-- File: 04_engagement_checks.sql
-- Suggested branch: feature/vle-engagement
-- Purpose: Validate click totals, active-student counts and zero-activity coverage.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: 04_vle_engagement.sql output, Gold fact_vle_interactions and vw_student_outcomes.
-- Output: Read-only validation queries with failure counts/details and stated expected results; no data
--    changes.
--
-- What to put in this file:
-- 1. Recompute clicks and distinct active students under the exact report filters and active-student
--    definition.
-- 2. Validate enrollment active days using distinct dates across all resources; do not sum resource-day
--    counts.
-- 3. Check full-enrollment participation rates include zero-activity students from the outcomes view.
-- 4. Compare per-presentation totals to the VLE fact and confirm dimension joins preserve click totals.
-- 5. Check relative-time bins consistently handle negative days and day 0.
--
-- Use this file for manual Databricks checks. A runner must explicitly fail on violations; a displayed
--    result alone is not an automated test.
--
-- Done when: Click totals and participation measures reconcile with the stated grain and denominator.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.

-- =============================================================================
-- File: 04_engagement_checks.sql
-- Suggested branch: feature/vle-engagement
--
-- Purpose:
-- Validate VLE engagement metrics used by 04_vle_engagement.sql.
--
-- Validates:
-- 1. Enrollment click totals.
-- 2. Enrollment active-day counts.
-- 3. Full-enrollment participation denominator.
-- 4. Per-presentation click reconciliation.
-- 5. Activity-type click reconciliation.
-- 6. Relative-time classification.
-- 7. Relative-time click reconciliation.
--
-- Expected result:
-- ZERO ROWS = PASS
--
-- Important definitions:
-- - Active student = student with at least one recorded positive VLE click.
-- - Active day = distinct relative day with at least one positive VLE click.
-- - Multiple resources used by the same student on the same day count as
--   one active day.
-- - Negative relative days are valid.
-- - Relative day 0 is the presentation start.
-- - sum_click represents recorded VLE clicks, not study duration.
--
-- Input:
--   open_university.oulad_gold.fact_vle_interactions
--   open_university.oulad_gold.vw_student_outcomes
--
-- Read-only validation only.
-- =============================================================================


WITH


-- =============================================================================
-- 1. BASE VLE FACT
-- =============================================================================
-- Keep only the fields required for engagement validation.
-- Rename `date` to `relative_day` so its meaning is explicit.
-- =============================================================================

vle_fact AS (

    SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        date AS relative_day,
        activity_type,
        COALESCE(sum_click, 0) AS sum_click

    FROM open_university.oulad_gold.fact_vle_interactions

),


-- =============================================================================
-- 2. FULL ENROLLMENT POPULATION
-- =============================================================================
-- The outcomes view contains the full student-enrollment population.
-- This is important because students with no VLE activity do not necessarily
-- appear in fact_vle_interactions.
-- =============================================================================

outcomes AS (

    SELECT
        code_module,
        code_presentation,
        id_student,
        COALESCE(total_clicks, 0) AS reported_total_clicks,
        COALESCE(active_days, 0) AS reported_active_days

    FROM open_university.oulad_gold.vw_student_outcomes

),


-- =============================================================================
-- 3. RECOMPUTE ENGAGEMENT DIRECTLY FROM THE FACT TABLE
-- =============================================================================
-- Grain:
-- one row per student enrollment:
--
-- code_module + code_presentation + id_student
--
-- total_clicks:
-- Sum every recorded click for the enrollment.
--
-- active_days:
-- Count DISTINCT relative dates with positive clicks.
--
-- Example:
-- Student uses 3 resources on day 5 and 2 resources on day 6.
--
-- Active days = 2
-- NOT 5.
-- =============================================================================

expected_enrollment_engagement AS (

    SELECT
        code_module,
        code_presentation,
        id_student,

        SUM(sum_click) AS expected_total_clicks,

        COUNT(
            DISTINCT CASE
                WHEN sum_click > 0 THEN relative_day
            END
        ) AS expected_active_days

    FROM vle_fact

    GROUP BY
        code_module,
        code_presentation,
        id_student

),


-- =============================================================================
-- 4. CHECK OUTCOMES CLICK TOTALS
-- =============================================================================
-- Compare the engagement stored/reported in vw_student_outcomes against an
-- independent calculation directly from fact_vle_interactions.
--
-- Students without VLE interaction receive expected values of zero.
--
-- Failure means:
-- vw_student_outcomes does not preserve the same enrollment-level click total
-- as fact_vle_interactions.
-- =============================================================================

outcome_click_failures AS (

    SELECT
        'OUTCOME_CLICK_MISMATCH' AS failure_type,

        o.code_module,
        o.code_presentation,
        o.id_student,

        COALESCE(e.expected_total_clicks, 0) AS expected_value,
        o.reported_total_clicks AS actual_value,

        'Enrollment total clicks do not match fact_vle_interactions.'
            AS failure_details

    FROM outcomes o

    LEFT JOIN expected_enrollment_engagement e
        ON  o.code_module = e.code_module
        AND o.code_presentation = e.code_presentation
        AND o.id_student = e.id_student

    WHERE
        o.reported_total_clicks
        <> COALESCE(e.expected_total_clicks, 0)

),


-- =============================================================================
-- 5. CHECK ENROLLMENT ACTIVE DAYS
-- =============================================================================
-- Recompute active days using DISTINCT relative days across ALL resources.
--
-- This prevents a student using several resources on the same day from being
-- counted as active for several days.
--
-- Failure means:
-- The active-day metric is being over-counted or under-counted.
-- =============================================================================

active_day_failures AS (

    SELECT
        'ACTIVE_DAY_MISMATCH' AS failure_type,

        o.code_module,
        o.code_presentation,
        o.id_student,

        COALESCE(e.expected_active_days, 0) AS expected_value,
        o.reported_active_days AS actual_value,

        'Active days must equal distinct positive-click relative days across all resources.'
            AS failure_details

    FROM outcomes o

    LEFT JOIN expected_enrollment_engagement e
        ON  o.code_module = e.code_module
        AND o.code_presentation = e.code_presentation
        AND o.id_student = e.id_student

    WHERE
        o.reported_active_days
        <> COALESCE(e.expected_active_days, 0)

),


-- =============================================================================
-- 6. CHECK THAT EVERY ACTIVE VLE ENROLLMENT EXISTS IN OUTCOMES
-- =============================================================================
-- An interaction must belong to an enrollment represented in the outcomes
-- population.
--
-- Failure means:
-- We have VLE activity for a student enrollment that is missing from the
-- reporting population.
-- =============================================================================

missing_outcome_enrollment_failures AS (

    SELECT
        'VLE_ENROLLMENT_MISSING_FROM_OUTCOMES' AS failure_type,

        e.code_module,
        e.code_presentation,
        e.id_student,

        CAST(1 AS BIGINT) AS expected_value,
        CAST(0 AS BIGINT) AS actual_value,

        'VLE enrollment exists in the fact table but not in vw_student_outcomes.'
            AS failure_details

    FROM expected_enrollment_engagement e

    LEFT JOIN outcomes o
        ON  e.code_module = o.code_module
        AND e.code_presentation = o.code_presentation
        AND e.id_student = o.id_student

    WHERE o.id_student IS NULL

),


-- =============================================================================
-- 7. FULL ENROLLMENT DENOMINATOR
-- =============================================================================
-- Count every enrollment from vw_student_outcomes.
--
-- This is the denominator for participation.
-- It includes:
-- - active students
-- - students with zero recorded VLE activity
-- =============================================================================

presentation_population AS (

    SELECT
        code_module,
        code_presentation,
        COUNT(*) AS enrolled_students

    FROM outcomes

    GROUP BY
        code_module,
        code_presentation

),


-- =============================================================================
-- 8. ACTIVE STUDENTS DIRECTLY FROM VLE FACT
-- =============================================================================
-- Active student definition:
--
-- At least one fact row with sum_click > 0.
--
-- COUNT(DISTINCT id_student) prevents the same student from being counted
-- several times because they have many VLE records.
-- =============================================================================

presentation_active_students AS (

    SELECT
        code_module,
        code_presentation,

        COUNT(
            DISTINCT CASE
                WHEN sum_click > 0 THEN id_student
            END
        ) AS active_students

    FROM vle_fact

    GROUP BY
        code_module,
        code_presentation

),


-- =============================================================================
-- 9. PARTICIPATION DENOMINATOR CHECK
-- =============================================================================
-- Active students must never exceed total enrolled students.
--
-- Example:
--
-- Enrolled = 1,000
-- Active   =   700
--
-- Valid.
--
-- Enrolled = 1,000
-- Active   = 1,050
--
-- Invalid.
--
-- This helps identify denominator problems or orphan VLE records.
-- =============================================================================

participation_failures AS (

    SELECT
        'ACTIVE_STUDENTS_EXCEED_ENROLLMENT' AS failure_type,

        p.code_module,
        p.code_presentation,

        CAST(NULL AS BIGINT) AS id_student,

        p.enrolled_students AS expected_value,
        COALESCE(a.active_students, 0) AS actual_value,

        'Active students cannot exceed the full enrollment population.'
            AS failure_details

    FROM presentation_population p

    LEFT JOIN presentation_active_students a
        ON  p.code_module = a.code_module
        AND p.code_presentation = a.code_presentation

    WHERE
        COALESCE(a.active_students, 0) > p.enrolled_students

),


-- =============================================================================
-- 10. FACT CLICK TOTALS BY PRESENTATION
-- =============================================================================
-- This is our reference total before creating reporting groupings.
-- =============================================================================

fact_presentation_clicks AS (

    SELECT
        code_module,
        code_presentation,
        SUM(sum_click) AS fact_total_clicks

    FROM vle_fact

    GROUP BY
        code_module,
        code_presentation

),


-- =============================================================================
-- 11. OUTCOMES CLICK TOTALS BY PRESENTATION
-- =============================================================================
-- Sum enrollment-level click totals from the full outcomes population.
--
-- This should equal the original fact total for each presentation.
-- =============================================================================

outcomes_presentation_clicks AS (

    SELECT
        code_module,
        code_presentation,
        SUM(reported_total_clicks) AS outcomes_total_clicks

    FROM outcomes

    GROUP BY
        code_module,
        code_presentation

),


-- =============================================================================
-- 12. PRESENTATION CLICK RECONCILIATION
-- =============================================================================
-- Verify that rolling engagement up through the outcomes view did not create
-- or lose clicks.
-- =============================================================================

presentation_click_failures AS (

    SELECT
        'PRESENTATION_CLICK_MISMATCH' AS failure_type,

        f.code_module,
        f.code_presentation,

        CAST(NULL AS BIGINT) AS id_student,

        f.fact_total_clicks AS expected_value,
        COALESCE(o.outcomes_total_clicks, 0) AS actual_value,

        'Presentation click total does not reconcile between fact and outcomes.'
            AS failure_details

    FROM fact_presentation_clicks f

    LEFT JOIN outcomes_presentation_clicks o
        ON  f.code_module = o.code_module
        AND f.code_presentation = o.code_presentation

    WHERE
        f.fact_total_clicks
        <> COALESCE(o.outcomes_total_clicks, 0)

),


-- =============================================================================
-- 13. ACTIVITY-TYPE TOTALS
-- =============================================================================
-- Group recorded clicks by activity type.
--
-- COALESCE preserves fact rows where activity_type is missing by putting them
-- into an explicit "Unknown" reporting category.
-- =============================================================================

activity_type_clicks AS (

    SELECT
        code_module,
        code_presentation,
        COALESCE(activity_type, 'Unknown') AS activity_type,
        SUM(sum_click) AS activity_type_clicks

    FROM vle_fact

    GROUP BY
        code_module,
        code_presentation,
        COALESCE(activity_type, 'Unknown')

),


-- =============================================================================
-- 14. RE-AGGREGATE ACTIVITY-TYPE TOTALS
-- =============================================================================
-- After splitting clicks into resource/activity categories, add those groups
-- back together.
--
-- The resulting total must equal the original fact total.
-- =============================================================================

activity_type_presentation_totals AS (

    SELECT
        code_module,
        code_presentation,
        SUM(activity_type_clicks) AS regrouped_clicks

    FROM activity_type_clicks

    GROUP BY
        code_module,
        code_presentation

),


-- =============================================================================
-- 15. ACTIVITY-TYPE RECONCILIATION CHECK
-- =============================================================================

activity_type_failures AS (

    SELECT
        'ACTIVITY_TYPE_CLICK_MISMATCH' AS failure_type,

        f.code_module,
        f.code_presentation,

        CAST(NULL AS BIGINT) AS id_student,

        f.fact_total_clicks AS expected_value,
        COALESCE(a.regrouped_clicks, 0) AS actual_value,

        'Clicks grouped by activity type do not add back to the fact total.'
            AS failure_details

    FROM fact_presentation_clicks f

    LEFT JOIN activity_type_presentation_totals a
        ON  f.code_module = a.code_module
        AND f.code_presentation = a.code_presentation

    WHERE
        f.fact_total_clicks
        <> COALESCE(a.regrouped_clicks, 0)

),


-- =============================================================================
-- 16. ASSIGN RELATIVE-TIME GROUPS
-- =============================================================================
-- OULAD dates are relative to presentation start.
--
-- Negative values:
-- before presentation
--
-- Day 0:
-- presentation start
--
-- Positive days:
-- Week 1 = days 1-7
-- Week 2 = days 8-14
-- Week 3 = days 15-21
-- etc.
--
-- Negative values must NOT be treated as invalid dates.
-- =============================================================================

vle_with_time_group AS (

    SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day,
        activity_type,
        sum_click,

        CASE
            WHEN relative_day < 0
                THEN 'Before presentation'

            WHEN relative_day = 0
                THEN 'Day 0'

            ELSE CONCAT(
                'Week ',
                CAST(CEIL(relative_day / 7.0) AS INT)
            )
        END AS relative_time_group,

        CASE
            WHEN relative_day < 0
                THEN 0

            WHEN relative_day = 0
                THEN 1

            ELSE CAST(CEIL(relative_day / 7.0) AS INT) + 1
        END AS time_group_order

    FROM vle_fact

),


-- =============================================================================
-- 17. VALIDATE RELATIVE-TIME CLASSIFICATION
-- =============================================================================
-- Explicitly look for rows placed into an incorrect time group.
--
-- Any returned row here means the report's timeline logic is inconsistent.
-- =============================================================================

time_bin_failures AS (

    SELECT
        'INVALID_RELATIVE_TIME_BIN' AS failure_type,

        code_module,
        code_presentation,
        id_student,

        CAST(relative_day AS BIGINT) AS expected_value,
        CAST(time_group_order AS BIGINT) AS actual_value,

        CONCAT(
            'Relative day ',
            CAST(relative_day AS STRING),
            ' was classified as ',
            relative_time_group
        ) AS failure_details

    FROM vle_with_time_group

    WHERE

        -- Negative days must be "Before presentation".
        (
            relative_day < 0
            AND (
                relative_time_group <> 'Before presentation'
                OR time_group_order <> 0
            )
        )

        OR

        -- Day 0 must be its own category.
        (
            relative_day = 0
            AND (
                relative_time_group <> 'Day 0'
                OR time_group_order <> 1
            )
        )

        OR

        -- Positive days must belong to Week 1 or later.
        (
            relative_day > 0
            AND (
                relative_time_group
                    <> CONCAT(
                        'Week ',
                        CAST(CEIL(relative_day / 7.0) AS INT)
                    )

                OR time_group_order
                    <> CAST(CEIL(relative_day / 7.0) AS INT) + 1
            )
        )

),


-- =============================================================================
-- 18. TOTAL CLICKS BY RELATIVE-TIME GROUP
-- =============================================================================

relative_time_clicks AS (

    SELECT
        code_module,
        code_presentation,
        relative_time_group,
        time_group_order,
        SUM(sum_click) AS time_group_clicks

    FROM vle_with_time_group

    GROUP BY
        code_module,
        code_presentation,
        relative_time_group,
        time_group_order

),


-- =============================================================================
-- 19. ADD TIME-GROUP TOTALS BACK TO PRESENTATION LEVEL
-- =============================================================================
-- Splitting clicks into time buckets must not change the number of clicks.
-- =============================================================================

relative_time_presentation_totals AS (

    SELECT
        code_module,
        code_presentation,
        SUM(time_group_clicks) AS regrouped_clicks

    FROM relative_time_clicks

    GROUP BY
        code_module,
        code_presentation

),


-- =============================================================================
-- 20. RELATIVE-TIME CLICK RECONCILIATION
-- =============================================================================

relative_time_failures AS (

    SELECT
        'RELATIVE_TIME_CLICK_MISMATCH' AS failure_type,

        f.code_module,
        f.code_presentation,

        CAST(NULL AS BIGINT) AS id_student,

        f.fact_total_clicks AS expected_value,
        COALESCE(t.regrouped_clicks, 0) AS actual_value,

        'Clicks grouped into relative-time bins do not add back to the fact total.'
            AS failure_details

    FROM fact_presentation_clicks f

    LEFT JOIN relative_time_presentation_totals t
        ON  f.code_module = t.code_module
        AND f.code_presentation = t.code_presentation

    WHERE
        f.fact_total_clicks
        <> COALESCE(t.regrouped_clicks, 0)

),


-- =============================================================================
-- 21. COMBINE ALL FAILURES
-- =============================================================================

all_failures AS (

    SELECT * FROM outcome_click_failures

    UNION ALL

    SELECT * FROM active_day_failures

    UNION ALL

    SELECT * FROM missing_outcome_enrollment_failures

    UNION ALL

    SELECT * FROM participation_failures

    UNION ALL

    SELECT * FROM presentation_click_failures

    UNION ALL

    SELECT * FROM activity_type_failures

    UNION ALL

    SELECT * FROM time_bin_failures

    UNION ALL

    SELECT * FROM relative_time_failures

)


-- =============================================================================
-- FINAL RESULT
-- =============================================================================
--
-- Expected:
--
-- ZERO ROWS
--
-- If rows appear, inspect failure_type, expected_value, actual_value and
-- failure_details to determine which business rule failed.
-- =============================================================================

SELECT
    failure_type,
    code_module,
    code_presentation,
    id_student,
    expected_value,
    actual_value,
    failure_details

FROM all_failures

ORDER BY
    failure_type,
    code_module,
    code_presentation,
    id_student;