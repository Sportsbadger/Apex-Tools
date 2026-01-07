# Apex Tools: SAP CVR Stamping

Batch and scheduler classes to stamp `SAP_Data__c.CVR__c` based on WBS mappings and billing documents.

## What this repo includes

- **`SapStampCvrBatch`**: Stamps `SAP_Data__c` **Cost Line** rows by mapping `L4_WBS__c` to `Project_WBS__c.CVR__c`.
- **`SapStampBillingLinesCvrBatch`**: Stamps **Billing Line** rows by deriving `CVR__c` from stamped **Cost Line** records that share the same `Billing_Document__c`.
- **`SapStampCvrScheduler`**: Schedules daily execution for a rolling 24‑hour window.
- **`SapStampCvrBatchandSchedulerTest`**: Unit tests covering WBS stamping, scheduler execution, billing line inheritance, and ambiguity handling.

## Data model assumptions

- `SAP_Data__c` has fields: `Type__c`, `L4_WBS__c`, `Billing_Document__c`, `CVR__c`.
- `Project_WBS__c` maps `WBS_Code__c` ➜ `CVR__c`.
- `CVR__c` relates to `sitetracker__Project__c` (per test setup).

## Batch behavior

### Cost Line stamping (`SapStampCvrBatch`)

- **Scope**: `SAP_Data__c` with
  - `Type__c = 'Cost Line'`
  - `CVR__c = NULL`
  - `L4_WBS__c != NULL`
  - `CreatedDate` within `[startDt, endDt)`
- **Logic**:
  - Build `WBS_Code__c ➜ CVR__c` map from `Project_WBS__c`.
  - If a WBS maps to multiple CVRs, mark as **ambiguous** and skip.
  - Stamp `SAP_Data__c.CVR__c` when a single match exists.

### Billing Line stamping (`SapStampBillingLinesCvrBatch`)

- **Scope**: `SAP_Data__c` with
  - `Type__c = 'Billing Line'`
  - `CVR__c = NULL`
  - `Billing_Document__c != NULL`
  - `CreatedDate` within `[startDt, endDt)`
- **Logic**:
  - Query **Cost Line** records with the same `Billing_Document__c` and a stamped `CVR__c`.
  - If a billing document maps to multiple CVRs, mark as **ambiguous** and skip.
  - Stamp `SAP_Data__c.CVR__c` when a single match exists.

## Scheduling

`sapStampCvrScheduler` executes daily for the window `[today 03:00, tomorrow 03:00)` by default:

```apex
// Example: schedule for 03:00 daily
SapStampCvrScheduler.scheduleDaily('SAP CVR Stamping Daily', 3, 0);
```

You can also run ad‑hoc:

```apex
DateTime startDt = DateTime.now().addDays(-1);
DateTime endDt = DateTime.now();
Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
```

## Notes

- Ambiguous mappings (multiple CVRs per WBS or Billing Document) are skipped to avoid incorrect stamping.
- Both batches maintain counters (`scanned`, `stamped`, `unmatched`, `ambiguous`) for logging/monitoring.
