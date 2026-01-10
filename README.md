# Apex Tools: SAP CVR Stamping

Batch and scheduler classes to stamp `SAP_Data__c.CVR__c` based on WBS mappings and billing documents.

## Quick start (beginner-friendly)

1. **Confirm prerequisites**: Objects, fields, and Custom Metadata exist (see below).
2. **Load mappings**: Insert `Project_WBS__c` rows for each WBS ➜ CVR mapping.
3. **Run once**: Execute the batches manually for a known time window.
4. **Schedule daily**: Use the scheduler helper to run every day.
5. **Test**: Run the Apex tests to validate your org setup.

## What this repo includes

- **`SapStampCvrBatch`**: Stamps `SAP_Data__c` **Cost Line** rows by mapping `L4_WBS__c` to `Project_WBS__c.CVR__c`.
- **`SapStampBillingLinesCvrBatch`**: Stamps **Billing Line** rows by deriving `CVR__c` from stamped **Cost Line** records that share the same `Billing_Document__c`.
- **`SapStampCvrScheduler`**: Schedules daily execution for a rolling 24‑hour window.
- **`SapStampCvrBatchandSchedulerTest`**: Unit tests covering WBS stamping, scheduler execution, billing line inheritance, and ambiguity handling.

## Pre-requisite objects and fields

> These are required for the batches and tests to compile and run. If your org uses different names, adjust the Apex code or add field aliases.

### Required objects

- `SAP_Data__c` (custom object)
- `Project_WBS__c` (custom object)
- `CVR__c` (custom object)
- `sitetracker__Project__c`, `sitetracker__Project_Template__c`, `sitetracker__Site__c` (from the SiteTracker managed package, used by tests)

### Required fields and relationships

**`SAP_Data__c`**
- `Type__c` (Text) — values used: `Cost Line`, `Billing Line`, `Aged Debt`
- `L4_WBS__c` (Text)
- `Billing_Document__c` (Text)
- `CVR__c` (Lookup to `CVR__c`)
- `CreatedDate` (standard)

**`Project_WBS__c`**
- `WBS_Code__c` (Text)
- `CVR__c` (Lookup to `CVR__c`)
- `Project__c` (Lookup to `sitetracker__Project__c`)

**`CVR__c`**
- `Project__c` (Lookup/Master-Detail to `sitetracker__Project__c` per tests)

**`sitetracker__Project__c`**
- `CVR__c` (Lookup to `CVR__c`)
- `sitetracker__ProjectTemplate__c` (Lookup to `sitetracker__Project_Template__c`)
- `sitetracker__Site__c` (Lookup to `sitetracker__Site__c`)

### Optional: Custom Metadata for scheduling

Create `Sap_Stamp_Settings__mdt` with a record named `Default` to configure the scheduler:

- `Cutover_Hour__c` (Number) — hour (0–23) used for daily cutoff, defaults to `3` if missing.
- `Mode__c` (Text) — `Cutover` (default) or `Backfill`.
- `Backfill_Days__c` (Number) — days back to process in `Backfill` mode (default `7`).

If this CMDT does not exist, the scheduler falls back to defaults.

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

## Scheduling (how to run it on a schedule)

### Default behavior

`SapStampCvrScheduler` executes daily and uses a cutover window by default:

- **Window**: `[yesterday 03:00, today 03:00)` (based on local org time)
- **Config**: If `Sap_Stamp_Settings__mdt.Default` exists, it can override cutover hour and enable backfill.

### Schedule daily (recommended)

```apex
// Example: schedule for 03:00 daily
SapStampCvrScheduler.scheduleDaily('SAP CVR Stamping Daily', 3, 0);
```

### Run once at a specific time

```apex
SapStampCvrScheduler.scheduleTodayAt('SAP CVR Stamping One-Off', 14, 30);
```

### Run immediately (ad-hoc batch execution)

```apex
DateTime startDt = DateTime.now().addDays(-1);
DateTime endDt = DateTime.now();
Database.executeBatch(new SapStampCvrBatch(startDt, endDt), 200);
Database.executeBatch(new SapStampBillingLinesCvrBatch(startDt, endDt), 200);
```

## Testing

### Run Apex tests in an org (CLI)

```bash
sfdx force:apex:test:run -n SapStampCvrBatchTest -r human -w 10
```

### Run Apex tests in Developer Console

1. Open **Developer Console**.
2. Go to **Test** ➜ **New Run**.
3. Select `SapStampCvrBatchTest`.
4. Click **Run**.

## Notes

- Ambiguous mappings (multiple CVRs per WBS or Billing Document) are skipped to avoid incorrect stamping.
- Both batches maintain counters (`scanned`, `stamped`, `unmatched`, `ambiguous`) for logging/monitoring.
