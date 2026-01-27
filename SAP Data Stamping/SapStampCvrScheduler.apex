global class SapStampCvrScheduler implements Schedulable {

    // Fallbacks if CMDT is missing
    public static final Integer DEFAULT_CUTOFF_HOUR = 3; // 03:00
    public static final Integer DEFAULT_BACKFILL_DAYS = 7;

    global void execute(SchedulableContext sc) {
        // Production path
        runForReferenceDateTime(DateTime.now());
    }

    @TestVisible
    static void runForReferenceDateTime(DateTime referenceDt) {
        Sap_Stamp_Settings__mdt cfg = getConfig();

        Integer cutoffHour = (cfg != null && cfg.Cutover_Hour__c != null)
            ? Integer.valueOf(cfg.Cutover_Hour__c)
            : DEFAULT_CUTOFF_HOUR;

        String mode = (cfg != null && String.isNotBlank(cfg.Mode__c))
            ? cfg.Mode__c
            : 'Cutover';

        Integer backfillDays = (cfg != null && cfg.Backfill_Days__c != null)
            ? Integer.valueOf(cfg.Backfill_Days__c)
            : DEFAULT_BACKFILL_DAYS;

        DateTime startDt;
        DateTime endDt;

        if (mode == 'Backfill') {
            endDt = DateTime.now();
            startDt = endDt.addDays(-backfillDays);
        } else {
            // Cutover window: most recent cutoff at or before referenceDt
            Date refDate = referenceDt.date();
            endDt = DateTime.newInstance(refDate, Time.newInstance(cutoffHour, 0, 0, 0));
            if (referenceDt < endDt) {
                endDt = endDt.addDays(-1);
            }
            startDt = endDt.addDays(-1);
        }

        Database.executeBatch(
            new SapStampCvrBatch(startDt, endDt, true), // chain billing in finish()
            1000
        );
    }

    // Reads CMDT record Sap_Stamp_Settings__mdt.Default
    @TestVisible
    static Sap_Stamp_Settings__mdt getConfig() {
        // getInstance works without SOQL
        return Sap_Stamp_Settings__mdt.getInstance('Default');
    }

    public static void scheduleDaily(String jobName, Integer hour24, Integer minute) {
        String cron = String.format(
            '0 {0} {1} * * ?',
            new List<String>{ String.valueOf(minute), String.valueOf(hour24) }
        );
        System.schedule(jobName, cron, new SapStampCvrScheduler());
    }

    // One-time helper: schedule today at a chosen time
    public static void scheduleTodayAt(String jobName, Integer hour24, Integer minute) {
        Date d = Date.today();
        String cron = String.format(
            '0 {0} {1} {2} {3} ?',
            new List<String>{
                String.valueOf(minute),
                String.valueOf(hour24),
                String.valueOf(d.day()),
                String.valueOf(d.month())
            }
        );
        System.schedule(jobName, cron, new SapStampCvrScheduler());
    }
}
