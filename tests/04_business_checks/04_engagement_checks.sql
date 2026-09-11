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
--
-- Purpose:
-- Validate VLE engagement measures against the current Gold dimensional model.
--
-- Validates:
-- 1. Silver-to-Gold VLE rows and clicks reconcile.
-- 2. Full enrollment population is preserved.
-- 3. Active students and active student-days use the correct grain.
-- 4. Active days are distinct across resources.
-- 5. Participation denominators include zero-activity students.
-- 6. Active students never exceed enrolled students.
-- 7. Relative-time bins handle negative days and Day 0 correctly.
-- 8. Relative-time click totals reconcile back to the VLE fact.
--
-- Read-only validation.
-- =============================================================================



-- =============================================================================
-- CHECK 1
-- SILVER → GOLD VLE RECONCILIATION
--
-- Expected:
-- silver_vle_rows = gold_vle_rows
-- silver_clicks   = gold_clicks
-- =============================================================================

select
    'SILVER_GOLD_VLE_RECONCILIATION' as check_name,

    (select count(*)
     from open_university.oulad_silver.student_vle_clean)
        as silver_vle_rows,

    (select count(*)
     from open_university.oulad_gold.fact_vle_interactions)
        as gold_vle_rows,

    (select sum(sum_click)
     from open_university.oulad_silver.student_vle_clean)
        as silver_clicks,

    (select sum(sum_click)
     from open_university.oulad_gold.fact_vle_interactions)
        as gold_clicks;



-- =============================================================================
-- CHECK 2
-- FULL ENROLLMENT POPULATION
--
-- Expected:
-- Silver enrollment count = reporting enrollment count
--
-- This confirms zero-activity enrollments are retained in the reporting layer.
-- =============================================================================

select
    'ENROLLMENT_RECONCILIATION' as check_name,

    (select count(*)
     from open_university.oulad_silver.student_info_clean)
        as silver_enrollments,

    (select count(*)
     from open_university.oulad_gold.vw_student_outcomes)
        as reporting_enrollments;



-- =============================================================================
-- CHECK 3
-- ACTIVE STUDENTS AND ACTIVE STUDENT-DAYS BY PRESENTATION
--
-- Active student:
-- at least one positive recorded click.
--
-- Active student-day:
-- one student + one relative day with positive clicks.
--
-- Multiple resources on the same day count only once.
-- =============================================================================

select
    code_module,
    code_presentation,

    count(
        distinct case
            when sum_click > 0 then id_student
        end
    ) as active_students,

    count(
        distinct case
            when sum_click > 0
            then concat_ws(
                '||',
                cast(id_student as string),
                cast(relative_day as string)
            )
        end
    ) as active_student_days,

    sum(sum_click) as total_clicks

from open_university.oulad_gold.fact_vle_interactions

group by
    code_module,
    code_presentation

order by
    code_module,
    code_presentation;



-- =============================================================================
-- CHECK 4
-- STUDENT-LEVEL ACTIVE DAYS
--
-- Grain:
-- code_module + code_presentation + id_student
--
-- Expected:
-- one distinct relative day counts once even when several resources were used.
-- =============================================================================

select
    code_module,
    code_presentation,
    id_student,

    count(
        distinct case
            when sum_click > 0 then relative_day
        end
    ) as active_days,

    sum(sum_click) as total_clicks

from open_university.oulad_gold.fact_vle_interactions

group by
    code_module,
    code_presentation,
    id_student

order by
    code_module,
    code_presentation,
    id_student;



-- =============================================================================
-- CHECK 5
-- PARTICIPATION DENOMINATOR
--
-- Enrollment denominator comes from vw_student_outcomes.
--
-- Expected:
-- active_students <= enrolled_students
--
-- zero_activity_students proves inactive enrollments remain in the denominator.
-- =============================================================================

with enrolled as (

    select
        code_module,
        code_presentation,
        count(*) as enrolled_students

    from open_university.oulad_gold.vw_student_outcomes

    group by
        code_module,
        code_presentation

),

active as (

    select
        code_module,
        code_presentation,

        count(
            distinct case
                when sum_click > 0 then id_student
            end
        ) as active_students

    from open_university.oulad_gold.fact_vle_interactions

    group by
        code_module,
        code_presentation

)

select
    e.code_module,
    e.code_presentation,

    e.enrolled_students,

    coalesce(a.active_students, 0)
        as active_students,

    e.enrolled_students
        - coalesce(a.active_students, 0)
        as zero_activity_students,

    round(
        100.0 * coalesce(a.active_students, 0)
        / nullif(e.enrolled_students, 0),
        2
    ) as participation_rate_pct,

    case
        when coalesce(a.active_students, 0)
            <= e.enrolled_students
            then 'PASS'
        else 'FAIL'
    end as validation_result

from enrolled e

left join active a
    on  e.code_module = a.code_module
    and e.code_presentation = a.code_presentation

order by
    e.code_module,
    e.code_presentation;



-- =============================================================================
-- CHECK 6
-- ORPHAN VLE ENROLLMENTS
--
-- Every student enrollment appearing in fact_vle_interactions should also
-- exist in vw_student_outcomes.
--
-- Expected:
-- ZERO ROWS
-- =============================================================================

select distinct
    v.code_module,
    v.code_presentation,
    v.id_student

from open_university.oulad_gold.fact_vle_interactions v

left join open_university.oulad_gold.vw_student_outcomes o
    on  v.code_module = o.code_module
    and v.code_presentation = o.code_presentation
    and v.id_student = o.id_student

where o.id_student is null;



-- =============================================================================
-- CHECK 7
-- RELATIVE-TIME CLASSIFICATION
--
-- Expected:
-- negative days = Before presentation
-- Day 0         = Day 0
-- days 1-7      = Week 1
-- days 8-14     = Week 2
-- etc.
-- =============================================================================

select
    relative_day,

    case
        when relative_day < 0
            then 'Before presentation'

        when relative_day = 0
            then 'Day 0'

        else concat(
            'Week ',
            cast(ceil(relative_day / 7.0) as int)
        )
    end as relative_time_group,

    case
        when relative_day < 0 then 0
        when relative_day = 0 then 1
        else cast(ceil(relative_day / 7.0) as int) + 1
    end as time_group_order,

    count(*) as interaction_rows,
    sum(sum_click) as total_clicks

from open_university.oulad_gold.fact_vle_interactions

group by
    relative_day

order by
    relative_day;



-- =============================================================================
-- CHECK 8
-- RELATIVE-TIME CLICK RECONCILIATION
--
-- Splitting fact rows into time groups must not lose or duplicate clicks.
--
-- Expected:
-- fact_clicks = grouped_clicks
-- validation_result = PASS
-- =============================================================================

with fact_total as (

    select
        sum(sum_click) as total_clicks

    from open_university.oulad_gold.fact_vle_interactions

),

time_group_totals as (

    select
        case
            when relative_day < 0
                then 'Before presentation'

            when relative_day = 0
                then 'Day 0'

            else concat(
                'Week ',
                cast(ceil(relative_day / 7.0) as int)
            )
        end as relative_time_group,

        sum(sum_click) as total_clicks

    from open_university.oulad_gold.fact_vle_interactions

    group by
        case
            when relative_day < 0
                then 'Before presentation'

            when relative_day = 0
                then 'Day 0'

            else concat(
                'Week ',
                cast(ceil(relative_day / 7.0) as int)
            )
        end

),

regrouped as (

    select
        sum(total_clicks) as grouped_clicks

    from time_group_totals

)

select
    f.total_clicks as fact_clicks,
    r.grouped_clicks,

    case
        when f.total_clicks = r.grouped_clicks
            then 'PASS'
        else 'FAIL'
    end as validation_result

from fact_total f
cross join regrouped r;



-- =============================================================================
-- CHECK 9
-- DIMENSION JOIN CLICK PRESERVATION
--
-- fact_vle_interactions already contains date_key.
-- Joining dim_date must not duplicate or drop fact rows/clicks.
--
-- Expected:
-- fact_clicks = joined_clicks
-- validation_result = PASS
-- =============================================================================

with fact_total as (

    select
        count(*) as fact_rows,
        sum(sum_click) as fact_clicks

    from open_university.oulad_gold.fact_vle_interactions

),

joined_total as (

    select
        count(*) as joined_rows,
        sum(v.sum_click) as joined_clicks

    from open_university.oulad_gold.fact_vle_interactions v

    inner join open_university.oulad_gold.dim_date d
        on v.date_key = d.date_key

)

select
    f.fact_rows,
    j.joined_rows,

    f.fact_clicks,
    j.joined_clicks,

    case
        when f.fact_rows = j.joined_rows
         and f.fact_clicks = j.joined_clicks
            then 'PASS'
        else 'FAIL'
    end as validation_result

from fact_total f
cross join joined_total j;