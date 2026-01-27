global class CVRProjectTotalsRollupScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        // batch size, optional
        CVRProjectTotalsRollupService.run(1000);
    }

    public static void scheduleDaily(String jobName, Integer hour24, Integer minute) {
        String cron = String.format(
            '0 {0} {1} * * ?',
            new List<String>{ String.valueOf(minute), String.valueOf(hour24) }
        );
        System.schedule(jobName, cron, new CVRProjectTotalsRollupScheduler());
    }
}
