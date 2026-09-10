{{ config(materialized='view', enabled=true) }}

-- One row per enrolled student in a module presentation.
-- Activity is aggregated separately before it is joined to avoid multiplying measures.

with enrollments as (
    select
        code_module,
        code_presentation,
        id_student,
        gender,
        region,
        highest_education,
        imd_band,
        age_band,
        disability,
        final_result
    from {{ source('oulad_silver', 'student_info_clean') }}
),

registration as (
    select
        code_module,
        code_presentation,
        id_student,
        date_registration,
        date_unregistration
    from {{ source('oulad_silver', 'student_registration_clean') }}
),

assessment_summary as (
    select
        code_module,
        code_presentation,
        id_student,
        count(*) as result_count,
        sum(case when score is not null then 1 else 0 end) as scored_result_count,
        avg(score) as average_score
    from {{ ref('fact_assessments') }}
    group by code_module, code_presentation, id_student
),

vle_summary as (
    select
        code_module,
        code_presentation,
        id_student,
        sum(sum_click) as total_clicks,
        count(distinct date) as active_days,
        count(distinct id_site) as resource_count
    from {{ ref('fact_vle_interactions') }}
    group by code_module, code_presentation, id_student
)

select
    e.code_module,
    e.code_presentation,
    e.id_student,
    ds.student_key,
    dc.course_key,
    dp.presentation_key,
    dd.demographics_key,
    e.final_result,
    case when e.final_result = 'Withdrawn' then true else false end as is_withdrawn,
    r.date_registration,
    r.date_unregistration,
    coalesce(a.result_count, 0) as result_count,
    coalesce(a.scored_result_count, 0) as scored_result_count,
    a.average_score,
    coalesce(v.total_clicks, 0) as total_clicks,
    coalesce(v.active_days, 0) as active_days,
    coalesce(v.resource_count, 0) as resource_count,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
from enrollments e
left join registration r
    on e.code_module = r.code_module
    and e.code_presentation = r.code_presentation
    and e.id_student = r.id_student
left join assessment_summary a
    on e.code_module = a.code_module
    and e.code_presentation = a.code_presentation
    and e.id_student = a.id_student
left join vle_summary v
    on e.code_module = v.code_module
    and e.code_presentation = v.code_presentation
    and e.id_student = v.id_student
left join {{ ref('dim_student') }} ds
    on e.id_student = ds.id_student
left join {{ ref('dim_course') }} dc
    on e.code_module = dc.code_module
left join {{ ref('dim_module_presentation') }} dp
    on e.code_module = dp.code_module
    and e.code_presentation = dp.code_presentation
left join {{ ref('dim_demographics') }} dd
    on coalesce(e.gender, '__NULL__') = coalesce(dd.gender, '__NULL__')
    and coalesce(e.region, '__NULL__') = coalesce(dd.region, '__NULL__')
    and coalesce(e.highest_education, '__NULL__') = coalesce(dd.highest_education, '__NULL__')
    and coalesce(e.imd_band, '__NULL__') = coalesce(dd.imd_band, '__NULL__')
    and coalesce(e.age_band, '__NULL__') = coalesce(dd.age_band, '__NULL__')
    and coalesce(e.disability, '__NULL__') = coalesce(dd.disability, '__NULL__')
