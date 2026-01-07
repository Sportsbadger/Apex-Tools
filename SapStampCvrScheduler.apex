global class SapStampCvrScheduler implements Schedulable {

    public static final Integer CUTOFF_HOUR = 3; // 03:00

    global void execute(SchedulableContext sc) {
        Date today = Date.today();
        DateTime endDt = DateTime.newInstance(today, Time.newInstance(CUTOFF_HOUR, 0, 0, 0));
        DateTime startDt = endDt.addDays(-1);

        // Batch size: 200 is a good default; bump to 500 if you want fewer execute calls
        Integer batchSize = 200;

        Database.executeBatch(new SapStampCvrBatch(startDt, endDt), batchSize);
    }

    public static void scheduleDaily(String jobName, Integer hour24, Integer minute) {
        String cron = String.format('0 {0} {1} * * ?',
            new List<String>{ String.valueOf(minute), String.valueOf(hour24) }
        );
        System.schedule(jobName, cron, new SapStampCvrScheduler());
    }
}
