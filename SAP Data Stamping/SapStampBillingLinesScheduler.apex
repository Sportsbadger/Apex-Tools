global class SapStampBillingLinesScheduler implements Schedulable {

    public static final Integer CUTOFF_HOUR = 3; // 03:00

    global void execute(SchedulableContext sc) {
        runForReferenceDateTime(DateTime.now());
    }

    @TestVisible
    static void runForReferenceDateTime(DateTime referenceDt) {
        Date refDate = referenceDt.date();

        DateTime endDt = DateTime.newInstance(
            refDate,
            Time.newInstance(CUTOFF_HOUR, 0, 0, 0)
        );

        // If we haven't reached today's cutoff yet, roll back one day
        if (referenceDt < endDt) {
            endDt = endDt.addDays(-1);
        }

        DateTime startDt = endDt.addDays(-1);

        Integer batchSize = 200;
        Database.executeBatch(
            new SapStampBillingLinesCvrBatch(startDt, endDt),
            batchSize
        );
    }

    public static void scheduleDaily(String jobName, Integer hour24, Integer minute) {
        String cron = String.format(
            '0 {0} {1} * * ?',
            new List<String>{ String.valueOf(minute), String.valueOf(hour24) }
        );
        System.schedule(jobName, cron, new SapStampBillingLinesScheduler());
    }
}
