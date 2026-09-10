{{ config(materialized='view') }}

-- Grain: one student enrollment in one module presentation.
-- VLE activity is aggregated before the join so enrollment measures are not multiplied.

with vle_summary as (
    select
        code_module,
        code_presentation,
        id_student,
        sum(sum_click) as total_clicks,
        count(distinct relative_day) as active_days,
        count(distinct id_site) as resource_count
    from {{ ref('fact_vle_interactions') }}
    group by code_module, code_presentation, id_student
)

select
    e.enrollment_key,
    e.student_key,
    e.course_key,
    e.presentation_key,
    e.demographics_key,
    e.registration_date_key,
    e.unregistration_date_key,
    e.id_student,
    e.code_module,
    e.code_presentation,
    e.date_registration,
    e.date_unregistration,
    e.final_result,
    e.is_withdrawn,
    e.studied_credits,
    e.num_of_prev_attempts,
    e.assessment_count,
    e.scored_assessment_count,
    e.missing_score_count,
    e.average_score,
    coalesce(v.total_clicks, 0) as total_clicks,
    coalesce(v.active_days, 0) as active_days,
    coalesce(v.resource_count, 0) as resource_count
from {{ ref('fact_student_enrollment') }} e
left join vle_summary v
    on e.code_module = v.code_module
    and e.code_presentation = v.code_presentation
    and e.id_student = v.id_student
