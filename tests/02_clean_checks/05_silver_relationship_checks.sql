-- ========================================================================================================
-- File: tests/02_clean_checks/05_silver_relationship_checks.sql
-- Branch: feature/clean-students
--
-- Objective:
--    Validate required parent-child relationships for the student Silver tables using the
--    complete business keys defined by the pipeline.
--
--    Ensures:
--      1. Every student_info_clean enrollment belongs to an existing course/module presentation.
--      2. Every student_registration_clean record belongs to an existing student enrollment.
--      3. Relationship checks use the complete composite keys rather than incomplete joins.
--
-- Scope:
--    Silver transformations owned by Task #9:
--      - student_info_clean
--      - student_registration_clean
--
-- Required Relationships:
--    student_info_clean -> courses_clean:
--      code_module + code_presentation
--
--    student_registration_clean -> student_info_clean:
--      code_module + code_presentation + id_student
--
-- Important Relationship Decisions:
--    - student_info_clean is validated against courses_clean using both module and presentation
--      codes because a module may have multiple presentations.
--
--    - student_registration_clean is validated against student_info_clean using the complete
--      enrollment key.
--
--    - id_student alone must not be used for the registration-to-enrollment relationship because
--      the same student may appear in multiple module presentations.
--
--    - LEFT JOIN is used so child rows without a matching parent remain visible and can be counted
--      as orphan records.
--
-- Expected Results:
--    student_info_clean -> courses_clean:
--      orphan_count = 0
--
--    student_registration_clean -> student_info_clean:
--      orphan_count = 0
--
-- Output:
--    Read-only validation results showing the relationship name, orphan count,
--    and PASS/FAIL status.
--
-- No data is inserted, updated, deleted, or otherwise modified by this file.
-- ========================================================================================================


-- ========================================================================================================
-- CHECK 1: STUDENT INFO CLEAN -> COURSES CLEAN
-- ========================================================================================================
--
-- Every student enrollment must reference an existing module presentation in courses_clean.
--
-- Relationship key:
--    student_info_clean.code_module
--      = courses_clean.code_module
--
--    student_info_clean.code_presentation
--      = courses_clean.code_presentation
--
-- A row is considered an orphan when no matching courses_clean parent record exists.
--
-- Expected result:
--    orphan_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_info_clean -> courses_clean' AS relationship_name,

    COUNT(*) AS orphan_count,

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END AS status

FROM open_university.oulad_silver.student_info_clean AS si

LEFT JOIN open_university.oulad_silver.courses_clean AS c
    ON  si.code_module = c.code_module
    AND si.code_presentation = c.code_presentation

WHERE c.code_module IS NULL


UNION ALL


-- ========================================================================================================
-- CHECK 2: STUDENT REGISTRATION CLEAN -> STUDENT INFO CLEAN
-- ========================================================================================================
--
-- Every registration record must correspond to an existing student enrollment.
--
-- Relationship key:
--    student_registration_clean.code_module
--      = student_info_clean.code_module
--
--    student_registration_clean.code_presentation
--      = student_info_clean.code_presentation
--
--    student_registration_clean.id_student
--      = student_info_clean.id_student
--
-- The complete enrollment key is required here. Matching only on id_student would be incorrect
-- because one student may legitimately have multiple enrollments across module presentations.
--
-- A row is considered an orphan when no corresponding student_info_clean enrollment exists.
--
-- Expected result:
--    orphan_count = 0
--    status = Pass
-- ========================================================================================================

SELECT
    'student_registration_clean -> student_info_clean',

    COUNT(*),

    CASE
        WHEN COUNT(*) = 0 THEN 'Pass'
        ELSE 'Fail'
    END

FROM open_university.oulad_silver.student_registration_clean AS sr

LEFT JOIN open_university.oulad_silver.student_info_clean AS si
    ON  sr.code_module = si.code_module
    AND sr.code_presentation = si.code_presentation
    AND sr.id_student = si.id_student

WHERE si.id_student IS NULL;