
-- File: fact_vle_interactions.sql
-- Suggested branch: feature/build-vle-mart
-- Purpose: Store daily resource engagement with reporting keys and unchanged click totals.
-- Status: Implementation pending. Replace this guide with the finished code.
-- Input: Silver student_vle_clean, vle_clean and student_info_clean; the five required dimensions via
--    ref().
-- Output: open_university.oulad_gold.fact_vle_interactions
-- Grain / business key: One row per (code_module, code_presentation, id_student, id_site, date).
--
-- What to put in this file:
-- 1. Write a dbt SELECT with named CTEs, source() for Silver inputs and ref() for other Gold models;
--    dbt manages the target relation.
-- 2. Start from student_vle_clean, whose repeated source keys have already been aggregated.
-- 3. Keep the complete five-column business key and sum_click.
-- 4. Resolve student_key, course_key, presentation_key, demographics_key and date_key (interaction
--    day).
-- 5. Join resources on code_module + code_presentation + id_site; join student_info on code_module +
--    code_presentation + id_student.
-- 6. Carry activity_type and optional resource availability weeks directly in the fact; no separate
--    resource dimension is required.
-- 7. Do not sum already aggregated rows again because a join produced duplicates. Check parent
--    uniqueness and retain NULL optional resource attributes.
-- 8. Use consistent, repeatable dimension keys and mart_load_timestamp/mart_load_date audit fields; do
--    not regenerate keys in a different order on reruns.
-- 9. Remove enabled=false only when this model and its dependencies are implemented; add
--    documentation/tests in the adjacent YAML.
--
-- Validate with facts.yml, dbt/tests/fact_vle_interactions_grain.sql and
--    dbt/tests/vle_click_reconciliation.sql.
--
-- Done when: 8,459,320 current-batch rows; unique daily keys; Silver-to-Gold click totals match
--    globally and per presentation.
-- Read: docs/pipeline_plan.md and docs/assumptions.md.


{{ config(
    materialized = 'table'
) }}

-- =============================================================================
-- MODEL: fact_vle_interactions
-- =============================================================================
-- Purpose:
--   Store daily student engagement with VLE resources and connect each
--   interaction to the appropriate reporting dimensions.
--
-- Target:
--   open_university.oulad_gold.fact_vle_interactions
--
-- Grain:
--   One row per:
--     code_module
--     + code_presentation
--     + id_student
--     + id_site
--     + date
--
-- Measure:
--   sum_click
--
-- Important:
--   student_vle_clean already contains daily aggregated interactions.
--   This model must not aggregate sum_click again.
--
-- Join types:
--   LEFT JOIN is used so interactions are retained even when optional resource
--   attributes or dimension records are missing.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Daily VLE interactions
-- -----------------------------------------------------------------------------
-- This is the base of the fact table.
-- Its five-column business key defines the required fact-table grain.
-- sum_click is already aggregated in the Silver layer.
with daily_interactions as (

    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        sum_click

    from {{ source('oulad_silver', 'student_vle_clean') }}

),


-- -----------------------------------------------------------------------------
-- 2. VLE resource details
-- -----------------------------------------------------------------------------
-- Adds descriptive information about the resource used by the student.
--
-- Expected resource key:
--   code_module + code_presentation + id_site
--
-- week_from and week_to are optional attributes and may remain NULL.
vle_resources as (

    select
        code_module,
        code_presentation,
        id_site,
        activity_type,
        week_from,
        week_to

    from {{ source('oulad_silver', 'vle_clean') }}

),


-- -----------------------------------------------------------------------------
-- 3. Student enrolment/presentation context
-- -----------------------------------------------------------------------------
-- Confirms that the student belongs to the relevant module presentation.
--
-- Expected student-information key:
--   code_module + code_presentation + id_student
student_info as (

    select
        code_module,
        code_presentation,
        id_student

    from {{ source('oulad_silver', 'student_info_clean') }}

),


-- -----------------------------------------------------------------------------
-- 4. Student dimension
-- -----------------------------------------------------------------------------
-- Retrieves the student surrogate key.
-- The natural-key columns are retained here only for the dimension lookup.
dim_student as (

    select
        student_key,
        code_module,
        code_presentation,
        id_student

    from {{ ref('dim_student') }}

),


-- -----------------------------------------------------------------------------
-- 5. Course dimension
-- -----------------------------------------------------------------------------
-- Retrieves the course surrogate key using code_module.
-- dim_course contains one row per distinct module.
dim_course as (

    select
        course_key,
        code_module

    from {{ ref('dim_course') }}

),


-- -----------------------------------------------------------------------------
-- 6. Module-presentation dimension
-- -----------------------------------------------------------------------------
-- Retrieves the presentation surrogate key.
--
-- Expected presentation key:
--   code_module + code_presentation
dim_module_presentation as (

    select
        presentation_key,
        code_module,
        code_presentation

    from {{ ref('dim_module_presentation') }}

),


-- -----------------------------------------------------------------------------
-- 7. Demographics dimension
-- -----------------------------------------------------------------------------
-- Retrieves the demographic surrogate key associated with the student's
-- module-presentation record.
dim_demographics as (

    select
        demographics_key,
        code_module,
        code_presentation,
        id_student

    from {{ ref('dim_demographics') }}

),


-- -----------------------------------------------------------------------------
-- 8. Relative-date dimension
-- -----------------------------------------------------------------------------
-- OULAD uses relative course days instead of calendar dates.
--
-- Examples:
--   relative_day = -5 means five days before the presentation starts.
--   relative_day = 10 means ten days after the presentation starts.
--
-- student_vle_clean.date therefore joins to dim_date.relative_day.
dim_date as (

    select
        date_key,
        relative_day

    from {{ ref('dim_date') }}

)


-- =============================================================================
-- FINAL FACT TABLE
-- =============================================================================
select
    -- -------------------------------------------------------------------------
    -- Dimension surrogate keys
    -- -------------------------------------------------------------------------
    ds.student_key,
    dc.course_key,
    dmp.presentation_key,
    ddg.demographics_key,
    ddt.date_key,

    -- -------------------------------------------------------------------------
    -- Original business key
    -- -------------------------------------------------------------------------
    -- These columns are retained for traceability, uniqueness testing and
    -- reconciliation with the Silver layer.
    di.code_module,
    di.code_presentation,
    di.id_student,
    di.id_site,
    di.date,

    -- -------------------------------------------------------------------------
    -- Fact measure
    -- -------------------------------------------------------------------------
    -- This value is already aggregated to the required daily grain in Silver.
    -- Do not wrap it in SUM() or add a GROUP BY in this model.
    di.sum_click,

    -- -------------------------------------------------------------------------
    -- Resource context
    -- -------------------------------------------------------------------------
    -- These attributes are stored directly in the fact because the design does
    -- not require a separate VLE-resource dimension.
    vr.activity_type,
    vr.week_from as resource_week_from,
    vr.week_to as resource_week_to,

    -- -------------------------------------------------------------------------
    -- Audit metadata
    -- -------------------------------------------------------------------------
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date

from daily_interactions as di


-- Add the resource description using the complete resource business key.
-- LEFT JOIN preserves the interaction when optional VLE context is unavailable.
left join vle_resources as vr
    on  di.code_module = vr.code_module
    and di.code_presentation = vr.code_presentation
    and di.id_site = vr.id_site


-- Match the interaction to the student's module-presentation record.
left join student_info as si
    on  di.code_module = si.code_module
    and di.code_presentation = si.code_presentation
    and di.id_student = si.id_student


-- Retrieve the surrogate student key from the matching student record.
left join dim_student as ds
    on  si.code_module = ds.code_module
    and si.code_presentation = ds.code_presentation
    and si.id_student = ds.id_student


-- Retrieve the course key.
-- code_module is unique in dim_course.
left join dim_course as dc
    on di.code_module = dc.code_module


-- Retrieve the module-presentation key.
left join dim_module_presentation as dmp
    on  di.code_module = dmp.code_module
    and di.code_presentation = dmp.code_presentation


-- Retrieve the demographic key for the student in this presentation.
left join dim_demographics as ddg
    on  si.code_module = ddg.code_module
    and si.code_presentation = ddg.code_presentation
    and si.id_student = ddg.id_student


-- Match the VLE interaction's relative day to the relative-date dimension.
left join dim_date as ddt
    on di.date = ddt.relative_day