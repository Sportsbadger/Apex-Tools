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

    // Toggle to enable/disable debug logging without changing logic
    public static final Boolean DEBUG = false;

    // How many sample rows to log per category
    public static final Integer DEBUG_SAMPLE_SIZE = 25;

    // Store a small sample of records for finish() logging (Stateful)
    global List<String> dbgSampleStamped = new List<String>();
    global List<String> dbgSampleUnmatched = new List<String>();
    global List<String> dbgSampleAmbiguous = new List<String>();

    global Set<String> dbgWbsSeen = new Set<String>(); // track unique WBS seen (sample)

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String soql =
            'SELECT Id, L4_WBS__c, CVR__c, Project__c, Type__c ' +
            'FROM SAP_Data__c ' +
            'WHERE CreatedDate >= :startDt ' +
            'AND CreatedDate < :endDt ' +
            'AND CVR__c = NULL ' +
            'AND L4_WBS__c != NULL ' +
            'AND Type__c IN (\'Cost Line\', \'Aged Debt\')';

        if (DEBUG) {
            System.debug(LoggingLevel.INFO,
                'SapStampCvrBatch.start window=[' + startDt + ' .. ' + endDt + ') soql=' + soql
            );
        }

        return Database.getQueryLocator(soql);
    }

    global void execute(Database.BatchableContext bc, List<SAP_Data__c> scope) {
        scanned += scope.size();

        // Collect normalized WBS codes from this scope
        Set<String> wbsCodes = new Set<String>();
        for (SAP_Data__c r : scope) {
            String w = (r.L4_WBS__c == null) ? null : r.L4_WBS__c.trim();
            if (!String.isBlank(w)) {
                wbsCodes.add(w);
                if (DEBUG && dbgWbsSeen.size() < DEBUG_SAMPLE_SIZE) dbgWbsSeen.add(w);
            }
        }
        if (wbsCodes.isEmpty()) return;

        // Build map WBS -> CVR and WBS -> Project, tracking ambiguous WBS codes
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

            // Ambiguity check: same WBS mapping to different CVR/Project
            if (!wbsToCvr.containsKey(w)) {
                wbsToCvr.put(w, cvrId);
                wbsToProject.put(w, projectId);
            } else {
                if (wbsToCvr.get(w) != cvrId || wbsToProject.get(w) != projectId) {
                    ambiguousWbs.add(w);
                }
            }
        }

        if (DEBUG) {
            System.debug(LoggingLevel.INFO,
                'SapStampCvrBatch.execute scope=' + scope.size() +
                ' uniqueWbs=' + wbsCodes.size() +
                ' mappingsFound=' + wbsToCvr.size() +
                ' ambiguousWbs=' + ambiguousWbs.size()
            );
        }

        // Stamp CVR__c + Project__c (skip ambiguous WBS)
        List<SAP_Data__c> updates = new List<SAP_Data__c>();

        for (SAP_Data__c r : scope) {
            String w = (r.L4_WBS__c == null) ? null : r.L4_WBS__c.trim();

            if (String.isBlank(w)) {
                unmatched++;
                if (DEBUG && dbgSampleUnmatched.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleUnmatched.add('Id=' + r.Id + ' Type=' + r.Type__c + ' WBS=<blank>');
                }
                continue;
            }

            if (ambiguousWbs.contains(w)) {
                ambiguous++;
                if (DEBUG && dbgSampleAmbiguous.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleAmbiguous.add('Id=' + r.Id + ' Type=' + r.Type__c + ' WBS=' + w);
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
                    dbgSampleStamped.add(
                        'Id=' + r.Id + ' Type=' + r.Type__c + ' WBS=' + w +
                        ' -> CVR=' + cvrId + ' Project=' + projectId
                    );
                }
            } else {
                unmatched++;
                if (DEBUG && dbgSampleUnmatched.size() < DEBUG_SAMPLE_SIZE) {
                    dbgSampleUnmatched.add('Id=' + r.Id + ' Type=' + r.Type__c + ' WBS=' + w + ' (no mapping)');
                }
            }
        }

        if (!updates.isEmpty()) update updates;
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'SapStampCvrBatch finished. ' +
            'Window=[' + startDt + ' .. ' + endDt + '), ' +
            'scanned=' + scanned + ', stamped=' + stamped +
            ', unmatched=' + unmatched + ', ambiguous=' + ambiguous
        );

        if (DEBUG) {
            System.debug(LoggingLevel.INFO, 'SapStampCvrBatch DEBUG WBS sample: ' + new List<String>(dbgWbsSeen));
            System.debug(LoggingLevel.INFO, 'SapStampCvrBatch DEBUG stamped sample: ' + dbgSampleStamped);
            System.debug(LoggingLevel.INFO, 'SapStampCvrBatch DEBUG unmatched sample: ' + dbgSampleUnmatched);
            System.debug(LoggingLevel.INFO, 'SapStampCvrBatch DEBUG ambiguous sample: ' + dbgSampleAmbiguous);
        }

        if (chainBilling) {
            Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
        }
    }
}
