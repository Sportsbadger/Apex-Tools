@IsTest
private class CVRProjectTotalsRollupServiceTest {

    @TestSetup
    static void makeData() {
        // Standard Test Setup
        sitetracker__Project_Template__c template = new sitetracker__Project_Template__c(
            Name = 'Test Template ST Rollup',
            sitetracker__Active__c = true
        );
        insert template;

        sitetracker__Site__c site = new sitetracker__Site__c(
            Name = 'Test site ST Rollup',
            sitetracker__Site_Type__c = 'Other'
        );
        insert site;

        // Project 1 (has children CVRs)
        sitetracker__Project__c project1 = new sitetracker__Project__c(
            sitetracker__ProjectTemplate__c = template.Id,
            sitetracker__Site__c = site.Id
        );
        insert project1;

        // Parent "Project" CVR
        CVR__c parent1 = new CVR__c(
            Project__c  = project1.Id,
            CVR_Type__c = 'Project'
        );
        insert parent1;

        // Child CVRs (non-Project types, linked to parent)
        CVR__c child1 = new CVR__c(
            Project__c    = project1.Id,
            CVR_Type__c   = 'Build',
            Parent_CVR__c = parent1.Id,

            // A few fields to prove rollup works
            SAP_Costs_Invoiced__c = 10,
            Coupa_PO__c           = 100,
            Manual_Sales__c       = 1000
        );

        CVR__c child2 = new CVR__c(
            Project__c    = project1.Id,
            CVR_Type__c   = 'Design',
            Parent_CVR__c = parent1.Id,

            SAP_Costs_Invoiced__c = 20,
            Coupa_PO__c           = 200,
            Manual_Sales__c       = 2000
        );

        insert new List<CVR__c>{ child1, child2 };

        // Project 2 (Project parent CVR but NO children -> should be zeroed by service)
        sitetracker__Project__c project2 = new sitetracker__Project__c(
            sitetracker__ProjectTemplate__c = template.Id,
            sitetracker__Site__c = site.Id
        );
        insert project2;

        CVR__c parent2 = new CVR__c(
            Project__c  = project2.Id,
            CVR_Type__c = 'Project'
        );
        insert parent2;
    }

    // Helper: build set of parent CVR Ids that have at least one child
    private static Set<Id> getParentIdsWithChildren() {
        Set<Id> parentIds = new Set<Id>();
        for (CVR__c c : [
            SELECT Parent_CVR__c
            FROM CVR__c
            WHERE Parent_CVR__c != NULL
        ]) {
            parentIds.add(c.Parent_CVR__c);
        }
        return parentIds;
    }

    // -------------------------------------------------------------------------
    // Service-level test:
    // Covers:
    // - onlyParentsWithChildren = false
    // - zeroParentsWithNoChildren = true
    // - childWhereClause / parentWhereClause filtering
    // -------------------------------------------------------------------------
    @IsTest
    static void testProjectTotalsServiceRollsUpAndZeros() {
        Set<Id> parentsWithKids = getParentIdsWithChildren();
        System.assert(!parentsWithKids.isEmpty(), 'Test setup should create at least one parent with children');

        Test.startTest();
            CVRProjectTotalsRollupService.run(200);
        Test.stopTest();

        // Parent with children
        CVR__c parentWithKids = [
            SELECT Id, CVR_Type__c,
                   SAP_Costs_Invoiced__c, Coupa_PO__c, Manual_Sales__c
            FROM CVR__c
            WHERE CVR_Type__c = 'Project'
              AND Id IN :parentsWithKids
            LIMIT 1
        ];

        System.assertEquals(30, parentWithKids.SAP_Costs_Invoiced__c,
            'Project parent should SUM SAP_Costs_Invoiced__c across non-Project children');
        System.assertEquals(300, parentWithKids.Coupa_PO__c,
            'Project parent should SUM Coupa_PO__c across non-Project children');
        System.assertEquals(3000, parentWithKids.Manual_Sales__c,
            'Project parent should SUM Manual_Sales__c across non-Project children');

        // Parent with NO children should be zeroed (because zeroParentsWithNoChildren = true)
        CVR__c parentNoKids = [
            SELECT Id, CVR_Type__c,
                   SAP_Costs_Invoiced__c, Coupa_PO__c, Manual_Sales__c
            FROM CVR__c
            WHERE CVR_Type__c = 'Project'
              AND Id NOT IN :parentsWithKids
            LIMIT 1
        ];

        System.assertEquals(0, parentNoKids.SAP_Costs_Invoiced__c,
            'Project parent with no children should be zeroed for SUM fields');
        System.assertEquals(0, parentNoKids.Coupa_PO__c,
            'Project parent with no children should be zeroed for SUM fields');
        System.assertEquals(0, parentNoKids.Manual_Sales__c,
            'Project parent with no children should be zeroed for SUM fields');
    }

    // -------------------------------------------------------------------------
    // Batch-level behaviour test: onlyParentsWithChildren = true (semi-join logic)
    // Here we ensure parents without children are not included/updated
    // -------------------------------------------------------------------------
    @IsTest
    static void testSelfRollupBatchOnlyParentsWithChildrenSkipsParentsWithoutKids() {
        Set<Id> parentsWithKids = getParentIdsWithChildren();

        CVR__c parentNoKids = [
            SELECT Id, CVR_Type__c, SAP_Costs_Invoiced__c
            FROM CVR__c
            WHERE CVR_Type__c = 'Project'
              AND Id NOT IN :parentsWithKids
            LIMIT 1
        ];

        // Sentinel value so we can prove it didn't get touched
        parentNoKids.SAP_Costs_Invoiced__c = 999;
        update parentNoKids;

        // Build a small spec that only updates parents with children
        SelfRollupBatch.Spec s = new SelfRollupBatch.Spec();
        s.objectApiName = 'CVR__c';
        s.parentLookupFieldApiName = 'Parent_CVR__c';
        s.childWhereClause  = 'CVR_Type__c != \'Project\'';
        s.parentWhereClause = 'CVR_Type__c = \'Project\'';
        s.onlyParentsWithChildren = true;
        s.zeroParentsWithNoChildren = false;
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Costs_Invoiced__c', 'SAP_Costs_Invoiced__c'));

        Test.startTest();
            Database.executeBatch(new SelfRollupBatch(s), 200);
        Test.stopTest();

        parentNoKids = [SELECT SAP_Costs_Invoiced__c FROM CVR__c WHERE Id = :parentNoKids.Id];
        System.assertEquals(999, parentNoKids.SAP_Costs_Invoiced__c,
            'With onlyParentsWithChildren=true and zeroParentsWithNoChildren=false, parents with no kids should not be updated');
    }

    // -------------------------------------------------------------------------
    // Scheduler coverage:
    // Schedules the Rollup scheduler and asserts the same outputs.
    // -------------------------------------------------------------------------
    @IsTest
    static void testRollupSchedulerExecutes() {
        Set<Id> parentsWithKids = getParentIdsWithChildren();
        System.assert(!parentsWithKids.isEmpty(), 'Test setup should create at least one parent with children');

        // Use a valid cron expression; the scheduled job fires at Test.stopTest()
        String cron = '0 0 0 1 1 ? 2099';

        Test.startTest();
            System.schedule('CVR Project Totals Rollup - Scheduler Test', cron, new CVRProjectTotalsRollupScheduler());
        Test.stopTest();

        // Parent with kids should now be rolled up
        CVR__c parentWithKids = [
            SELECT Id, SAP_Costs_Invoiced__c, Coupa_PO__c, Manual_Sales__c
            FROM CVR__c
            WHERE CVR_Type__c = 'Project'
              AND Id IN :parentsWithKids
            LIMIT 1
        ];

        System.assertEquals(30, parentWithKids.SAP_Costs_Invoiced__c);
        System.assertEquals(300, parentWithKids.Coupa_PO__c);
        System.assertEquals(3000, parentWithKids.Manual_Sales__c);

        // Parent with no kids should be zeroed (service config uses zeroParentsWithNoChildren=true)
        CVR__c parentNoKids = [
            SELECT Id, SAP_Costs_Invoiced__c, Coupa_PO__c, Manual_Sales__c
            FROM CVR__c
            WHERE CVR_Type__c = 'Project'
              AND Id NOT IN :parentsWithKids
            LIMIT 1
        ];

        System.assertEquals(0, parentNoKids.SAP_Costs_Invoiced__c);
        System.assertEquals(0, parentNoKids.Coupa_PO__c);
        System.assertEquals(0, parentNoKids.Manual_Sales__c);
    }

    // -------------------------------------------------------------------------
    // Spec validation coverage: hit validateSpec error branches.
    // -------------------------------------------------------------------------
    @IsTest
    static void testSelfRollupBatchValidateSpecThrows() {
        // 1) Null spec
        try {
            new SelfRollupBatch(null);
            System.assert(false, 'Expected exception for null spec');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Spec is required'));
        }

        // 2) Missing objectApiName
        try {
            SelfRollupBatch.Spec s = new SelfRollupBatch.Spec();
            s.objectApiName = null;
            s.parentLookupFieldApiName = 'Parent_CVR__c';
            s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Costs_Invoiced__c', 'SAP_Costs_Invoiced__c'));
            new SelfRollupBatch(s);
            System.assert(false, 'Expected exception for missing objectApiName');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Spec.objectApiName is required'));
        }

        // 3) Empty ops
        try {
            SelfRollupBatch.Spec s = new SelfRollupBatch.Spec();
            s.objectApiName = 'CVR__c';
            s.parentLookupFieldApiName = 'Parent_CVR__c';
            s.ops.clear();
            new SelfRollupBatch(s);
            System.assert(false, 'Expected exception for empty ops');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Spec.ops must have at least one operation'));
        }

        // 4) Unsupported op string
        try {
            SelfRollupBatch.Spec s = new SelfRollupBatch.Spec();
            s.objectApiName = 'CVR__c';
            s.parentLookupFieldApiName = 'Parent_CVR__c';
            s.ops.add(new SelfRollupBatch.RollupOp('AVG', 'SAP_Costs_Invoiced__c', 'SAP_Costs_Invoiced__c'));
            new SelfRollupBatch(s);
            System.assert(false, 'Expected exception for unsupported operation');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Unsupported op.operation'));
        }

        // 5) SUM requires childField
        try {
            SelfRollupBatch.Spec s = new SelfRollupBatch.Spec();
            s.objectApiName = 'CVR__c';
            s.parentLookupFieldApiName = 'Parent_CVR__c';
            s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, null, 'SAP_Costs_Invoiced__c'));
            new SelfRollupBatch(s);
            System.assert(false, 'Expected exception for SUM missing childField');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('SUM requires childField'));
        }
    }
}
