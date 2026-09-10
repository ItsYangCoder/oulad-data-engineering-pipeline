-- Compares complete enrollment outcomes by module presentation.
select
    code_module,
    code_presentation,
    count(*) as enrollment_count,
    sum(case when final_result = 'Distinction' then 1 else 0 end) as distinction_count,
    sum(case when final_result = 'Pass' then 1 else 0 end) as pass_count,
    sum(case when final_result = 'Fail' then 1 else 0 end) as fail_count,
    sum(case when final_result = 'Withdrawn' then 1 else 0 end) as withdrawn_count,
    round(100.0 * sum(case when final_result = 'Withdrawn' then 1 else 0 end) / count(*), 2)
        as withdrawal_rate_pct
from open_university.oulad_gold.vw_student_outcomes
group by code_module, code_presentation
order by code_module, code_presentation;
