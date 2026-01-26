public class CVRProjectTotalsRollupService {

    public static void run(Integer batchSize) {

        SelfRollupBatch.Spec s = new SelfRollupBatch.Spec();
        s.objectApiName = 'CVR__c';
        s.parentLookupFieldApiName = 'Parent_CVR__c';

        // Include only WBS CVRs as children
        s.childWhereClause  = 'CVR_Type__c != \'Project\'';

        // Update only Project CVRs as parents
        s.parentWhereClause = 'CVR_Type__c = \'Project\'';

        s.zeroParentsWithNoChildren = true;
        s.onlyParentsWithChildren = false;

        // Add rollups
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Costs_Invoiced__c', 'SAP_Costs_Invoiced__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_New_Month_PO_Accrual__c', 'SAP_New_Month_PO_Accrual__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_In_Month_PO_Accrual__c', 'SAP_In_Month_PO_Accrual__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_PO_Accrual__c', 'SAP_PO_Accrual__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_New_Month_Labour__c', 'SAP_New_Month_Labour__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_In_Month_Labour__c', 'SAP_In_Month_Labour__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Labour__c', 'SAP_Labour__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Costs_Invoiced__c', 'SAP_Costs_Invoiced__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Invoiced__c', 'SAP_Invoiced__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_New_Month_Intercompany__c', 'SAP_New_Month_Intercompany__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_In_Month_Intercompany__c', 'SAP_In_Month_Intercompany__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Intercompany__c', 'SAP_Intercompany__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Not_Due__c', 'Not_Due__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x91_120__c', 'x91_120__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x721_Days_Over__c', 'x721_Days_Over__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x61_90__c', 'x61_90__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x361_720__c', 'x361_720__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x31_60__c', 'x31_60__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x181_360__c', 'x181_360__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x151_180__c', 'x151_180__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x121_150__c', 'x121_150__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'x1_30__c', 'x1_30__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_In_Month_Cost__c', 'SAP_In_Month_Cost__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_New_Month_Billing__c', 'SAP_New_Month_Billing__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_In_Month_Billed__c', 'SAP_In_Month_Billed__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Billed__c', 'SAP_Billed__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_Ne_wMonth_AI_DI__c', 'SAP_Ne_wMonth_AI_DI__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_In_Month_AI_DI__c', 'SAP_In_Month_AI_DI__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'SAP_AI_DI__c', 'SAP_AI_DI__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Total_Sitetracker_Sales__c', 'Total_Sitetracker_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Projected_Sales__c', 'Projected_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Projected_Costs__c', 'Projected_Costs__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Other_Sales__c', 'Other_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'IA_Sales__c', 'IA_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Design_Sales__c', 'Design_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Acquisition_Sales__c', 'Acquisition_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Other_Projected_Sales__c', 'Other_Projected_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Other_Projected_Cost__c', 'Other_Projected_Cost__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'IA_Projected_Sales__c', 'IA_Projected_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'IA_Projected_Cost__c', 'IA_Projected_Cost__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Design_Projected_Sales__c', 'Design_Projected_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Design_Projected_Cost__c', 'Design_Projected_Cost__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Acquisition_Projected_Sales__c', 'Acquisition_Projected_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Acquisition_Projected_Cost__c', 'Acquisition_Projected_Cost__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Coupa_Receipted__c', 'Coupa_Receipted__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Coupa_PR__c', 'Coupa_PR__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Coupa_PO__c', 'Coupa_PO__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Coupa_Invoiced__c', 'Coupa_Invoiced__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Created_PO__c', 'Created_PO__c'));

        // Add rollups for Manual Data Entry fields

        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Manual_Sales__c', 'Manual_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Supplier_Costs_Legacy_System__c', 'Supplier_Costs_Legacy_System__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Prior_Month_Recognised_Sales__c', 'Prior_Month_Recognised_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Prior_Month_Labour__c', 'Prior_Month_Labour__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Prior_Month_Manual_Accrual__c', 'Prior_Month_Manual_Accrual__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Prior_Month_Invoiced_Sales__c', 'Prior_Month_Invoiced_Sales__c'));
        s.ops.add(new SelfRollupBatch.RollupOp(SelfRollupBatch.OP_SUM, 'Prior_Month_Invoiced_Cost__c', 'Prior_Month_Invoiced_Cost__c'));


        Integer bs = (batchSize == null || batchSize <= 0) ? s.batchSize : batchSize;
        Database.executeBatch(new SelfRollupBatch(s), bs);
    }

    public static void run() {
        run(1000);
    }
}
