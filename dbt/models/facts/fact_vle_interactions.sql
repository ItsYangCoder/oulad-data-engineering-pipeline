{{ config(materialized='table') }}

-- Gold fact table containing daily VLE activity for each student.
-- The grain is one row per student, resource, and day within a module presentation.
-- The Silver layer already stores daily sum_click values, so no additional aggregation is applied here.

with daily_interactions as (

    -- Source of student click activity from the Silver layer.
    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        sum_click
    from {{ source('oulad_silver', 'student_vle_clean') }}

),

vle_resources as (

    -- Reference details for each VLE resource accessed by a student.
    -- week_from and week_to may be NULL because these fields are optional.
    select
        code_module,
        code_presentation,
        id_site,
        activity_type,
        week_from,
        week_to
    from {{ source('oulad_silver', 'vle_clean') }}

),

student_info as (

    -- Enrollment details used to identify the student's profile
    -- within the correct module and presentation.
    select
        code_module,
        code_presentation,
        id_student,
        gender,
        region,
        highest_education,
        imd_band,
        age_band,
        disability
    from {{ source('oulad_silver', 'student_info_clean') }}

),

student_dimension as (

    -- dim_student contains one row per student, so id_student is used as the join key.
    select
        student_key,
        id_student
    from {{ ref('dim_student') }}

),

course_dimension as (

    -- Retrieves the course key using the module code.
    select
        course_key,
        code_module
    from {{ ref('dim_course') }}

),

presentation_dimension as (

    -- Uses both module and presentation codes to retrieve the correct presentation key.
    select
        presentation_key,
        code_module,
        code_presentation
    from {{ ref('dim_module_presentation') }}

),

demographics_dimension as (

    -- dim_demographics stores profile attributes rather than student IDs.
    -- The demographic values are therefore used to retrieve the corresponding key.
    select
        demographics_key,
        gender,
        region,
        highest_education,
        imd_band,
        age_band,
        disability
    from {{ ref('dim_demographics') }}

),

date_dimension as (

    -- OULAD date values represent relative days rather than calendar dates.
    select
        date_key,
        relative_day
    from {{ ref('dim_date') }}

)

select
    -- Foreign keys linking the fact record to the dimension tables.
    ds.student_key,
    dc.course_key,
    dp.presentation_key,
    dd.demographics_key,
    dt.date_key,

    -- Source identifiers retained for reconciliation with the Silver layer.
    di.code_module,
    di.code_presentation,
    di.id_student,
    di.id_site,
    di.date,

    -- Daily click count provided by the Silver layer.
    di.sum_click,

    -- Additional attributes describing the VLE resource.
    vr.activity_type,
    vr.week_from as resource_week_from,
    vr.week_to as resource_week_to,

    -- Audit fields recording when the Gold table was created or refreshed.
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date

from daily_interactions di

-- Matches the complete resource key to prevent activity from being linked to the wrong module.
left join vle_resources vr
    on di.code_module = vr.code_module
    and di.code_presentation = vr.code_presentation
    and di.id_site = vr.id_site

-- Matches the enrollment record to identify the correct demographic profile.
left join student_info si
    on di.code_module = si.code_module
    and di.code_presentation = si.code_presentation
    and di.id_student = si.id_student

-- Uses student ID as the natural key for dim_student.
left join student_dimension ds
    on di.id_student = ds.id_student

left join course_dimension dc
    on di.code_module = dc.code_module

left join presentation_dimension dp
    on di.code_module = dp.code_module
    and di.code_presentation = dp.code_presentation

-- COALESCE allows NULL demographic values to match consistently.
left join demographics_dimension dd
    on coalesce(si.gender, '__NULL__') = coalesce(dd.gender, '__NULL__')
    and coalesce(si.region, '__NULL__') = coalesce(dd.region, '__NULL__')
    and coalesce(si.highest_education, '__NULL__') = coalesce(dd.highest_education, '__NULL__')
    and coalesce(si.imd_band, '__NULL__') = coalesce(dd.imd_band, '__NULL__')
    and coalesce(si.age_band, '__NULL__') = coalesce(dd.age_band, '__NULL__')
    and coalesce(si.disability, '__NULL__') = coalesce(dd.disability, '__NULL__')

left join date_dimension dt
    on di.date = dt.relative_day
