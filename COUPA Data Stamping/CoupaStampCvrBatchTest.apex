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

        Project_WBS__c wbsMap = new Project_WBS__c(
            Project__c = project.Id,
            CVR__c = cvr.Id,
            WBS_Code__c = 'TEST-WBS-001'
        );
        insert wbsMap;
    }

    @IsTest
    static void testCoupaBatchStampsCvr() {
        CVR__c cvr = [SELECT Id FROM CVR__c LIMIT 1];

        // MATCHING row (PO, Account ends with WBS)
        Coupa_Data__c coupaMatch = new Coupa_Data__c(
            Name = 'Coupa Match',
            Type__c = 'PO',
            Account__c = 'TEST-WBS-001'
        );

        // NON-matching row (PO, different WBS)
        Coupa_Data__c coupaNoMatch = new Coupa_Data__c(
            Name = 'Coupa No Match',
            Type__c = 'PO',
            Account__c = 'NO-MATCH'
        );

        insert new List<Coupa_Data__c>{ coupaMatch, coupaNoMatch };

        DateTime startDt = DateTime.now().addHours(-1);
        DateTime endDt   = DateTime.now().addHours(1);

        Test.setCreatedDate(coupaMatch.Id, DateTime.now());
        Test.setCreatedDate(coupaNoMatch.Id, DateTime.now());

        Test.startTest();
            Database.executeBatch(
                new CoupaStampCvrBatch(startDt, endDt, false),
                200
            );
        Test.stopTest();

        Map<Id, Coupa_Data__c> reloaded = new Map<Id, Coupa_Data__c>([
            SELECT Id, CVR__c
            FROM Coupa_Data__c
            WHERE Id IN :new List<Id>{ coupaMatch.Id, coupaNoMatch.Id }
        ]);

        System.assertEquals(
            cvr.Id,
            reloaded.get(coupaMatch.Id).CVR__c,
            'Matching WBS should stamp CVR__c on Coupa_Data__c'
        );
        System.assertEquals(
            null,
            reloaded.get(coupaNoMatch.Id).CVR__c,
            'Non-matching WBS should remain null on Coupa_Data__c'
        );
    }
}
