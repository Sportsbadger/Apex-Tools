global class SapStampBillingLinesCvrBatch implements Database.Batchable<SObject>, Database.Stateful {

    global final DateTime startDt;
    global final DateTime endDt;

    // Optional counters
    global Integer scanned = 0;
    global Integer stamped = 0;
    global Integer unmatched = 0;
    global Integer ambiguous = 0;

    global SapStampBillingLinesCvrBatch(DateTime startDt, DateTime endDt) {
        this.startDt = startDt;
        this.endDt   = endDt;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Only Billing Lines in the window that still need stamping
        String soql =
            'SELECT Id, CVR__c, Project__c, WBS_Key__c, L4_WBS__c, Type__c, Billing_Document__c ' +
            'FROM SAP_Data__c ' +
            'WHERE CreatedDate >= :startDt ' +
            'AND CreatedDate < :endDt ' +
            'AND CVR__c = NULL ' +
            'AND Type__c = \'Billing Line\' ' +
            'AND Billing_Document__c != NULL';
        return Database.getQueryLocator(soql);
    }

    global void execute(Database.BatchableContext bc, List<SAP_Data__c> scope) {
        scanned += scope.size();

        // Collect Billing Document numbers from billing lines in this scope
        Set<String> billingDocs = new Set<String>();
        for (SAP_Data__c r : scope) {
            if (!String.isBlank(r.Billing_Document__c)) {
                billingDocs.add(r.Billing_Document__c.trim());
            }
        }
        if (billingDocs.isEmpty()) return;

        // Build "first wins" maps from COST LINES that are already stamped
        Map<String, Id>     docToCvr     = new Map<String, Id>();
        Map<String, Id>     docToProject = new Map<String, Id>();
        Map<String, String> docToKey     = new Map<String, String>();
        Map<String, String> docToWbs     = new Map<String, String>();

        // Deterministic tie-break: earliest-created cost line wins
        for (SAP_Data__c cost : [
            SELECT Billing_Document__c, CVR__c, Project__c, WBS_Key__c, L4_WBS__c, CreatedDate
            FROM SAP_Data__c
            WHERE Type__c = 'Cost Line'
              AND Billing_Document__c IN :billingDocs
              AND CVR__c != NULL
              AND Project__c != NULL
            ORDER BY CreatedDate ASC
        ]) {
            String doc = (cost.Billing_Document__c == null) ? null : cost.Billing_Document__c.trim();
            if (String.isBlank(doc)) continue;

            Id cvrId = cost.CVR__c;
            Id projectId = cost.Project__c;
            String key = (cost.WBS_Key__c == null) ? null : cost.WBS_Key__c.trim();
            String wbs = (cost.L4_WBS__c == null) ? null : cost.L4_WBS__c.trim();

            if (!docToCvr.containsKey(doc)) {
                docToCvr.put(doc, cvrId);
                docToProject.put(doc, projectId);
                docToKey.put(doc, key);
                docToWbs.put(doc, wbs);
            } else {
                // Count ambiguity if values differ for same Billing Doc, but keep first-wins stamping
                if (docToCvr.get(doc) != cvrId ||
                    docToProject.get(doc) != projectId ||
                    docToKey.get(doc) != key ||
                    docToWbs.get(doc) != wbs) {
                    ambiguous++;
                }
            }
        }

        // Stamp billing lines from the matched cost line data
        List<SAP_Data__c> updates = new List<SAP_Data__c>();

        for (SAP_Data__c bill : scope) {
            String doc = (bill.Billing_Document__c == null) ? null : bill.Billing_Document__c.trim();
            if (String.isBlank(doc)) {
                unmatched++;
                continue;
            }

            Id cvrId = docToCvr.get(doc);
            Id projectId = docToProject.get(doc);
            String key = docToKey.get(doc);
            String wbs = docToWbs.get(doc);

            if (cvrId == null || projectId == null) {
                unmatched++;
                continue;
            }

            Boolean changed = false;

            if (bill.CVR__c != cvrId) {
                bill.CVR__c = cvrId;
                changed = true;
            }
            if (bill.Project__c != projectId) {
                bill.Project__c = projectId;
                changed = true;
            }
            if (!String.isBlank(key)) {
                if (String.isBlank(bill.WBS_Key__c) || bill.WBS_Key__c.trim() != key) {
                    bill.WBS_Key__c = key;
                    changed = true;
                }
            }
            if (!String.isBlank(wbs)) {
                if (String.isBlank(bill.L4_WBS__c) || bill.L4_WBS__c.trim() != wbs) {
                    bill.L4_WBS__c = wbs;
                    changed = true;
                }
            }

            if (changed) {
                updates.add(bill);
                stamped++;
            }
        }

        if (!updates.isEmpty()) update updates;
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'SapStampBillingLinesCvrBatch finished. ' +
            'Window=[' + String.valueOf(startDt) + ' .. ' + String.valueOf(endDt) + '), ' +
            'scanned=' + scanned + ', stamped=' + stamped +
            ', unmatched=' + unmatched + ', ambiguous=' + ambiguous
        );
    }
}
