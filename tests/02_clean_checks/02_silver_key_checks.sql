-- ========================================================================================================
-- File: tests/02_clean_checks/02_silver_key_checks.sql
-- Branch: feature/clean-courses
--
-- Objective:
--    Verify business key integrity on currently implemented Silver clean tables.
--
--    Ensures:
--      1. Required business key attributes are not NULL.
--      2. The defined business key is unique.
--
-- Scope:
--    Currently implemented Silver transformation:
--      - courses_clean
--
-- Business Key:
--    courses_clean:
--      (code_module, code_presentation)
--
-- Output:
--    Read-only validation results showing invalid row/key counts and PASS/FAIL status.
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================


-- ========================================================================================================
-- CHECK 1: COURSES CLEAN - NULL BUSINESS KEY ATTRIBUTES
-- ========================================================================================================
--
-- Every Silver course record must contain both attributes required to identify its
-- module/presentation business key.
--
-- Expected result:
--    invalid_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_null_keys' AS check_name,

    COUNT(*) AS invalid_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE code_module IS NULL
   OR code_presentation IS NULL;


-- ========================================================================================================
-- CHECK 2: COURSES CLEAN - BUSINESS KEY UNIQUENESS
-- ========================================================================================================
--
-- The combination of code_module and code_presentation must identify exactly one
-- Silver course record.
--
-- Expected result:
--    duplicate_keys = 0
--    check_status = PASS
--
-- duplicate_keys counts the number of business-key combinations that occur more than once.
-- ========================================================================================================

SELECT

    'courses_clean_duplicate_keys' AS check_name,

    COUNT(*) AS duplicate_keys,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM (

    SELECT

        code_module,
        code_presentation,

        COUNT(*) AS row_count

    FROM open_university.oulad_silver.courses_clean

    GROUP BY
        code_module,
        code_presentation

    HAVING COUNT(*) > 1

) AS duplicate_key_groups;
