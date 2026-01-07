global class SapStampCvrBatch implements Database.Batchable<SObject>, Database.Stateful {

    global final DateTime startDt;
    global final DateTime endDt;

    // Optional counters for logging/monitoring
    global Integer scanned = 0;
    global Integer stamped = 0;
    global Integer unmatched = 0;
    global Integer ambiguous = 0;

    global SapStampCvrBatch(DateTime startDt, DateTime endDt) {
        this.startDt = startDt;
        this.endDt   = endDt;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String soql =
            'SELECT Id, L4_WBS__c, CVR__c ' +
            'FROM SAP_Data__c ' +
            'WHERE CreatedDate >= :startDt ' +
            'AND CreatedDate < :endDt ' +
            'AND CVR__c = NULL ' +
            'AND L4_WBS__c != NULL';
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

        // Map WBS -> CVR, track ambiguous WBS
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

        // Stamp CVR__c
        List<SAP_Data__c> updates = new List<SAP_Data__c>();
        for (SAP_Data__c r : scope) {
            if (ambiguousWbs.contains(r.L4_WBS__c)) {
                ambiguous++;
                continue;
            }

            Id cvrId = wbsToCvr.get(r.L4_WBS__c);
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
    }
}
