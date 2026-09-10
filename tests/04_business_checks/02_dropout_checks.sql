-- These current-batch values validate the documented withdrawal rule and missing timing.
select
    count(*) as enrollment_count,
    sum(case when is_withdrawn then 1 else 0 end) as withdrawn_count,
    sum(case when is_withdrawn and date_unregistration is null then 1 else 0 end)
        as withdrawn_without_date,
    sum(case when final_result = 'Fail' and date_unregistration is not null then 1 else 0 end)
        as failed_with_unregistration_date
from open_university.oulad_gold.fact_student_enrollment;

-- This query should return zero rows.
select *
from open_university.oulad_gold.fact_student_enrollment
where is_withdrawn <> (final_result = 'Withdrawn');
