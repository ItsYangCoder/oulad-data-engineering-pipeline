-- Enrollment summaries must preserve the full assessment-result population.
select
    sum(assessment_count) as assessment_count,
    sum(scored_assessment_count) as scored_assessment_count,
    sum(missing_score_count) as missing_score_count
from open_university.oulad_gold.fact_student_enrollment;

-- This query should return zero rows.
select *
from open_university.oulad_gold.fact_student_enrollment
where assessment_count <> scored_assessment_count + missing_score_count
   or average_score < 0
   or average_score > 100;
