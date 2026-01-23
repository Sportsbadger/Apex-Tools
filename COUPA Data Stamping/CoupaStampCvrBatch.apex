// =====================================================
// 1) Batch: CoupaStampCvrBatch  
// =====================================================
global class CoupaStampCvrBatch implements Database.Batchable<SObject>, Database.Stateful {

    global final DateTime startDt;
    global final DateTime endDt;

    // Placeholder for your future Step 2 chaining (off by default)
    global final Boolean chainStep2;

    // Optional counters (handy in Apex Jobs / logs)
    global Integer scanned = 0;
    global Integer stamped = 0;
    global Integer unmatched = 0;
    global Integer ambiguous = 0;

    // Debug toggle 
    public static final Boolean DEBUG = false;
    public static final Integer DEBUG_SAMPLE_SIZE = 25;

    global Set<String> dbgWbsSeen = new Set<String>();
    global List<String> dbgSampleStamped = new List<String>();
    global List<String> dbgSampleUnmatched = new List<String>();
    global List<String> dbgSampleAmbiguous = new List<String>();

    global CoupaStampCvrBatch(DateTime startDt, DateTime endDt, Boolean chainStep2) {
        this.startDt = startDt;
        this.endDt   = endDt;
        this.chainStep2 = chainStep2;
    }

    global CoupaStampCvrBatch(DateTime startDt, DateTime endDt) {
        this(startDt, endDt, false);
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        // NOTE: include Project__c so we can stamp it
        String soql =
            'SELECT Id, Name, L4_WBS__c, CVR__c, Project__c ' +
            'FROM Coupa_Data__c ' +
            'WHERE CreatedDate >= :startDt ' +
            'AND CreatedDate < :endDt ' +
            'AND CVR__c = NULL ' +
            'AND L4_WBS__c != NULL';

        if (DEBUG) {
            System.debug(LoggingLevel.INFO,
                'CoupaStampCvrBatch.start window=[' + startDt + ' .. ' + endDt + ') soql=' + soql
            );
        }

        return Database.getQueryLocator(soql);
    }

    global void execute(Database.BatchableContext bc, List<Coupa_Data__c> scope) {
        scanned += scope.size();

        // Collect normalized WBS codes from this scope
        Set<String> wbsCodes = new Set<String>();
        for (Coupa_Data__c r : scope) {
            String w = (r.L4_WBS__c == null) ? null : r.L4_WBS__c.trim();
            if (!String.isBlank(w)) {
                wbsCodes.add(w);
                if (DEBUG && dbgWbsSeen.size() < DEBUG_SAMPLE_SIZE) dbgWbsSeen.add(w);
            }
        }
        if (wbsCodes.isEmpty()) return;

        // Map WBS -> CVR AND WBS -> Project; track ambiguous WBS
        Map<String, Id> wbsToCvr = new Map<String, Id>();
        Map<String, Id> wbsToProject = new Map<String, Id>();
        Set<String> ambiguousWbs = new Set<String>();

        for (Project_WBS__c m : [
            SELECT WBS_Code__c, CVR__c, Project__c
            FROM Project_WBS__c
            WHERE WBS_Code__c IN :wbsCodes
              AND CVR__c != NULL
              AND Project__c != NULL
        ]) {
            String w = (m.WBS_Code__c == null) ? null : m.WBS_Code__c.trim();
            if (String.isBlank(w)) continue;

            Id cvrId = m.CVR__c;
            Id projectId = m.Project__c;

            if (!wbsToCvr.containsKey(w)) {
                wbsToCvr.put(w, cvrId);
                wbsToProject.put(w, projectId);
            } else {
                // Ambiguous if either CVR or Project differs for same WBS
                if (wbsToCvr.get(w) != cvrId || wbsToProject.get(w) != projectId) {
                    ambiguousWbs.add(w);
                }
            }
        }

        if (DEBUG) {
            System.debug(LoggingLevel.INFO,
                'CoupaStampCvrBatch.execute scope=' + scope.size() +
                ' uniqueWbs=' + wbsCodes.size() +
                ' mappingsFound=' + wbsToCvr.size() +
                ' ambiguousWbs=' + ambiguousWbs.size()
            );
        }

        List<Coupa_Data__c> updates = new List<Coupa_Data__c>();

        for (Coupa_Data__c r : scope) {
            String w = (r.L4_WBS__c == null) ? null : r.L4_WBS__c.trim();
            if (String.isBlank(w)) {
                unmatched++;
                if (DEBUG && dbgSampleUnmatched.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleUnmatched.add('Id=' + r.Id + ' WBS=<blank>');
                }
                continue;
            }

            if (ambiguousWbs.contains(w)) {
                ambiguous++;
                if (DEBUG && dbgSampleAmbiguous.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleAmbiguous.add('Id=' + r.Id + ' WBS=' + w);
                }
                continue;
            }

            Id cvrId = wbsToCvr.get(w);
            Id projectId = wbsToProject.get(w);

            if (cvrId != null && projectId != null) {
                r.CVR__c = cvrId;
                r.Project__c = projectId;
                updates.add(r);
                stamped++;

                if (DEBUG && dbgSampleStamped.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleStamped.add('Id=' + r.Id + ' WBS=' + w + ' -> CVR=' + cvrId + ' Project=' + projectId);
                }
            } else {
                unmatched++;
                if (DEBUG && dbgSampleUnmatched.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleUnmatched.add('Id=' + r.Id + ' WBS=' + w + ' (no mapping)');
                }
            }
        }

        if (!updates.isEmpty()) update updates;
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'CoupaStampCvrBatch finished. ' +
            'Window=[' + startDt + ' .. ' + endDt + '), ' +
            'scanned=' + scanned + ', stamped=' + stamped +
            ', unmatched=' + unmatched + ', ambiguous=' + ambiguous
        );

        if (DEBUG) {
            System.debug(LoggingLevel.INFO, 'CoupaStampCvrBatch DEBUG WBS sample: ' + new List<String>(dbgWbsSeen));
            System.debug(LoggingLevel.INFO, 'CoupaStampCvrBatch DEBUG stamped sample: ' + dbgSampleStamped);
            System.debug(LoggingLevel.INFO, 'CoupaStampCvrBatch DEBUG unmatched sample: ' + dbgSampleUnmatched);
            System.debug(LoggingLevel.INFO, 'CoupaStampCvrBatch DEBUG ambiguous sample: ' + dbgSampleAmbiguous);
        }

        // Future Step 2 hook (details later)
        if (chainStep2) {
            // e.g. Database.executeBatch(new CoupaStep2Batch(startDt, endDt), 200);
        }
    }
}
