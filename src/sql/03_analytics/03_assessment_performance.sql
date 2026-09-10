-- Relates enrollment-level VLE engagement to assessment performance.
-- AVG ignores enrollments without a scored assessment; the counts show that coverage.
select
    code_module,
    code_presentation,
    count(*) as enrollment_count,
    count(average_score) as scored_enrollment_count,
    round(avg(average_score), 2) as average_score,
    round(avg(total_clicks), 2) as average_clicks,
    round(corr(cast(total_clicks as double), cast(average_score as double)), 4)
        as clicks_score_correlation
from open_university.oulad_gold.vw_student_outcomes
group by code_module, code_presentation
order by code_module, code_presentation;
