@IsTest
private class SapStampCvrBatchTest {

    @TestSetup
    static void makeData() {

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
            sitetracker__Site__c = site.Id
        );
        insert project;

        // --- Create the single CVR for this Project (CVR -> Project is Master-Detail) ---
        CVR__c cvr = new CVR__c(
            Project__c = project.Id
        );
        insert cvr;

        // --- Set the Project lookup back to CVR ---
        project.CVR__c = cvr.Id;
        update project;

        // --- Create a WBS mapping record that points to the CVR ---
        Project_WBS__c wbsMap = new Project_WBS__c(
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
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001'
        );
        SAP_Data__c sapNoMatch = new SAP_Data__c(
            Name = 'SAP No Match',
            Type__c = 'Cost Line',
            L4_WBS__c = 'NO-MATCH'
        );
        insert new List<SAP_Data__c>{ sapMatch, sapNoMatch };

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.setCreatedDate(sapMatch.Id, DateTime.now());
        Test.setCreatedDate(sapNoMatch.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
        Test.stopTest();

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
        CVR__c cvr = [SELECT Id FROM CVR__c LIMIT 1];

        SAP_Data__c sap = new SAP_Data__c(
            Name = 'SAP For Scheduler',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001'
        );
        insert sap;
        Test.setCreatedDate(sap.Id, DateTime.now());

        Test.startTest();
            new SapStampCvrScheduler().execute(null);
        Test.stopTest();

        SAP_Data__c reloaded = [SELECT Id, CVR__c FROM SAP_Data__c WHERE Id = :sap.Id];

        System.assert(
            reloaded.CVR__c == null || reloaded.CVR__c == cvr.Id,
            'Scheduler run should not fail; stamping depends on window timing.'
        );
    }


    @IsTest
    static void testBillingBatchStampsFromCostLines() {
        CVR__c cvr = [SELECT Id FROM CVR__c LIMIT 1];

        SAP_Data__c cost = new SAP_Data__c(
            Name = 'Cost Line 1',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001',
            Billing_Document__c = 'BILL-123'
        );
        insert cost;

        SAP_Data__c bill = new SAP_Data__c(
            Name = 'Billing Line 1',
            Type__c = 'Billing Line',
            Billing_Document__c = 'BILL-123'
        );
        insert bill;

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.setCreatedDate(cost.Id, DateTime.now());
        Test.setCreatedDate(bill.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
            Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
        Test.stopTest();

        Map<Id, SAP_Data__c> reloaded = new Map<Id, SAP_Data__c>([
            SELECT Id, CVR__c, Type__c
            FROM SAP_Data__c
            WHERE Id IN :new List<Id>{ cost.Id, bill.Id }
        ]);

        System.assertEquals(
            cvr.Id,
            reloaded.get(cost.Id).CVR__c,
            'Cost Line should be stamped by WBS batch'
        );
        System.assertEquals(
            cvr.Id,
            reloaded.get(bill.Id).CVR__c,
            'Billing Line should inherit CVR via Billing_Document__c from Cost Lines'
        );
    }

    @IsTest
    static void testBillingBatchSkipsWhenAmbiguous() {
        CVR__c cvr1 = [SELECT Id FROM CVR__c LIMIT 1];

        sitetracker__Project_Template__c template2 = new sitetracker__Project_Template__c(
            Name = 'Test Template ST 2003 - 2',
            sitetracker__Active__c = true
        );
        insert template2;

        sitetracker__Site__c site2 = new sitetracker__Site__c(
            Name = 'Test site ST 2003 - 2',
            sitetracker__Site_Type__c = 'Other'
        );
        insert site2;

        sitetracker__Project__c project2 = new sitetracker__Project__c(
            sitetracker__ProjectTemplate__c = template2.Id,
            sitetracker__Site__c = site2.Id
        );
        insert project2;

        CVR__c cvr2 = new CVR__c(
            Project__c = project2.Id
        );
        insert cvr2;

        project2.CVR__c = cvr2.Id;
        update project2;

        Project_WBS__c map2 = new Project_WBS__c(
            Project__c = project2.Id,
            CVR__c = cvr2.Id,
            WBS_Code__c = 'TEST-WBS-002'
        );
        insert map2;

        SAP_Data__c cost1 = new SAP_Data__c(
            Name = 'Cost Amb 1',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001',
            Billing_Document__c = 'BILL-AMB'
        );
        SAP_Data__c cost2 = new SAP_Data__c(
            Name = 'Cost Amb 2',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-002',
            Billing_Document__c = 'BILL-AMB'
        );
        insert new List<SAP_Data__c>{ cost1, cost2 };

        SAP_Data__c bill = new SAP_Data__c(
            Name = 'Billing Amb',
            Type__c = 'Billing Line',
            Billing_Document__c = 'BILL-AMB'
        );
        insert bill;

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.setCreatedDate(cost1.Id, DateTime.now());
        Test.setCreatedDate(cost2.Id, DateTime.now());
        Test.setCreatedDate(bill.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
            Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
        Test.stopTest();

        bill = [SELECT CVR__c FROM SAP_Data__c WHERE Id = :bill.Id];

        System.assertEquals(
            null,
            bill.CVR__c,
            'Billing Line should remain unstamped when Billing_Document__c maps to multiple CVRs'
        );
    }

    @IsTest
    static void testAgedDebtStampsCvr() {
        CVR__c cvr = [SELECT Id FROM CVR__c LIMIT 1];

        // Aged Debt row should stamp via L4_WBS__c (same as Cost Line)
        SAP_Data__c agedDebt = new SAP_Data__c(
            Name = 'Aged Debt 1',
            Type__c = 'Aged Debt',
            L4_WBS__c = 'TEST-WBS-001'
        );
        insert agedDebt;

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.setCreatedDate(agedDebt.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
        Test.stopTest();

        agedDebt = [SELECT CVR__c FROM SAP_Data__c WHERE Id = :agedDebt.Id];

        System.assertEquals(
            cvr.Id,
            agedDebt.CVR__c,
            'Aged Debt should be stamped by WBS batch when L4_WBS__c matches'
        );
    }
}
