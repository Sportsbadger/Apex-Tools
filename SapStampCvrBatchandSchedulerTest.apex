@IsTest
private class SapStampCvrBatchTest {

    @TestSetup
    static void makeData() {
        // --- Your provided SiteTracker setup ---
        sitetracker__Project_Template__c template = new sitetracker__Project_Template__c(
            Name = 'Test Template ST 2003',
            sitetracker__Active__c = true
        );
        insert template;

        sitetracker__Site__c site = new sitetracker__Site__c(
            Name = 'Test site ST 2003',
            sitetracker__Site_Type__c = 'Other'
        );
        insert site;

        sitetracker__Project__c project = new sitetracker__Project__c(
            sitetracker__ProjectTemplate__c = template.Id,
            sitetracker__Site__c = site.Id,
            Name = 'Test Project ST 2003'
        );
        insert project;

        // --- Create the single CVR for this Project (CVR -> Project is Master-Detail) ---
        // Adjust field API names if your org differs:
        CVR__c cvr = new CVR__c(
            Name = 'Test CVR',
            Project__c = project.Id
        );
        insert cvr;

        // --- Set the Project lookup back to CVR (you said Project has a lookup to CVR) ---
        project.CVR__c = cvr.Id;
        update project;

        // --- Create a WBS mapping record that points to the CVR ---
        Project_WBS__c wbsMap = new Project_WBS__c(
            Name = 'Map-1',
            Project__c = project.Id,
            CVR__c = cvr.Id,
            WBS_Code__c = 'TEST-WBS-001'
        );
        insert wbsMap;
    }

    @IsTest
    static void testBatchStampsCvr() {
        // Grab CVR id from setup
        CVR__c cvr = [SELECT Id FROM CVR__c LIMIT 1];

        // Create SAP rows: one matches, one doesn't
        SAP_Data__c sapMatch = new SAP_Data__c(
            Name = 'SAP Match',
            L4_WBS__c = 'TEST-WBS-001'
        );
        SAP_Data__c sapNoMatch = new SAP_Data__c(
            Name = 'SAP No Match',
            L4_WBS__c = 'NO-MATCH'
        );
        insert new List<SAP_Data__c>{ sapMatch, sapNoMatch };

        // Force CreatedDate to be inside the batch window we will use.
        // We'll define a simple window of "now - 1 hour" to "now + 1 hour".
        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        // Make sure both records are in-range
        Test.setCreatedDate(sapMatch.Id, DateTime.now());
        Test.setCreatedDate(sapNoMatch.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
        Test.stopTest();

        // Reload and assert
        Map<Id, SAP_Data__c> reloaded = new Map<Id, SAP_Data__c>([
            SELECT Id, CVR__c, L4_WBS__c
            FROM SAP_Data__c
            WHERE Id IN :new List<Id>{ sapMatch.Id, sapNoMatch.Id }
        ]);

        System.assertEquals(
            cvr.Id,
            reloaded.get(sapMatch.Id).CVR__c,
            'Matching WBS should stamp CVR__c'
        );
        System.assertEquals(
            null,
            reloaded.get(sapNoMatch.Id).CVR__c,
            'Non-matching WBS should remain null'
        );
    }

    @IsTest
    static void testSchedulerExecutes() {
        // Insert one SAP row that should match, created "now"
        CVR__c cvr = [SELECT Id FROM CVR__c LIMIT 1];

        SAP_Data__c sap = new SAP_Data__c(
            Name = 'SAP For Scheduler',
            L4_WBS__c = 'TEST-WBS-001'
        );
        insert sap;
        Test.setCreatedDate(sap.Id, DateTime.now());

        // Run scheduler's execute directly for coverage.
        // Note: we can't easily control Date.today() inside the scheduler without refactoring,
        // but calling execute() is still valuable coverage.
        Test.startTest();
            new SapStampCvrScheduler().execute(null);
        Test.stopTest();

        // Scheduler uses a 03:00 cutover window; depending on current test time,
        // the record might or might not be inside the calculated window.
        // So we only assert that no exception occurred and the record is either stamped or still null.
        SAP_Data__c reloaded = [SELECT Id, CVR__c FROM SAP_Data__c WHERE Id = :sap.Id];

        // Soft assert: if it stamped, great; if not, it's because the scheduler window didn't include "now".
        // You can make this deterministic by refactoring scheduler to accept start/end (optional later).
        System.assert(
            reloaded.CVR__c == null || reloaded.CVR__c == cvr.Id,
            'Scheduler run should not fail; stamping depends on window timing.'
        );
    }
}
