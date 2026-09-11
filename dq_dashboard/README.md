# OULAD data-quality result contract

This package creates a generic audit contract for **every OULAD dataset** in Bronze, Silver, and Gold. Individual checks write to the same two Delta tables, so the dashboard does not need custom logic for each source table.

## Files

- `00_create_data_quality_contract.sql` creates the schema, two Delta tables, and dashboard views. It is safe to rerun.
- `01_validate_data_quality_contract.sql` contains read-only contract tests. Every query should return zero rows.

Run the create script first. Run the validation script after checks have started writing results.

## Standard contract

### Check categories

| `check_type` | Question answered |
|---|---|
| `NULL` | Is required data missing? |
| `UNIQUE` | Are records unexpectedly duplicated? |
| `RANGE` | Are numeric or date values reasonable? |
| `ACCEPTED_VALUES` | Are categories valid? |
| `REFERENTIAL_INTEGRITY` | Do parent-child relationships work? |
| `VOLUME` | Did we receive roughly the expected number of rows? |

### Statuses

| `status` | Meaning | Included in pass-rate denominator? |
|---|---|---:|
| `PASS` | The expectation was met. | Yes |
| `WARN` | A warning threshold was breached; investigate. | Yes |
| `FAIL` | A failure threshold was breached. | Yes |
| `NOT_APPLICABLE` | The check does not apply to this dataset/run. | **No** |

Pass rate is:

`PASS checks / checks where status <> NOT_APPLICABLE * 100`

### Severities and stop rules

| `severity` | Meaning when breached | Pipeline action |
|---|---|---|
| `WARN` | Quality concern with limited impact | Continue and investigate |
| `FAIL` | Material defect | Mark failed; pipeline continues unless orchestration has a stricter policy |
| `CRITICAL` | Unsafe or unusable output | Stop when status is `FAIL` |

The stored rule is exact:

`stop_pipeline = (status = 'FAIL' AND severity = 'CRITICAL')`

Severity describes business impact. Status describes the observed result. A passing critical check is therefore `status = PASS`, `severity = CRITICAL`, and `stop_pipeline = false`.

### Overall health

The dashboard derives health from the latest completed run:

1. `FAIL` if at least one check has status `FAIL`.
2. Otherwise `WARN` if at least one check has status `WARN`.
3. Otherwise `WARN` if no applicable checks ran, because there is no usable health signal.
4. Otherwise `PASS`.

`stop_pipeline` is a separate decision flag. This lets the dashboard distinguish an ordinary failed check from a critical failure that must halt processing.

## What every check must define

Before implementing a check, record these values in the result row:

| Requirement | Contract columns |
|---|---|
| WHAT | `check_name`, `check_description` |
| EXPECTATION | `expectation`, `expected_result` |
| THRESHOLD | `threshold_operator`, `threshold_value` |
| SEVERITY | `severity` |
| OWNER | `check_owner` |

Use a stable `check_id`. Example: `silver_student_vle_complete_business_key`. Do not put a timestamp in `check_id`; history depends on the identifier remaining stable.

## Table grain and relationships

### `open_university.oulad_quality.data_quality_results`

Grain: **one row per `run_id` + dataset + `check_id`**.

`check_result_id` is the technical link to failure details. Generate it once with `uuid()` and reuse the same value for every related failure row.

The dataset is identified by four fields: `dataset_catalog`, `dataset_schema`, `dataset_table`, and `dataset_layer`. This supports every OULAD table rather than hard-coding the current seven sources.

### `open_university.oulad_quality.data_quality_failures`

Grain: **one row per failed record or failed business key**.

For a composite key, store deterministic JSON in `failed_key`, for example:

```sql
to_json(named_struct(
  'code_module', code_module,
  'code_presentation', code_presentation,
  'id_student', id_student,
  'id_site', id_site,
  'date', date
))
```

For duplicate-key checks, write one failure row per duplicated key, not one row per physical duplicate. Put the duplicate count in `failure_metadata`, for example `map('duplicate_count', cast(duplicate_count as string))`.

For row-level checks, populate `failed_record_json` when the data is safe for dashboard users to see. Avoid storing unnecessary sensitive fields.

## Required write pattern

1. Generate one `run_id` at the start of the job and one `check_result_id` per check.
2. Calculate the failed rows/keys once in a temporary view or CTE.
3. Insert those rows into `data_quality_failures` using the check's `check_result_id`.
4. Insert one aggregate row into `data_quality_results` with the same identifiers.
5. Set `run_completed_at` only after the run completes. The latest-run dashboard views ignore incomplete runs.
6. Make retries idempotent with `MERGE` keys:
   - Results: `run_id + dataset_catalog + dataset_schema + dataset_table + check_id`
   - Failures: `failure_id`, or a deterministic hash of `run_id + check_result_id + failed_key`

When creating a deterministic failure identifier, use:

```sql
sha2(concat_ws('||', run_id, check_result_id, failed_key), 256)
```

## Dashboard drill-down

| Dashboard level | View | Answers |
|---|---|---|
| Overview | `vw_dq_dashboard_overview` | Overall health, pass rate, failed/warning checks, critical failures, affected datasets, last checked |
| Dataset | `vw_dq_dataset_health` | Which layer/table is unhealthy? |
| Check | `vw_dq_problem_checks` | What failed, what was expected, threshold, severity, and owner |
| Failure | `vw_dq_failure_detail` | Which actual rows or keys failed? |
| Trend | `vw_dq_history` | When did failure start, is quality worsening, and which dataset fails most often? |

The default dashboard filter should use the latest-run views. Historical charts should use `vw_dq_history`.

## Dashboard tiles

Use `vw_dq_dashboard_overview` for the five 10-second health tiles:

1. Overall Health: `overall_health`
2. Checks Passed: `checks_passed`, `applicable_checks`, `pass_rate_pct`
3. Failed Checks: `failed_checks` (with `warning_checks` shown separately)
4. Dataset/Table: `datasets_affected`, then drill into `vw_dq_dataset_health`
5. Last Checked: `last_checked`

Use `critical_failures` and `stop_pipeline` for the stop indicator. Use `vw_dq_failure_detail` to show the actual failed rows.

## Definition of done

- Run `00_create_data_quality_contract.sql` twice without errors.
- Confirm both Delta tables appear under `open_university.oulad_quality`.
- Load at least one row for each status and each check category in a development environment.
- Confirm `NOT_APPLICABLE` is excluded from `applicable_checks` and `pass_rate_pct`.
- Confirm any `FAIL` + `CRITICAL` result exposes `stop_pipeline = true`.
- Confirm all eight validation queries return zero rows.
- Confirm the dashboard drill-down follows Overview -> Dataset -> Check -> Failure.
