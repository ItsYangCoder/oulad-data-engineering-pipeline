{{ config(enabled=true) }}

with assessment_context as (
    select
        id_assessment,
        code_module,
        code_presentation
    from {{ source('oulad_silver', 'assessment_clean') }}
),

source_results as (
    select
        a.code_module,
        a.code_presentation,
        r.id_assessment,
        r.id_student,
        count(*) as result_count,
        count(r.score) as scored_count,
        count(*) - count(r.score) as null_score_count,
        coalesce(sum(r.score), 0) as score_sum
    from {{ source('oulad_silver', 'student_assessment_clean') }} r
    left join assessment_context a
        on r.id_assessment = a.id_assessment
    group by
        a.code_module,
        a.code_presentation,
        r.id_assessment,
        r.id_student
),

gold_results as (
    select
        code_module,
        code_presentation,
        id_assessment,
        id_student,
        count(*) as result_count,
        count(score) as scored_count,
        count(*) - count(score) as null_score_count,
        coalesce(sum(score), 0) as score_sum
    from {{ ref('fact_assessments') }}
    group by
        code_module,
        code_presentation,
        id_assessment,
        id_student
),

key_reconciliation as (
    select
        coalesce(s.code_module, g.code_module) as code_module,
        coalesce(s.code_presentation, g.code_presentation) as code_presentation,
        coalesce(s.id_assessment, g.id_assessment) as id_assessment,
        coalesce(s.id_student, g.id_student) as id_student,
        coalesce(s.result_count, 0) as source_result_count,
        coalesce(g.result_count, 0) as gold_result_count,
        coalesce(s.scored_count, 0) as source_scored_count,
        coalesce(g.scored_count, 0) as gold_scored_count,
        coalesce(s.null_score_count, 0) as source_null_score_count,
        coalesce(g.null_score_count, 0) as gold_null_score_count,
        coalesce(s.score_sum, 0) as source_score_sum,
        coalesce(g.score_sum, 0) as gold_score_sum
    from source_results s
    full outer join gold_results g
        on s.code_module = g.code_module
        and s.code_presentation = g.code_presentation
        and s.id_assessment = g.id_assessment
        and s.id_student = g.id_student
),

failures as (
    select *
    from key_reconciliation
    where source_result_count <> gold_result_count
       or source_scored_count <> gold_scored_count
       or source_null_score_count <> gold_null_score_count
       or abs(source_score_sum - gold_score_sum) > 0.01
)

select *
from failures
