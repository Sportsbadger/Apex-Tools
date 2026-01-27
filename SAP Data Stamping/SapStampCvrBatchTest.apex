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

        CVR__c cvr = new CVR__c(
            Project__c = project.Id
        );
        insert cvr;

        project.CVR__c = cvr.Id;
        update project;

        // IMPORTANT: your SapStampCvrBatch requires WBS_Key__c to be non-null
        Project_WBS__c wbsMap = new Project_WBS__c(
            Project__c = project.Id,
            CVR__c = cvr.Id,
            WBS_Code__c = 'TEST-WBS-001',
            WBS_Key__c  = 'KEY-TEST-WBS-001'
        );
        insert wbsMap;
    }

    // -------------------------------------------------------------------------
    // Batch tests
    // -------------------------------------------------------------------------

    @IsTest
    static void testBatchStampsCvrProjectAndKey() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [SELECT WBS_Key__c FROM Project_WBS__c WHERE WBS_Code__c = 'TEST-WBS-001' LIMIT 1];

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
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt, false), 200);
        Test.stopTest();

        Map<Id, SAP_Data__c> reloaded = new Map<Id, SAP_Data__c>([
            SELECT Id, CVR__c, Project__c, WBS_Key__c, L4_WBS__c
            FROM SAP_Data__c
            WHERE Id IN :new List<Id>{ sapMatch.Id, sapNoMatch.Id }
        ]);

        System.assertEquals(cvr.Id, reloaded.get(sapMatch.Id).CVR__c, 'Matching WBS should stamp CVR__c');
        System.assertEquals(cvr.Project__c, reloaded.get(sapMatch.Id).Project__c, 'Matching WBS should stamp Project__c');
        System.assertEquals(map1.WBS_Key__c, reloaded.get(sapMatch.Id).WBS_Key__c, 'Matching WBS should stamp WBS_Key__c');

        System.assertEquals(null, reloaded.get(sapNoMatch.Id).CVR__c, 'Non-matching WBS should remain null');
        System.assertEquals(null, reloaded.get(sapNoMatch.Id).Project__c, 'Non-matching WBS Project__c should remain null');
        System.assertEquals(null, reloaded.get(sapNoMatch.Id).WBS_Key__c, 'Non-matching WBS_Key__c should remain null');
    }

    @IsTest
    static void testAgedDebtStampsCvrProjectAndKey() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [SELECT WBS_Key__c FROM Project_WBS__c WHERE WBS_Code__c = 'TEST-WBS-001' LIMIT 1];

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
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt, false), 200);
        Test.stopTest();

        agedDebt = [SELECT CVR__c, Project__c, WBS_Key__c FROM SAP_Data__c WHERE Id = :agedDebt.Id];

        System.assertEquals(cvr.Id, agedDebt.CVR__c, 'Aged Debt should stamp CVR__c');
        System.assertEquals(cvr.Project__c, agedDebt.Project__c, 'Aged Debt should stamp Project__c');
        System.assertEquals(map1.WBS_Key__c, agedDebt.WBS_Key__c, 'Aged Debt should stamp WBS_Key__c');
    }

    @IsTest
    static void testBillingBatchStampsFromCostLinesAndCopiesWbsAndKey() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [SELECT WBS_Key__c FROM Project_WBS__c WHERE WBS_Code__c = 'TEST-WBS-001' LIMIT 1];

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
            // Stamp cost line (CVR/Project/WBS_Key)
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt, false), 200);
            // Then stamp billing line from cost line data
            Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
        Test.stopTest();

        Map<Id, SAP_Data__c> reloaded = new Map<Id, SAP_Data__c>([
            SELECT Id, Type__c, CVR__c, Project__c, WBS_Key__c, L4_WBS__c
            FROM SAP_Data__c
            WHERE Id IN :new List<Id>{ cost.Id, bill.Id }
        ]);

        // Cost line
        System.assertEquals(cvr.Id, reloaded.get(cost.Id).CVR__c, 'Cost line should be stamped');
        System.assertEquals(cvr.Project__c, reloaded.get(cost.Id).Project__c, 'Cost line should have Project');
        System.assertEquals(map1.WBS_Key__c, reloaded.get(cost.Id).WBS_Key__c, 'Cost line should have WBS_Key');

        // Billing line inherits CVR/Project/Key and copies L4_WBS__c
        System.assertEquals(cvr.Id, reloaded.get(bill.Id).CVR__c, 'Billing line should inherit CVR');
        System.assertEquals(cvr.Project__c, reloaded.get(bill.Id).Project__c, 'Billing line should inherit Project');
        System.assertEquals(map1.WBS_Key__c, reloaded.get(bill.Id).WBS_Key__c, 'Billing line should inherit WBS_Key');
        System.assertEquals('TEST-WBS-001', reloaded.get(bill.Id).L4_WBS__c, 'Billing line should copy L4_WBS__c from cost line');
    }

    @IsTest
    static void testBillingBatchFirstWinsWhenAmbiguousDoc() {
        // Setup a second Project/CVR/Mapping to create different stamp values
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

        CVR__c cvr2 = new CVR__c(Project__c = project2.Id);
        insert cvr2;

        project2.CVR__c = cvr2.Id;
        update project2;

        Project_WBS__c map2 = new Project_WBS__c(
            Project__c = project2.Id,
            CVR__c = cvr2.Id,
            WBS_Code__c = 'TEST-WBS-002',
            WBS_Key__c  = 'KEY-TEST-WBS-002'
        );
        insert map2;

        // Existing CVR/map1
        CVR__c cvr1 = [SELECT Id, Project__c FROM CVR__c WHERE Id != :cvr2.Id LIMIT 1];
        Project_WBS__c map1 = [SELECT WBS_Key__c FROM Project_WBS__c WHERE WBS_Code__c = 'TEST-WBS-001' LIMIT 1];

        // Two cost lines, same billing doc, different WBS (-> different CVR/Project/Key)
        SAP_Data__c costEarly = new SAP_Data__c(
            Name = 'Cost Amb Early',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001',
            Billing_Document__c = 'BILL-AMB'
        );
        SAP_Data__c costLate = new SAP_Data__c(
            Name = 'Cost Amb Late',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-002',
            Billing_Document__c = 'BILL-AMB'
        );
        insert new List<SAP_Data__c>{ costEarly, costLate };

        // Force deterministic ordering: costEarly created first
        Test.setCreatedDate(costEarly.Id, DateTime.now().addMinutes(-10));
        Test.setCreatedDate(costLate.Id, DateTime.now().addMinutes(-5));

        // Billing line references ambiguous doc
        SAP_Data__c bill = new SAP_Data__c(
            Name = 'Billing Amb',
            Type__c = 'Billing Line',
            Billing_Document__c = 'BILL-AMB'
        );
        insert bill;
        Test.setCreatedDate(bill.Id, DateTime.now());

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.startTest();
            // Stamp BOTH cost lines first
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt, false), 200);
            // Billing batch should pick earliest-created cost line for the doc
            Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
        Test.stopTest();

        bill = [SELECT CVR__c, Project__c, WBS_Key__c, L4_WBS__c FROM SAP_Data__c WHERE Id = :bill.Id];

        System.assertEquals(cvr1.Id, bill.CVR__c, 'First-wins: billing should take CVR from earliest cost line');
        System.assertEquals(cvr1.Project__c, bill.Project__c, 'First-wins: billing should take Project from earliest cost line');
        System.assertEquals(map1.WBS_Key__c, bill.WBS_Key__c, 'First-wins: billing should take WBS_Key from earliest cost line');
        System.assertEquals('TEST-WBS-001', bill.L4_WBS__c, 'First-wins: billing should copy L4_WBS__c from earliest cost line');
    }

    // -------------------------------------------------------------------------
    // Scheduler tests (deterministic)
    // -------------------------------------------------------------------------

    @IsTest
    static void testSapStampSchedulerCutoverChainsBilling() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [SELECT WBS_Key__c FROM Project_WBS__c WHERE WBS_Code__c = 'TEST-WBS-001' LIMIT 1];

        // Choose a reference time AFTER cutoff (03:00), so window is [yesterday 03:00 .. today 03:00)
        Date refDate = Date.newInstance(2026, 1, 10);
        DateTime referenceDt = DateTime.newInstance(refDate, Time.newInstance(4, 0, 0, 0)); // 04:00
        DateTime endDt = DateTime.newInstance(refDate, Time.newInstance(3, 0, 0, 0));
        DateTime startDt = endDt.addDays(-1);

        SAP_Data__c cost = new SAP_Data__c(
            Name = 'Sched Cost',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001',
            Billing_Document__c = 'BILL-SCHED'
        );
        insert cost;

        SAP_Data__c bill = new SAP_Data__c(
            Name = 'Sched Bill',
            Type__c = 'Billing Line',
            Billing_Document__c = 'BILL-SCHED'
        );
        insert bill;

        // Put both CreatedDate inside scheduler window
        DateTime inside = startDt.addHours(1);
        Test.setCreatedDate(cost.Id, inside);
        Test.setCreatedDate(bill.Id, inside);

        Test.startTest();
            SapStampCvrScheduler.runForReferenceDateTime(referenceDt); // chains billing
        Test.stopTest();

        Map<Id, SAP_Data__c> reloaded = new Map<Id, SAP_Data__c>([
            SELECT Id, Type__c, CVR__c, Project__c, WBS_Key__c, L4_WBS__c
            FROM SAP_Data__c
            WHERE Id IN :new List<Id>{ cost.Id, bill.Id }
        ]);

        System.assertEquals(cvr.Id, reloaded.get(cost.Id).CVR__c, 'Scheduler should stamp cost CVR');
        System.assertEquals(cvr.Project__c, reloaded.get(cost.Id).Project__c, 'Scheduler should stamp cost Project');
        System.assertEquals(map1.WBS_Key__c, reloaded.get(cost.Id).WBS_Key__c, 'Scheduler should stamp cost WBS_Key');

        System.assertEquals(cvr.Id, reloaded.get(bill.Id).CVR__c, 'Chained billing should stamp billing CVR');
        System.assertEquals(cvr.Project__c, reloaded.get(bill.Id).Project__c, 'Chained billing should stamp billing Project');
        System.assertEquals(map1.WBS_Key__c, reloaded.get(bill.Id).WBS_Key__c, 'Chained billing should stamp billing WBS_Key');
        System.assertEquals('TEST-WBS-001', reloaded.get(bill.Id).L4_WBS__c, 'Chained billing should copy L4_WBS__c');
    }

    @IsTest
    static void testBillingLinesSchedulerRunsDeterministicWindow() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [SELECT WBS_Key__c FROM Project_WBS__c WHERE WBS_Code__c = 'TEST-WBS-001' LIMIT 1];

        // Create a cost line (will be stamped first by running SapStampCvrBatch directly)
        SAP_Data__c cost = new SAP_Data__c(
            Name = 'Sched2 Cost',
            Type__c = 'Cost Line',
            L4_WBS__c = 'TEST-WBS-001',
            Billing_Document__c = 'BILL-SCHED2'
        );
        insert cost;

        // Billing line is unstamped
        SAP_Data__c bill = new SAP_Data__c(
            Name = 'Sched2 Bill',
            Type__c = 'Billing Line',
            Billing_Document__c = 'BILL-SCHED2'
        );
        insert bill;

        // Build a deterministic cutover window based on referenceDt (after 03:00)
        Date refDate = Date.newInstance(2026, 1, 11);
        DateTime referenceDt = DateTime.newInstance(refDate, Time.newInstance(4, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(refDate, Time.newInstance(3, 0, 0, 0));
        DateTime startDt = endDt.addDays(-1);

        DateTime inside = startDt.addHours(2);
        Test.setCreatedDate(cost.Id, inside);
        Test.setCreatedDate(bill.Id, inside);

        Test.startTest();
            // Stamp cost line
            Database.executeBatch(new SapStampCvrBatch(startDt, endDt, false), 200);
            // Now run billing scheduler which uses same window logic
            SapStampBillingLinesScheduler.runForReferenceDateTime(referenceDt);
        Test.stopTest();

        bill = [SELECT CVR__c, Project__c, WBS_Key__c, L4_WBS__c FROM SAP_Data__c WHERE Id = :bill.Id];

        System.assertEquals(cvr.Id, bill.CVR__c, 'Billing scheduler should stamp billing CVR');
        System.assertEquals(cvr.Project__c, bill.Project__c, 'Billing scheduler should stamp billing Project');
        System.assertEquals(map1.WBS_Key__c, bill.WBS_Key__c, 'Billing scheduler should stamp billing WBS_Key');
        System.assertEquals('TEST-WBS-001', bill.L4_WBS__c, 'Billing scheduler should copy L4_WBS__c');
    }
}
