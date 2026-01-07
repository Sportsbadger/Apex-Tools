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
        // Only Billing Lines in the window that still need CVR stamping
        String soql =
            'SELECT Id, CVR__c, Type__c, Billing_Document__c ' +
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

        // Build map BillingDoc -> CVR from COST LINES that are already stamped
        Map<String, Id> docToCvr = new Map<String, Id>();
        Set<String> ambiguousDocs = new Set<String>();

        // Query cost lines for those billing docs
        for (SAP_Data__c cost : [
            SELECT Billing_Document__c, CVR__c
            FROM SAP_Data__c
            WHERE Type__c = 'Cost Line'
              AND Billing_Document__c IN :billingDocs
              AND CVR__c != NULL
        ]) {
            String doc = (cost.Billing_Document__c == null) ? null : cost.Billing_Document__c.trim();
            if (String.isBlank(doc)) continue;

            Id cvrId = cost.CVR__c;

            if (!docToCvr.containsKey(doc)) {
                docToCvr.put(doc, cvrId);
            } else if (docToCvr.get(doc) != cvrId) {
                ambiguousDocs.add(doc);
            }
        }

        // Stamp billing lines, skipping ambiguous
        List<SAP_Data__c> updates = new List<SAP_Data__c>();

        for (SAP_Data__c bill : scope) {
            String doc = (bill.Billing_Document__c == null) ? null : bill.Billing_Document__c.trim();
            if (String.isBlank(doc)) {
                unmatched++;
                continue;
            }

            if (ambiguousDocs.contains(doc)) {
                ambiguous++;
                continue;
            }

            Id cvrId = docToCvr.get(doc);
            if (cvrId != null) {
                bill.CVR__c = cvrId;
                updates.add(bill);
                stamped++;
            } else {
                unmatched++;
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
