-- Zero rows means pass. View active_days counts recorded days, including zero-click records.
WITH
vle_fact AS (
    SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day,
        activity_type,
        sum_click AS sum_click
    FROM open_university.oulad_gold.fact_vle_interactions
),
outcomes AS (
    SELECT
        code_module,
        code_presentation,
        id_student,
        total_clicks AS reported_total_clicks,
        active_days AS reported_active_days
    FROM open_university.oulad_gold.vw_student_outcomes
),
expected_enrollment_engagement AS (
    SELECT
        code_module,
        code_presentation,
        id_student,
        SUM(sum_click) AS expected_total_clicks,
        COUNT(DISTINCT relative_day) AS expected_active_days
    FROM vle_fact
    GROUP BY
        code_module,
        code_presentation,
        id_student
),
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
        o.reported_total_clicks IS NULL OR o.reported_total_clicks
        <> COALESCE(e.expected_total_clicks, 0)
),
active_day_failures AS (
    SELECT
        'ACTIVE_DAY_MISMATCH' AS failure_type,
        o.code_module,
        o.code_presentation,
        o.id_student,
        COALESCE(e.expected_active_days, 0) AS expected_value,
        o.reported_active_days AS actual_value,
        'Active days must equal distinct recorded relative days across all resources.'
            AS failure_details
    FROM outcomes o
    LEFT JOIN expected_enrollment_engagement e
        ON  o.code_module = e.code_module
        AND o.code_presentation = e.code_presentation
        AND o.id_student = e.id_student
    WHERE
        o.reported_active_days IS NULL OR o.reported_active_days
        <> COALESCE(e.expected_active_days, 0)
),
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
activity_type_clicks AS (
    SELECT
        code_module,
        code_presentation,
        activity_type AS activity_type,
        SUM(sum_click) AS activity_type_clicks
    FROM vle_fact
    GROUP BY
        code_module,
        code_presentation,
        activity_type
),
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
        (
            relative_day < 0
            AND (
                relative_time_group <> 'Before presentation'
                OR time_group_order <> 0
            )
        )
        OR
        (
            relative_day = 0
            AND (
                relative_time_group <> 'Day 0'
                OR time_group_order <> 1
            )
        )
        OR
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
