{{ config(materialized='table') }}

-- Grain: one student enrollment in one module presentation.
-- Assessment results are summarized to this grain before they are joined.

with enrollments as (
    select
        code_module, code_presentation, id_student, gender, region,
        highest_education, imd_band, age_band, disability,
        num_of_prev_attempts, studied_credits, final_result
    from {{ source('oulad_silver', 'student_info_clean') }}
),

registrations as (
    select code_module, code_presentation, id_student,
           date_registration, date_unregistration
    from {{ source('oulad_silver', 'student_registration_clean') }}
),

assessment_summary as (
    select
        a.code_module,
        a.code_presentation,
        sa.id_student,
        count(*) as assessment_count,
        count(sa.score) as scored_assessment_count,
        count(*) - count(sa.score) as missing_score_count,
        avg(sa.score) as average_score
    from {{ source('oulad_silver', 'student_assessment_clean') }} sa
    inner join {{ source('oulad_silver', 'assessment_clean') }} a
        on sa.id_assessment = a.id_assessment
    group by a.code_module, a.code_presentation, sa.id_student
),

joined as (
    select
        e.*,
        r.date_registration,
        r.date_unregistration,
        coalesce(a.assessment_count, 0) as assessment_count,
        coalesce(a.scored_assessment_count, 0) as scored_assessment_count,
        coalesce(a.missing_score_count, 0) as missing_score_count,
        a.average_score
    from enrollments e
    left join registrations r
        on e.code_module = r.code_module
        and e.code_presentation = r.code_presentation
        and e.id_student = r.id_student
    left join assessment_summary a
        on e.code_module = a.code_module
        and e.code_presentation = a.code_presentation
        and e.id_student = a.id_student
)

select
    md5(concat_ws('||', j.code_module, j.code_presentation, cast(j.id_student as string))) as enrollment_key,
    ds.student_key,
    dc.course_key,
    dp.presentation_key,
    dd.demographics_key,
    coalesce(dr.date_key, 'UNKNOWN') as registration_date_key,
    coalesce(du.date_key, 'UNKNOWN') as unregistration_date_key,
    j.id_student,
    j.code_module,
    j.code_presentation,
    j.date_registration,
    j.date_unregistration,
    j.final_result,
    case when j.final_result = 'Withdrawn' then true else false end as is_withdrawn,
    j.studied_credits,
    j.num_of_prev_attempts,
    j.assessment_count,
    j.scored_assessment_count,
    j.missing_score_count,
    cast(j.average_score as decimal(5, 2)) as average_score,
    current_timestamp() as mart_load_timestamp,
    current_date() as mart_load_date
from joined j
inner join {{ ref('dim_student') }} ds
    on j.id_student = ds.id_student
inner join {{ ref('dim_course') }} dc
    on j.code_module = dc.code_module
inner join {{ ref('dim_module_presentation') }} dp
    on j.code_module = dp.code_module
    and j.code_presentation = dp.code_presentation
inner join {{ ref('dim_demographics') }} dd
    on j.gender = dd.gender
    and j.region = dd.region
    and j.highest_education = dd.highest_education
    and j.imd_band = dd.imd_band
    and j.age_band = dd.age_band
    and j.disability = dd.disability
left join {{ ref('dim_date') }} dr
    on j.date_registration = dr.relative_day
left join {{ ref('dim_date') }} du
    on j.date_unregistration = du.relative_day
