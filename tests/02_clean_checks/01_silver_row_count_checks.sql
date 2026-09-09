-- ========================================================================================================
-- File: tests/02_clean_checks/01_silver_row_count_checks.sql
-- Branch: feature/clean-courses
--
-- Objective:
--    Validate Bronze-to-Silver row accounting for the currently implemented Silver transformations.
--
--    The check identifies whether Bronze source rows are fully accounted for across:
--      - Silver clean records
--      - Silver quarantine records
--      - documented deduplication
--
--    A zero leakage count indicates that the transformation accounts for all source rows.
--
-- Scope:
--    Currently implemented Silver transformation:
--      - courses
--
-- Output:
--    One validation record showing Bronze rows, Silver clean rows, quarantine rows,
--    accounted rows, leakage count, and PASS/FAIL status.
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================


WITH raw_counts AS (

    SELECT
        COUNT(*) AS raw_count
    FROM open_university.oulad_bronze.courses_raw

),

clean_counts AS (

    SELECT
        COUNT(*) AS clean_count
    FROM open_university.oulad_silver.courses_clean

),

quarantine_counts AS (

    SELECT
        COALESCE(SUM(source_row_count), 0) AS quarantine_count
    FROM open_university.oulad_silver.courses_invalid_key_quarantine

)

SELECT

    'courses' AS entity_name,

    raw.raw_count,

    clean.clean_count,

    quarantine.quarantine_count,

    clean.clean_count
        + quarantine.quarantine_count
        AS accounted_count,

    raw.raw_count
        - (
            clean.clean_count
            + quarantine.quarantine_count
          )
        AS leakage_count,

    CASE
        WHEN raw.raw_count
             - (
                 clean.clean_count
                 + quarantine.quarantine_count
               ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM raw_counts AS raw

CROSS JOIN clean_counts AS clean

CROSS JOIN quarantine_counts AS quarantine;