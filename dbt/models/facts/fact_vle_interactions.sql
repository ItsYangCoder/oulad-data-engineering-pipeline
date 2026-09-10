{{ config(materialized='table') }}

-- Grain: one student, VLE resource and relative day in one module presentation.
-- Silver has already combined repeated source rows at this daily grain.

with daily_interactions as (
    select code_module, code_presentation, id_student, id_site, date, sum_click
    from {{ source('oulad_silver', 'student_vle_clean') }}
),

resources as (
    select code_module, code_presentation, id_site, activity_type, week_from, week_to
    from {{ source('oulad_silver', 'vle_clean') }}
),

enrollment_profiles as (
    select
        code_module, code_presentation, id_student, gender, region,
        highest_education, imd_band, age_band, disability
    from {{ source('oulad_silver', 'student_info_clean') }}
)

select
    md5(concat_ws(
        '||', di.code_module, di.code_presentation,
        cast(di.id_student as string), cast(di.id_site as string), cast(di.date as string)
    )) as vle_interaction_key,
    ds.student_key,
    dc.course_key,
    dp.presentation_key,
    dd.demographics_key,
    dt.date_key,
    di.id_student,
    di.code_module,
    di.code_presentation,
    di.id_site,
    di.date as relative_day,
    r.activity_type,
    r.week_from as resource_week_from,
    r.week_to as resource_week_to,
    di.sum_click,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
from daily_interactions di
inner join resources r
    on di.code_module = r.code_module
    and di.code_presentation = r.code_presentation
    and di.id_site = r.id_site
inner join enrollment_profiles ep
    on di.code_module = ep.code_module
    and di.code_presentation = ep.code_presentation
    and di.id_student = ep.id_student
inner join {{ ref('dim_student') }} ds
    on di.id_student = ds.id_student
inner join {{ ref('dim_course') }} dc
    on di.code_module = dc.code_module
inner join {{ ref('dim_module_presentation') }} dp
    on di.code_module = dp.code_module
    and di.code_presentation = dp.code_presentation
inner join {{ ref('dim_demographics') }} dd
    on coalesce(ep.gender, '__NULL__') = coalesce(dd.gender, '__NULL__')
    and coalesce(ep.region, '__NULL__') = coalesce(dd.region, '__NULL__')
    and coalesce(ep.highest_education, '__NULL__') = coalesce(dd.highest_education, '__NULL__')
    and coalesce(ep.imd_band, '__NULL__') = coalesce(dd.imd_band, '__NULL__')
    and coalesce(ep.age_band, '__NULL__') = coalesce(dd.age_band, '__NULL__')
    and coalesce(ep.disability, '__NULL__') = coalesce(dd.disability, '__NULL__')
inner join {{ ref('dim_date') }} dt
    on di.date = dt.relative_day
