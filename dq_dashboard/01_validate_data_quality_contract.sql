-- =============================================================================
-- DATA QUALITY CONTRACT VALIDATION
-- Expected result for every query in this file: zero rows.
-- Read-only and safe to rerun.
-- =============================================================================

USE CATALOG open_university;

-- 1. Exactly one result per run + dataset + check.
SELECT
    run_id,
    dataset_catalog,
    dataset_schema,
    dataset_table,
    check_id,
    COUNT(*) AS duplicate_count
FROM open_university.oulad_quality.data_quality_results
GROUP BY
    run_id,
    dataset_catalog,
    dataset_schema,
    dataset_table,
    check_id
HAVING COUNT(*) > 1;

-- 2. Contract enums are valid.
SELECT *
FROM open_university.oulad_quality.data_quality_results
WHERE check_type NOT IN (
        'NULL',
        'UNIQUE',
        'RANGE',
        'ACCEPTED_VALUES',
        'REFERENTIAL_INTEGRITY',
        'VOLUME'
    )
    OR status NOT IN ('PASS', 'WARN', 'FAIL', 'NOT_APPLICABLE')
    OR severity NOT IN ('WARN', 'FAIL', 'CRITICAL')
    OR dataset_layer NOT IN ('BRONZE', 'SILVER', 'GOLD', 'OTHER');

-- 3. Counts and percentages are internally consistent.
SELECT *
FROM open_university.oulad_quality.data_quality_results
WHERE fail_count < 0
    OR total_count < 0
    OR fail_count > total_count
    OR fail_pct < 0
    OR fail_pct > 100
    OR status IN ('PASS', 'NOT_APPLICABLE') AND fail_count <> 0
    OR total_count > 0
        AND ABS(fail_pct - (100.0 * fail_count / total_count)) > 0.000001;

-- 4. Critical stop rule is exact and cannot silently drift.
SELECT *
FROM open_university.oulad_quality.data_quality_results
WHERE stop_pipeline <> (status = 'FAIL' AND severity = 'CRITICAL');

-- 5. Completed runs have sensible timestamps.
SELECT *
FROM open_university.oulad_quality.data_quality_results
WHERE executed_at < run_started_at
    OR run_completed_at < run_started_at
    OR run_completed_at < executed_at;

-- 6. Failure details always have a parent result.
SELECT f.*
FROM open_university.oulad_quality.data_quality_failures f
LEFT ANTI JOIN open_university.oulad_quality.data_quality_results r
    ON f.check_result_id = r.check_result_id
    AND f.run_id = r.run_id;

-- 7. Failure detail agrees with its parent result and enum contract.
SELECT f.*
FROM open_university.oulad_quality.data_quality_failures f
INNER JOIN open_university.oulad_quality.data_quality_results r
    ON f.check_result_id = r.check_result_id
    AND f.run_id = r.run_id
WHERE r.status NOT IN ('WARN', 'FAIL')
    OR f.check_id <> r.check_id
    OR f.check_type <> r.check_type
    OR f.severity <> r.severity
    OR f.dataset_catalog <> r.dataset_catalog
    OR f.dataset_schema <> r.dataset_schema
    OR f.dataset_table <> r.dataset_table
    OR f.dataset_layer <> r.dataset_layer;

-- 8. Stored fail_count matches captured failure rows.
-- VOLUME checks may have no source row to capture, so they are excluded.
SELECT
    r.check_result_id,
    r.run_id,
    r.check_id,
    r.fail_count AS stored_fail_count,
    COUNT(f.failure_id) AS captured_failure_count
FROM open_university.oulad_quality.data_quality_results r
LEFT JOIN open_university.oulad_quality.data_quality_failures f
    ON r.check_result_id = f.check_result_id
    AND r.run_id = f.run_id
WHERE r.check_type <> 'VOLUME'
GROUP BY r.check_result_id, r.run_id, r.check_id, r.fail_count
HAVING r.fail_count <> COUNT(f.failure_id);
