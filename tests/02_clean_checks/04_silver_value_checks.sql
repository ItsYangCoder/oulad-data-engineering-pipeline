-- ========================================================================================================
-- File: tests/02_clean_checks/04_silver_value_checks.sql
-- Branch: feature/clean-courses
--
-- Objective:
--    Validate domain value integrity and metadata flag accuracy on currently implemented
--    Silver clean tables.
--
--    Ensures:
--      1. module_presentation_length contains only valid positive values when populated.
--      2. is_valid_length correctly reflects the validity of module_presentation_length.
--      3. Invalid business-key records are not present in the clean Silver table.
--
-- Scope:
--    Currently implemented Silver transformation:
--      - courses_clean
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================


-- ========================================================================================================
-- CHECK 1: COURSES CLEAN - LENGTH DOMAIN VALIDITY
-- ========================================================================================================
--
-- module_presentation_length must be a positive value when populated.
--
-- Invalid values include:
--    - zero
--    - negative values
--
-- NULL is not treated as a domain violation here because missing values are handled separately
-- by the is_valid_length flag check.
--
-- Expected result:
--    invalid_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_invalid_length_values' AS check_name,

    COUNT(*) AS invalid_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE module_presentation_length IS NOT NULL
  AND module_presentation_length <= 0;


-- ========================================================================================================
-- CHECK 2: COURSES CLEAN - LENGTH FLAG ACCURACY
-- ========================================================================================================
--
-- is_valid_length must correctly describe module_presentation_length.
--
-- Expected rule:
--    TRUE  -> module_presentation_length is present and greater than zero.
--    FALSE -> module_presentation_length is NULL or not greater than zero.
--
-- Expected result:
--    mismatch_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_flag_accuracy' AS check_name,

    COUNT(*) AS mismatch_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE
      (
          is_valid_length = TRUE
          AND (
              module_presentation_length IS NULL
              OR module_presentation_length <= 0
          )
      )

   OR (
          is_valid_length = FALSE
          AND (
              module_presentation_length IS NOT NULL
              AND module_presentation_length > 0
          )
      );


-- ========================================================================================================
-- CHECK 3: COURSES CLEAN - BUSINESS KEY FLAG ACCURACY
-- ========================================================================================================
--
-- Invalid business keys should not remain in courses_clean.
--
-- Invalid/conflicting business-key records are expected to be handled by the
-- courses_clean transformation and routed to the quarantine table.
--
-- Expected result:
--    invalid_key_flag_rows = 0
--    check_status = PASS
-- ========================================================================================================

SELECT

    'courses_clean_is_valid_key_check' AS check_name,

    COUNT(*) AS invalid_key_flag_rows,

    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS check_status

FROM open_university.oulad_silver.courses_clean

WHERE is_valid_key = FALSE;
