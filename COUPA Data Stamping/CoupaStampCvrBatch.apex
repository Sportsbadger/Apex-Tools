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
        // Include WBS_Key__c so we can stamp it too
        String soql =
            'SELECT Id, Name, L4_WBS__c, WBS_Key__c, CVR__c, Project__c ' +
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

        // Build maps WBS -> CVR/Project/WBS_Key
        // If WBS reused, keep first mapping deterministically and count ambiguity.
        Map<String, Id>     wbsToCvr     = new Map<String, Id>();
        Map<String, Id>     wbsToProject = new Map<String, Id>();
        Map<String, String> wbsToKey     = new Map<String, String>();

        for (Project_WBS__c m : [
            SELECT WBS_Code__c, WBS_Key__c, CVR__c, Project__c, CreatedDate
            FROM Project_WBS__c
            WHERE WBS_Code__c IN :wbsCodes
              AND CVR__c != NULL
              AND Project__c != NULL
              AND WBS_Key__c != NULL
            ORDER BY CreatedDate ASC
        ]) {
            String w = (m.WBS_Code__c == null) ? null : m.WBS_Code__c.trim();
            if (String.isBlank(w)) continue;

            Id cvrId = m.CVR__c;
            Id projectId = m.Project__c;
            String key = (m.WBS_Key__c == null) ? null : m.WBS_Key__c.trim();
            if (String.isBlank(key)) continue;

            if (!wbsToCvr.containsKey(w)) {
                // first mapping wins
                wbsToCvr.put(w, cvrId);
                wbsToProject.put(w, projectId);
                wbsToKey.put(w, key);
            } else {
                // count ambiguity but do NOT block stamping
                if (wbsToCvr.get(w) != cvrId || wbsToProject.get(w) != projectId || wbsToKey.get(w) != key) {
                    ambiguous++;
                    if (DEBUG && dbgSampleAmbiguous.size() < DEBUG_SAMPLE_SIZE) {
                        dbgSampleAmbiguous.add(
                            'WBS=' + w +
                            ' existing(CVR=' + wbsToCvr.get(w) + ', Project=' + wbsToProject.get(w) + ', Key=' + wbsToKey.get(w) + ')' +
                            ' vs new(CVR=' + cvrId + ', Project=' + projectId + ', Key=' + key + ')'
                        );
                    }
                }
            }
        }

        if (DEBUG) {
            System.debug(LoggingLevel.INFO,
                'CoupaStampCvrBatch.execute scope=' + scope.size() +
                ' uniqueWbs=' + wbsCodes.size() +
                ' mappingsFound=' + wbsToCvr.size() +
                ' ambiguousSeen=' + ambiguous
            );
        }

        // Stamp CVR__c + Project__c + WBS_Key__c (only when changed)
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

            Id cvrId = wbsToCvr.get(w);
            Id projectId = wbsToProject.get(w);
            String key = wbsToKey.get(w);

            if (cvrId != null && projectId != null && !String.isBlank(key)) {
                Boolean changed = false;

                if (r.CVR__c != cvrId) {
                    r.CVR__c = cvrId;
                    changed = true;
                }
                if (r.Project__c != projectId) {
                    r.Project__c = projectId;
                    changed = true;
                }
                if (String.isBlank(r.WBS_Key__c) || r.WBS_Key__c.trim() != key) {
                    r.WBS_Key__c = key;
                    changed = true;
                }

                if (changed) {
                    updates.add(r);
                    stamped++;
                    if (DEBUG && dbgSampleStamped.size() < DEBUG_SAMPLE_SIZE) {
                        dbgSampleStamped.add(
                            'Id=' + r.Id + ' WBS=' + w +
                            ' -> CVR=' + cvrId + ' Project=' + projectId + ' Key=' + key
                        );
                    }
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
