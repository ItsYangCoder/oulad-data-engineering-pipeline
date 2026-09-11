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
--
-- Purpose:
-- Summarize recorded VLE engagement by module presentation and relative time.
--
-- Definitions:
-- - Active student = student with at least one positive recorded VLE click.
-- - Active day = one distinct relative interaction day with positive clicks.
-- - Multiple VLE resources used on the same day still count as one active day.
-- - Clicks represent recorded VLE interactions only.
-- - Clicks are NOT study duration, sessions, attention, or learning quality.
-- - Enrollment denominators include zero-activity students through
--   vw_student_outcomes.
--
-- Output grain:
-- one row per
-- code_module + code_presentation + relative_time_group
-- =============================================================================


with outcomes as (

    -- Full enrollment population.
    select
        code_module,
        code_presentation,
        id_student
    from open_university.oulad_gold.vw_student_outcomes

),


vle_fact as (

    -- Fact grain:
    -- module + presentation + student + resource + relative day
    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day,
        activity_type,
        sum_click
    from open_university.oulad_gold.fact_vle_interactions

),


-- =============================================================================
-- STUDENT-ENROLLMENT ENGAGEMENT
--
-- Aggregate across all resources first.
--
-- Grain:
-- code_module + code_presentation + id_student
-- =============================================================================

student_engagement as (

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


-- =============================================================================
-- FULL ENROLLMENT POPULATION
--
-- Students without VLE records remain present with zero engagement.
-- =============================================================================

enrollment_population as (

    select
        o.code_module,
        o.code_presentation,
        o.id_student,

        coalesce(e.total_clicks, 0) as total_clicks,
        coalesce(e.active_days, 0) as active_days

    from outcomes o

    left join student_engagement e
        on  o.code_module = e.code_module
        and o.code_presentation = e.code_presentation
        and o.id_student = e.id_student

),


-- =============================================================================
-- PRESENTATION DENOMINATOR
-- =============================================================================

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


-- =============================================================================
-- RELATIVE-TIME CLASSIFICATION
--
-- Negative day  = Before presentation
-- Day 0         = Presentation start
-- Days 1-7      = Week 1
-- Days 8-14     = Week 2
-- etc.
-- =============================================================================

vle_with_time_group as (

    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day,
        activity_type,
        sum_click,

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


-- =============================================================================
-- RELATIVE-TIME ENGAGEMENT SUMMARY
--
-- Grain:
-- code_module + code_presentation + relative_time_group
-- =============================================================================

time_summary as (

    select
        v.code_module,
        v.code_presentation,
        v.relative_time_group,
        v.time_group_order,

        p.enrolled_students,

        count(
            distinct case
                when v.sum_click > 0 then v.id_student
            end
        ) as active_students,

        count(
            distinct case
                when v.sum_click > 0
                then concat_ws(
                    '||',
                    cast(v.id_student as string),
                    cast(v.relative_day as string)
                )
            end
        ) as active_student_days,

        sum(v.sum_click) as total_clicks

    from vle_with_time_group v

    inner join presentation_population p
        on  v.code_module = p.code_module
        and v.code_presentation = p.code_presentation

    group by
        v.code_module,
        v.code_presentation,
        v.relative_time_group,
        v.time_group_order,
        p.enrolled_students

)


select
    code_module,
    code_presentation,
    relative_time_group,
    time_group_order,

    enrolled_students,
    active_students,

    enrolled_students - active_students
        as inactive_students,

    round(
        100.0 * active_students
        / nullif(enrolled_students, 0),
        2
    ) as participation_rate_pct,

    active_student_days,
    total_clicks

from time_summary

order by
    code_module,
    code_presentation,
    time_group_order;