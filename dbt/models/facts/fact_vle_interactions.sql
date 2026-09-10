{{ config(materialized='table') }}

-- Gumagawa ito ng Gold fact table para sa daily VLE activity ng bawat student.
-- Isang row ay isang student, resource, at araw sa isang module presentation.
-- Daily total na ang sum_click sa Silver kaya hindi na ito dapat i-SUM ulit dito.

with daily_interactions as (

    -- Ito ang main source ng student clicks.
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

    -- Kinukuha nito ang details ng VLE resource na binuksan ng student.
    -- Puwedeng NULL ang week_from at week_to dahil optional ang mga field na iyon.
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

    -- Kailangan ang enrollment record para malaman ang demographics
    -- ng student sa tamang module at presentation.
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

    -- Ang dim_student ay one row per student kaya id_student ang ginagamit na match.
    select
        student_key,
        id_student
    from {{ ref('dim_student') }}

),

course_dimension as (

    -- Kinukuha ang course key gamit ang module code.
    select
        course_key,
        code_module
    from {{ ref('dim_course') }}

),

presentation_dimension as (

    -- Magkasama ang module at presentation code para makuha ang tamang presentation key.
    select
        presentation_key,
        code_module,
        code_presentation
    from {{ ref('dim_module_presentation') }}

),

demographics_dimension as (

    -- Profile fields ang laman ng dim_demographics, hindi student ID.
    -- Kaya ang demographic values mismo ang gagamitin para mahanap ang key.
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

    -- Relative day ang date ng OULAD at hindi totoong calendar date.
    select
        date_key,
        relative_day
    from {{ ref('dim_date') }}

)

select
    -- Mga key na nagkokonekta sa fact papunta sa dimensions.
    ds.student_key,
    dc.course_key,
    dp.presentation_key,
    dd.demographics_key,
    dt.date_key,

    -- Original columns para madaling ma-check laban sa Silver data.
    di.code_module,
    di.code_presentation,
    di.id_student,
    di.id_site,
    di.date,

    -- Daily clicks na galing mismo sa Silver.
    di.sum_click,

    -- Extra details tungkol sa resource.
    vr.activity_type,
    vr.week_from as resource_week_from,
    vr.week_to as resource_week_to,

    -- Record kung kailan ginawa o ni-refresh ang Gold table.
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date

from daily_interactions di

-- Kumpletong resource key ang gamit para hindi mapunta sa maling module ang activity.
left join vle_resources vr
    on di.code_module = vr.code_module
    and di.code_presentation = vr.code_presentation
    and di.id_site = vr.id_site

-- Ang enrollment match ang nagbibigay ng tamang demographic profile.
left join student_info si
    on di.code_module = si.code_module
    and di.code_presentation = si.code_presentation
    and di.id_student = si.id_student

-- Student ID lang ang natural key ng dim_student.
left join student_dimension ds
    on di.id_student = ds.id_student

left join course_dimension dc
    on di.code_module = dc.code_module

left join presentation_dimension dp
    on di.code_module = dp.code_module
    and di.code_presentation = dp.code_presentation

-- COALESCE ang gamit para mag-match din nang maayos ang NULL demographic values.
left join demographics_dimension dd
    on coalesce(si.gender, '__NULL__') = coalesce(dd.gender, '__NULL__')
    and coalesce(si.region, '__NULL__') = coalesce(dd.region, '__NULL__')
    and coalesce(si.highest_education, '__NULL__') = coalesce(dd.highest_education, '__NULL__')
    and coalesce(si.imd_band, '__NULL__') = coalesce(dd.imd_band, '__NULL__')
    and coalesce(si.age_band, '__NULL__') = coalesce(dd.age_band, '__NULL__')
    and coalesce(si.disability, '__NULL__') = coalesce(dd.disability, '__NULL__')

left join date_dimension dt
    on di.date = dt.relative_day
