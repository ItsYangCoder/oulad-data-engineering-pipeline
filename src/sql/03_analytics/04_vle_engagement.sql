-- File: 04_vle_engagement.sql
-- Suggested branch: feature/vle-engagement
-- Purpose: Summarize recorded clicks and participation across resource types and relative time.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: open_university.oulad_gold.fact_vle_interactions, dim_date and other relevant dimensions;
--    vw_student_outcomes for all-enrollment rates.
-- Output: Read-only result set for Metabase; no CREATE, MERGE, INSERT or table rebuild.
-- Grain / business key: One output row per declared presentation, activity type or relative-time group.
--
-- What to put in this file:
-- 1. Return SUM(sum_click), distinct active students, and clearly defined active-day measures.
-- 2. At enrollment grain, count distinct interaction dates across resources; do not add per-resource
--    day counts.
-- 3. Use the outcomes view when a denominator must include students with no activity; a fact-only query
--    covers active records only.
-- 4. Use relative days/weeks for trends and state whether a student with a zero-click record counts as
--    active.
-- 5. Treat sum_click as recorded clicks, not time spent studying, sessions or resource quality.
-- 6. Aggregate VLE and assessment facts separately before relating engagement to performance.
--
--
-- Done when: Click totals reconcile to the VLE fact and participation denominators are explicit;
--    tests/04_business_checks/04_engagement_checks.sql passes.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.


-- =============================================================================
-- File: 04_vle_engagement.sql
-- Branch: feature/vle-engagement
-- Purpose:
--   Summarize recorded VLE clicks and participation by:
--     1. module presentation
--     2. VLE activity type
--     3. relative-time group
--
-- Important definitions:
--   - "Clicks" means recorded VLE clicks only.
--   - Clicks are NOT study duration, sessions, learning quality or attention.
--   - An active student has at least one row where sum_click > 0.
--   - An active day is a distinct relative interaction date on which a student
--     recorded at least one click.
--   - Enrollment active days are counted across ALL resources first.
--     Resource-level day counts must not be added together.
--   - Participation denominators come from vw_student_outcomes so students
--     with zero recorded VLE activity remain in the denominator.
--
-- Output grain:
--   One row per:
--     PRESENTATION
--     PRESENTATION + ACTIVITY_TYPE
--     PRESENTATION + RELATIVE_TIME_GROUP
--
-- Read-only query for Databricks / Metabase.
-- =============================================================================


with outcomes as (

    -- Complete enrollment population.
    -- Includes students with zero recorded VLE activity.
    select
        code_module,
        code_presentation,
        id_student
    from open_university.oulad_gold.vw_student_outcomes

),


vle_fact as (

    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        date as relative_day,
        activity_type,
        sum_click
    from open_university.oulad_gold.fact_vle_interactions

),


-- ---------------------------------------------------------------------------
-- Enrollment-level engagement
--
-- IMPORTANT:
-- Count distinct interaction dates across ALL VLE resources before
-- aggregating to presentation level.
-- ---------------------------------------------------------------------------

enrollment_engagement as (

    select
        code_module,
        code_presentation,
        id_student,

        sum(sum_click) as total_clicks,

        count(
            distinct case
                when sum_click > 0 then relative_day
            end
        ) as active_days

    from vle_fact

    group by
        code_module,
        code_presentation,
        id_student

),


-- ---------------------------------------------------------------------------
-- Complete enrollment population joined to engagement.
--
-- Students without a VLE interaction receive:
--   total_clicks = 0
--   active_days  = 0
-- ---------------------------------------------------------------------------

enrollment_population as (

    select
        o.code_module,
        o.code_presentation,
        o.id_student,

        coalesce(e.total_clicks, 0) as total_clicks,
        coalesce(e.active_days, 0) as active_days

    from outcomes o

    left join enrollment_engagement e
        on  o.code_module = e.code_module
        and o.code_presentation = e.code_presentation
        and o.id_student = e.id_student

),


-- ---------------------------------------------------------------------------
-- Presentation-level denominator.
-- ---------------------------------------------------------------------------

presentation_population as (

    select
        code_module,
        code_presentation,
        count(*) as enrolled_students

    from outcomes

    group by
        code_module,
        code_presentation

),


-- ---------------------------------------------------------------------------
-- 1. PRESENTATION SUMMARY
--
-- total_active_days here is the sum of correctly calculated enrollment
-- active-day counts.
--
-- Because each student's distinct dates were counted before this aggregation,
-- accessing several resources on the same day counts as ONE active day for
-- that student's enrollment.
-- ---------------------------------------------------------------------------

presentation_summary as (

    select
        'PRESENTATION' as analysis_level,

        code_module,
        code_presentation,

        cast(null as string) as activity_type,
        cast(null as string) as relative_time_group,
        cast(null as int) as time_group_order,

        count(*) as enrolled_students,

        sum(
            case
                when active_days > 0 then 1
                else 0
            end
        ) as active_students,

        sum(total_clicks) as total_clicks,

        sum(active_days) as total_student_active_days,

        avg(
            case
                when active_days > 0
                    then cast(active_days as double)
            end
        ) as avg_active_days_per_active_student

    from enrollment_population

    group by
        code_module,
        code_presentation

),


-- ---------------------------------------------------------------------------
-- 2. ACTIVITY-TYPE SUMMARY
--
-- The denominator is still ALL enrollments in the presentation.
--
-- A student using two resource types appears as active in both categories.
-- Therefore activity-type active-student counts should NOT be summed to get
-- presentation-level active students.
-- ---------------------------------------------------------------------------

activity_type_summary as (

    select
        'ACTIVITY_TYPE' as analysis_level,

        f.code_module,
        f.code_presentation,

        coalesce(f.activity_type, 'Unknown') as activity_type,

        cast(null as string) as relative_time_group,
        cast(null as int) as time_group_order,

        p.enrolled_students,

        count(
            distinct case
                when f.sum_click > 0 then f.id_student
            end
        ) as active_students,

        sum(f.sum_click) as total_clicks,

        count(
            distinct case
                when f.sum_click > 0
                    then concat(
                        cast(f.id_student as string),
                        '||',
                        cast(f.relative_day as string)
                    )
            end
        ) as total_student_active_days,

        cast(null as double) as avg_active_days_per_active_student

    from vle_fact f

    inner join presentation_population p
        on  f.code_module = p.code_module
        and f.code_presentation = p.code_presentation

    group by
        f.code_module,
        f.code_presentation,
        coalesce(f.activity_type, 'Unknown'),
        p.enrolled_students

),


-- ---------------------------------------------------------------------------
-- Relative-time classification.
--
-- Negative values are valid and represent activity before presentation start.
-- Day 0 is explicitly separated.
--
-- Positive days:
--   Day 1-7   = Week 1
--   Day 8-14  = Week 2
--   Day 15-21 = Week 3
--   etc.
-- ---------------------------------------------------------------------------

vle_with_time_group as (

    select
        *,

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
        end as time_group_order

    from vle_fact

),


-- ---------------------------------------------------------------------------
-- 3. RELATIVE-TIME SUMMARY
--
-- Again, active students across time groups are NOT additive because the same
-- student can be active in several weeks.
-- ---------------------------------------------------------------------------

relative_time_summary as (

    select
        'RELATIVE_TIME' as analysis_level,

        f.code_module,
        f.code_presentation,

        cast(null as string) as activity_type,

        f.relative_time_group,
        f.time_group_order,

        p.enrolled_students,

        count(
            distinct case
                when f.sum_click > 0 then f.id_student
            end
        ) as active_students,

        sum(f.sum_click) as total_clicks,

        count(
            distinct case
                when f.sum_click > 0
                    then concat(
                        cast(f.id_student as string),
                        '||',
                        cast(f.relative_day as string)
                    )
            end
        ) as total_student_active_days,

        cast(null as double) as avg_active_days_per_active_student

    from vle_with_time_group f

    inner join presentation_population p
        on  f.code_module = p.code_module
        and f.code_presentation = p.code_presentation

    group by
        f.code_module,
        f.code_presentation,
        f.relative_time_group,
        f.time_group_order,
        p.enrolled_students

),


combined as (

    select * from presentation_summary

    union all

    select * from activity_type_summary

    union all

    select * from relative_time_summary

)


select
    analysis_level,
    code_module,
    code_presentation,
    activity_type,
    relative_time_group,
    time_group_order,

    enrolled_students,
    active_students,

    enrolled_students - active_students as inactive_students,

    round(
        100.0 * active_students
        / nullif(enrolled_students, 0),
        2
    ) as participation_rate_pct,

    total_clicks,
    total_student_active_days,

    round(
        avg_active_days_per_active_student,
        2
    ) as avg_active_days_per_active_student

from combined

order by
    code_module,
    code_presentation,

    case analysis_level
        when 'PRESENTATION' then 1
        when 'ACTIVITY_TYPE' then 2
        when 'RELATIVE_TIME' then 3
    end,

    activity_type,
    time_group_order;

    