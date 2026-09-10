-- Returns a row when outcome counts do not equal the complete enrollment population.
with totals as (
    select
        count(*) as enrollment_count,
        sum(case when final_result in ('Distinction', 'Pass', 'Fail', 'Withdrawn') then 1 else 0 end)
            as classified_count
    from open_university.oulad_gold.vw_student_outcomes
)
select * from totals
where enrollment_count <> classified_count
   or enrollment_count <> 32593;
