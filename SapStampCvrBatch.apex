global class SapStampCvrBatch implements Database.Batchable<SObject>, Database.Stateful {

    global final DateTime startDt;
    global final DateTime endDt;

    // When true, the billing-line batch will be started in finish()
    global final Boolean chainBilling;

    // Optional counters for logging/monitoring
    global Integer scanned = 0;
    global Integer stamped = 0;
    global Integer unmatched = 0;
    global Integer ambiguous = 0;

    // Primary constructor (allows orchestration control)
    global SapStampCvrBatch(DateTime startDt, DateTime endDt, Boolean chainBilling) {
        this.startDt = startDt;
        this.endDt   = endDt;
        this.chainBilling = chainBilling;
    }

    // Backwards-compatible constructor (no chaining by default)
    global SapStampCvrBatch(DateTime startDt, DateTime endDt) {
        this(startDt, endDt, false);
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Stamps CVR via WBS for types that should use L4_WBS__c matching.
        // Update this IN list as new WBS-driven SAP types are added.
        String soql =
            'SELECT Id, L4_WBS__c, CVR__c, Type__c ' +
            'FROM SAP_Data__c ' +
            'WHERE CreatedDate >= :startDt ' +
            'AND CreatedDate < :endDt ' +
            'AND CVR__c = NULL ' +
            'AND L4_WBS__c != NULL ' +
            'AND Type__c IN (\'Cost Line\', \'Aged Debt\')';

        return Database.getQueryLocator(soql);
    }

    global void execute(Database.BatchableContext bc, List<SAP_Data__c> scope) {
        scanned += scope.size();

        // Collect WBS codes from this scope
        Set<String> wbsCodes = new Set<String>();
        for (SAP_Data__c r : scope) {
            if (!String.isBlank(r.L4_WBS__c)) wbsCodes.add(r.L4_WBS__c);
        }
        if (wbsCodes.isEmpty()) return;

        // Build a map WBS -> CVR, tracking ambiguous WBS codes
        Map<String, Id> wbsToCvr = new Map<String, Id>();
        Set<String> ambiguousWbs = new Set<String>();

        for (Project_WBS__c m : [
            SELECT WBS_Code__c, CVR__c
            FROM Project_WBS__c
            WHERE WBS_Code__c IN :wbsCodes
              AND CVR__c != NULL
        ]) {
            String w = m.WBS_Code__c;
            Id cvrId = m.CVR__c;

            if (!wbsToCvr.containsKey(w)) {
                wbsToCvr.put(w, cvrId);
            } else if (wbsToCvr.get(w) != cvrId) {
                ambiguousWbs.add(w);
            }
        }

        // Stamp CVR__c (skip ambiguous WBS)
        List<SAP_Data__c> updates = new List<SAP_Data__c>();
        for (SAP_Data__c r : scope) {
            String w = r.L4_WBS__c;

            if (ambiguousWbs.contains(w)) {
                ambiguous++;
                continue;
            }

            Id cvrId = wbsToCvr.get(w);
            if (cvrId != null) {
                r.CVR__c = cvrId;
                updates.add(r);
                stamped++;
            } else {
                unmatched++;
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'SapStampCvrBatch finished. ' +
            'Window=[' + String.valueOf(startDt) + ' .. ' + String.valueOf(endDt) + '), ' +
            'scanned=' + scanned + ', stamped=' + stamped +
            ', unmatched=' + unmatched + ', ambiguous=' + ambiguous
        );

        // Orchestrate: only kick Billing Lines batch if requested
        if (chainBilling) {
            Database.executeBatch(
                new SapStampBillingLinesCvrBatch(startDt, endDt),
                200
            );
        }
    }
}
