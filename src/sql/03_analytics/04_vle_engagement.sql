-- Shows how recorded student activity changes by relative course week.
select
    v.code_module,
    v.code_presentation,
    d.relative_week,
    count(distinct v.id_student) as active_students,
    count(distinct concat_ws('||', cast(v.id_student as string), cast(v.relative_day as string)))
        as active_student_days,
    sum(v.sum_click) as total_clicks
from open_university.oulad_gold.fact_vle_interactions v
inner join open_university.oulad_gold.dim_date d
    on v.date_key = d.date_key
group by v.code_module, v.code_presentation, d.relative_week
order by v.code_module, v.code_presentation, d.relative_week;
