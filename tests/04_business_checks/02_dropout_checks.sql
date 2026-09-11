-- Baseline withdrawal counts must reconcile to the current source batch.
with baseline as (
    select
        count(*) as enrollment_count,
        sum(case when final_result = 'Withdrawn' then 1 else 0 end)
            as withdrawn_count
    from open_university.oulad_gold.fact_student_enrollment
)
select *
from baseline
where enrollment_count <> 32593
   or withdrawn_count <> 10156;


-- Known and unknown withdrawal timing must cover the full Withdrawn population.
with timing as (
    select
        sum(
            case
                when final_result = 'Withdrawn'
                    and date_unregistration is not null
                then 1
                else 0
            end
        ) as known_timing_count,
        sum(
            case
                when final_result = 'Withdrawn'
                    and date_unregistration is null
                then 1
                else 0
            end
        ) as unknown_timing_count,
        sum(
            case
                when final_result = 'Withdrawn'
                then 1
                else 0
            end
        ) as withdrawn_count
    from open_university.oulad_gold.fact_student_enrollment
)
select *
from timing
where known_timing_count + unknown_timing_count <> withdrawn_count
   or known_timing_count <> 10063
   or unknown_timing_count <> 93
   or withdrawn_count <> 10156;


-- Records with an unregistration date must not automatically be classified as dropout.
with exceptions as (
    select
        sum(
            case
                when final_result = 'Fail'
                    and date_unregistration is not null
                then 1
                else 0
            end
        ) as fail_with_unregistration_date
    from open_university.oulad_gold.fact_student_enrollment
)
select *
from exceptions
where fail_with_unregistration_date <> 9;


-- is_withdrawn must remain consistent with the documented dropout definition.
select *
from open_university.oulad_gold.fact_student_enrollment
where is_withdrawn <> (final_result = 'Withdrawn');