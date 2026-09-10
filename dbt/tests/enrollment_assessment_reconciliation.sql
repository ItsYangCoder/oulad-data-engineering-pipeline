-- Returns a row when enrollment-level assessment summaries do not reconcile to Silver.
with source_metrics as (
    select
        count(*) as assessment_count,
        count(score) as scored_assessment_count,
        count(*) - count(score) as missing_score_count
    from {{ source('oulad_silver', 'student_assessment_clean') }}
),

fact_metrics as (
    select
        sum(assessment_count) as assessment_count,
        sum(scored_assessment_count) as scored_assessment_count,
        sum(missing_score_count) as missing_score_count
    from {{ ref('fact_student_enrollment') }}
)

select
    s.assessment_count as source_assessment_count,
    f.assessment_count as fact_assessment_count,
    s.scored_assessment_count as source_scored_count,
    f.scored_assessment_count as fact_scored_count,
    s.missing_score_count as source_missing_count,
    f.missing_score_count as fact_missing_count
from source_metrics s
cross join fact_metrics f
where s.assessment_count <> f.assessment_count
   or s.scored_assessment_count <> f.scored_assessment_count
   or s.missing_score_count <> f.missing_score_count
