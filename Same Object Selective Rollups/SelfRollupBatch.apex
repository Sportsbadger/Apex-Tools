global class SelfRollupBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Operation constants (avoid enums/keywords entirely)
    public static final String OP_SUM   = 'SUM';
    public static final String OP_COUNT = 'COUNT';
    public static final String OP_MAX   = 'MAX';
    public static final String OP_MIN   = 'MIN';

    global class RollupOp {
        global String operation;   // one of OP_SUM/OP_COUNT/OP_MAX/OP_MIN
        global String childField;  // null for COUNT
        global String parentField; // required

        global RollupOp(String operation, String childField, String parentField) {
            this.operation  = operation;
            this.childField = childField;
            this.parentField = parentField;
        }
    }

    global class Spec {
        global String objectApiName;             // e.g. 'CVR__c'
        global String parentLookupFieldApiName;  // e.g. 'Parent_CVR__c'
        global String childWhereClause;          // without 'WHERE' (optional)
        global String parentWhereClause;         // without 'WHERE' (optional)
        global Boolean onlyParentsWithChildren;  // if true, uses a semi-join to limit parents
        global Boolean zeroParentsWithNoChildren;// if true, sets target fields to 0/null for parents with no children
        global List<RollupOp> ops;
        global Integer batchSize;

        global Spec() {
            onlyParentsWithChildren = true;
            zeroParentsWithNoChildren = false;
            ops = new List<RollupOp>();
            batchSize = 200;
        }
    }

    global final Spec spec;

    global Integer parentsScanned = 0;
    global Integer parentsUpdated = 0;

    global SelfRollupBatch(Spec spec) {
        this.spec = spec;
        validateSpec(spec);
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String parentSoql = 'SELECT Id FROM ' + spec.objectApiName;

        List<String> whereParts = new List<String>();

        if (!String.isBlank(spec.parentWhereClause)) {
            whereParts.add('(' + spec.parentWhereClause + ')');
        }

        if (spec.onlyParentsWithChildren) {
            String sub = 'SELECT ' + spec.parentLookupFieldApiName +
                         ' FROM ' + spec.objectApiName +
                         ' WHERE ' + spec.parentLookupFieldApiName + ' != NULL';

            if (!String.isBlank(spec.childWhereClause)) {
                sub += ' AND (' + spec.childWhereClause + ')';
            }

            whereParts.add('Id IN (' + sub + ')');
        }

        if (!whereParts.isEmpty()) {
            parentSoql += ' WHERE ' + String.join(whereParts, ' AND ');
        }

        return Database.getQueryLocator(parentSoql);
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        parentsScanned += scope.size();
        if (scope.isEmpty()) return;

        Set<Id> parentIds = new Set<Id>();
        for (SObject p : scope) parentIds.add((Id)p.get('Id'));

        // Build aggregate query
        String selectPart = 'SELECT ' + spec.parentLookupFieldApiName + ' parentId';

        List<String> aliases = new List<String>();
        Integer i = 0;

        for (RollupOp op : spec.ops) {
            i++;
            String alias = 'a' + i;
            aliases.add(alias);

            if (op.operation == OP_COUNT) {
                selectPart += ', COUNT(Id) ' + alias;
            } else {
                selectPart += ', ' + op.operation + '(' + op.childField + ') ' + alias;
            }
        }

        String aggSoql =
            selectPart +
            ' FROM ' + spec.objectApiName +
            ' WHERE ' + spec.parentLookupFieldApiName + ' IN :parentIds';

        if (!String.isBlank(spec.childWhereClause)) {
            aggSoql += ' AND (' + spec.childWhereClause + ')';
        }

        aggSoql += ' GROUP BY ' + spec.parentLookupFieldApiName;

        List<AggregateResult> ars = Database.query(aggSoql);

        Map<Id, AggregateResult> byParent = new Map<Id, AggregateResult>();
        for (AggregateResult ar : ars) {
            Id pid = (Id)ar.get('parentId');
            if (pid != null) byParent.put(pid, ar);
        }

        SObjectType t = Schema.getGlobalDescribe().get(spec.objectApiName);
        List<SObject> updates = new List<SObject>();

        for (Id pid : parentIds) {
            AggregateResult ar = byParent.get(pid);

            if (ar == null && !spec.zeroParentsWithNoChildren) continue;

            SObject upd = t.newSObject(pid);

            for (Integer idx = 0; idx < spec.ops.size(); idx++) {
                RollupOp op = spec.ops[idx];
                String alias = aliases[idx];

                Object raw = (ar == null) ? null : ar.get(alias);

                if (ar == null) {
                    if (op.operation == OP_COUNT || op.operation == OP_SUM) {
                        upd.put(op.parentField, 0);
                    } else {
                        upd.put(op.parentField, null);
                    }
                } else {
                    upd.put(op.parentField, raw);
                }
            }

            updates.add(upd);
        }

        if (!updates.isEmpty()) {
            update updates;
            parentsUpdated += updates.size();
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'SelfRollupBatch finished. object=' + spec.objectApiName +
            ' parentsScanned=' + parentsScanned +
            ' parentsUpdated=' + parentsUpdated
        );
    }

    private static void validateSpec(Spec s) {
        if (s == null) throw new AuraHandledException('Spec is required');
        if (String.isBlank(s.objectApiName)) throw new AuraHandledException('Spec.objectApiName is required');
        if (String.isBlank(s.parentLookupFieldApiName)) throw new AuraHandledException('Spec.parentLookupFieldApiName is required');
        if (s.ops == null || s.ops.isEmpty()) throw new AuraHandledException('Spec.ops must have at least one operation');

        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey(s.objectApiName)) throw new AuraHandledException('Unknown object: ' + s.objectApiName);

        Schema.DescribeSObjectResult dor = gd.get(s.objectApiName).getDescribe();
        Map<String, Schema.SObjectField> fmap = dor.fields.getMap();

        if (!fmap.containsKey(s.parentLookupFieldApiName)) {
            throw new AuraHandledException('Unknown relationship field: ' + s.parentLookupFieldApiName);
        }

        Set<String> allowed = new Set<String>{ OP_SUM, OP_COUNT, OP_MAX, OP_MIN };

        for (RollupOp op : s.ops) {
            if (op == null) throw new AuraHandledException('Null operation not allowed');
            if (String.isBlank(op.parentField)) throw new AuraHandledException('Each op must define parentField');
            if (!fmap.containsKey(op.parentField)) throw new AuraHandledException('Unknown parentField: ' + op.parentField);

            if (String.isBlank(op.operation) || !allowed.contains(op.operation)) {
                throw new AuraHandledException('Unsupported op.operation: ' + op.operation + ' (use OP_SUM/OP_COUNT/OP_MAX/OP_MIN)');
            }

            if (op.operation != OP_COUNT) {
                if (String.isBlank(op.childField)) throw new AuraHandledException(op.operation + ' requires childField');
                if (!fmap.containsKey(op.childField)) throw new AuraHandledException('Unknown childField: ' + op.childField);
            }
        }
    }
}