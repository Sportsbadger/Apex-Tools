@IsTest
private class CoupaStampCvrBatchTest {

    @TestSetup
    static void makeData() {
        sitetracker__Project_Template__c template = new sitetracker__Project_Template__c(
            Name = 'Test Template ST Coupa',
            sitetracker__Active__c = true
        );
        insert template;

        sitetracker__Site__c site = new sitetracker__Site__c(
            Name = 'Test site ST Coupa',
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

        // IMPORTANT: CoupaStampCvrBatch requires WBS_Key__c != NULL in mapping
        Project_WBS__c wbsMap = new Project_WBS__c(
            Project__c = project.Id,
            CVR__c = cvr.Id,
            WBS_Code__c = 'TEST-WBS-001',
            WBS_Key__c  = 'KEY-TEST-WBS-001'
        );
        insert wbsMap;
    }

    @IsTest
    static void testCoupaBatchStampsCvrProjectAndKey_NoTypeFilter() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [
            SELECT WBS_Key__c
            FROM Project_WBS__c
            WHERE WBS_Code__c = 'TEST-WBS-001'
            LIMIT 1
        ];

        // L4_WBS__c is a formula: RIGHT(Account__c, 23)
        // Ensure the last 23 chars equal the WBS code.
        String prefix = 'XXXXXXXXXXXXXXXXXXXX'; // arbitrary prefix

        // Matching (Type PO)
        Coupa_Data__c coupaMatchPO = new Coupa_Data__c(
            Name = 'Coupa Match PO',
            Type__c = 'PO',
            Account__c = prefix + 'TEST-WBS-001'
        );

        // Matching (Type other) - proves no type filter
        Coupa_Data__c coupaMatchOther = new Coupa_Data__c(
            Name = 'Coupa Match Other',
            Type__c = 'Invoice',
            Account__c = prefix + 'TEST-WBS-001'
        );

        // Non-matching
        Coupa_Data__c coupaNoMatch = new Coupa_Data__c(
            Name = 'Coupa No Match',
            Type__c = 'PO',
            Account__c = prefix + 'NO-MATCH'
        );

        insert new List<Coupa_Data__c>{ coupaMatchPO, coupaMatchOther, coupaNoMatch };

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.setCreatedDate(coupaMatchPO.Id, DateTime.now());
        Test.setCreatedDate(coupaMatchOther.Id, DateTime.now());
        Test.setCreatedDate(coupaNoMatch.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(new CoupaStampCvrBatch(startDt, endDt, false), 200);
        Test.stopTest();

        Map<Id, Coupa_Data__c> reloaded = new Map<Id, Coupa_Data__c>([
            SELECT Id, CVR__c, Project__c, WBS_Key__c
            FROM Coupa_Data__c
            WHERE Id IN :new List<Id>{ coupaMatchPO.Id, coupaMatchOther.Id, coupaNoMatch.Id }
        ]);

        // PO match
        System.assertEquals(
            cvr.Id,
            reloaded.get(coupaMatchPO.Id).CVR__c,
            'Matching WBS should stamp CVR__c (PO)'
        );
        System.assertEquals(
            cvr.Project__c,
            reloaded.get(coupaMatchPO.Id).Project__c,
            'Matching WBS should stamp Project__c (PO)'
        );
        System.assertEquals(
            map1.WBS_Key__c,
            reloaded.get(coupaMatchPO.Id).WBS_Key__c,
            'Matching WBS should stamp WBS_Key__c (PO)'
        );

        // Other type match
        System.assertEquals(
            cvr.Id,
            reloaded.get(coupaMatchOther.Id).CVR__c,
            'Should stamp regardless of Type__c'
        );
        System.assertEquals(
            cvr.Project__c,
            reloaded.get(coupaMatchOther.Id).Project__c,
            'Should stamp Project regardless of Type__c'
        );
        System.assertEquals(
            map1.WBS_Key__c,
            reloaded.get(coupaMatchOther.Id).WBS_Key__c,
            'Should stamp WBS_Key regardless of Type__c'
        );

        // No match
        System.assertEquals(
            null,
            reloaded.get(coupaNoMatch.Id).CVR__c,
            'Non-matching WBS should remain null'
        );
        System.assertEquals(
            null,
            reloaded.get(coupaNoMatch.Id).Project__c,
            'Non-matching should not stamp Project__c'
        );
        System.assertEquals(
            null,
            reloaded.get(coupaNoMatch.Id).WBS_Key__c,
            'Non-matching should not stamp WBS_Key__c'
        );
    }

    @IsTest
    static void testCoupaSchedulerExecutesCutover() {
        CVR__c cvr = [SELECT Id, Project__c FROM CVR__c LIMIT 1];
        Project_WBS__c map1 = [
            SELECT WBS_Key__c
            FROM Project_WBS__c
            WHERE WBS_Code__c = 'TEST-WBS-001'
            LIMIT 1
        ];

        // Deterministic reference time AFTER cutoff (03:00)
        Date refDate = Date.newInstance(2026, 1, 12);
        DateTime referenceDt = DateTime.newInstance(refDate, Time.newInstance(4, 0, 0, 0)); // 04:00

        DateTime endDt = DateTime.newInstance(refDate, Time.newInstance(3, 0, 0, 0));
        DateTime startDt = endDt.addDays(-1);
        DateTime inside = startDt.addHours(1);

        String prefix = 'XXXXXXXXXXXXXXXXXXXX';
        Coupa_Data__c coupa = new Coupa_Data__c(
            Name = 'Coupa For Scheduler',
            Type__c = 'PR',
            Account__c = prefix + 'TEST-WBS-001'
        );
        insert coupa;

        // Put record inside scheduler window
        Test.setCreatedDate(coupa.Id, inside);

        Test.startTest();
            CoupaStampCvrScheduler.runForReferenceDateTime(referenceDt);
        Test.stopTest();

        coupa = [SELECT Id, CVR__c, Project__c, WBS_Key__c FROM Coupa_Data__c WHERE Id = :coupa.Id];

        System.assertEquals(cvr.Id, coupa.CVR__c, 'Scheduler should stamp CVR__c');
        System.assertEquals(cvr.Project__c, coupa.Project__c, 'Scheduler should stamp Project__c');
        System.assertEquals(map1.WBS_Key__c, coupa.WBS_Key__c, 'Scheduler should stamp WBS_Key__c');
    }
}
