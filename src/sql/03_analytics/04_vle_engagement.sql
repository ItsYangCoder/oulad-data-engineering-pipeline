-- Active students/days require positive clicks; all enrollments form participation denominators.
-- Time groups: negative days, day 0, then days 1-7 as week 1. Categories are not additive for students.
with outcomes as (
    select
        code_module,
        code_presentation,
        id_student
    from open_university.oulad_gold.vw_student_outcomes
),
vle_fact as (
    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day,
        activity_type,
        sum_click
    from open_university.oulad_gold.fact_vle_interactions
),
enrollment_engagement as (
    select
        code_module,
        code_presentation,
        id_student,
        sum(sum_click) as total_clicks,
        count(
            distinct case
                when sum_click > 0 then relative_day
            end
        ) as active_days
    from vle_fact
    group by
        code_module,
        code_presentation,
        id_student
),
enrollment_population as (
    select
        o.code_module,
        o.code_presentation,
        o.id_student,
        coalesce(e.total_clicks, 0) as total_clicks,
        coalesce(e.active_days, 0) as active_days
    from outcomes o
    left join enrollment_engagement e
        on  o.code_module = e.code_module
        and o.code_presentation = e.code_presentation
        and o.id_student = e.id_student
),
presentation_population as (
    select
        code_module,
        code_presentation,
        count(*) as enrolled_students
    from outcomes
    group by
        code_module,
        code_presentation
),
presentation_summary as (
    select
        'PRESENTATION' as analysis_level,
        code_module,
        code_presentation,
        cast(null as string) as activity_type,
        cast(null as string) as relative_time_group,
        cast(null as int) as time_group_order,
        count(*) as enrolled_students,
        sum(
            case
                when active_days > 0 then 1
                else 0
            end
        ) as active_students,
        sum(total_clicks) as total_clicks,
        sum(active_days) as total_student_active_days,
        avg(
            case
                when active_days > 0
                    then cast(active_days as double)
            end
        ) as avg_active_days_per_active_student
    from enrollment_population
    group by
        code_module,
        code_presentation
),
activity_type_summary as (
    select
        'ACTIVITY_TYPE' as analysis_level,
        f.code_module,
        f.code_presentation,
        f.activity_type as activity_type,
        cast(null as string) as relative_time_group,
        cast(null as int) as time_group_order,
        p.enrolled_students,
        count(
            distinct case
                when f.sum_click > 0 then f.id_student
            end
        ) as active_students,
        sum(f.sum_click) as total_clicks,
        count(
            distinct case
                when f.sum_click > 0
                    then concat(
                        cast(f.id_student as string),
                        '||',
                        cast(f.relative_day as string)
                    )
            end
        ) as total_student_active_days,
        cast(null as double) as avg_active_days_per_active_student
    from vle_fact f
    inner join presentation_population p
        on  f.code_module = p.code_module
        and f.code_presentation = p.code_presentation
    group by
        f.code_module,
        f.code_presentation,
        f.activity_type,
        p.enrolled_students
),
vle_with_time_group as (
    select
        *,
        case
            when relative_day < 0
                then 'Before presentation'
            when relative_day = 0
                then 'Day 0'
            else concat(
                'Week ',
                cast(ceil(relative_day / 7.0) as int)
            )
        end as relative_time_group,
        case
            when relative_day < 0 then 0
            when relative_day = 0 then 1
            else cast(ceil(relative_day / 7.0) as int) + 1
        end as time_group_order
    from vle_fact
),
relative_time_summary as (
    select
        'RELATIVE_TIME' as analysis_level,
        f.code_module,
        f.code_presentation,
        cast(null as string) as activity_type,
        f.relative_time_group,
        f.time_group_order,
        p.enrolled_students,
        count(
            distinct case
                when f.sum_click > 0 then f.id_student
            end
        ) as active_students,
        sum(f.sum_click) as total_clicks,
        count(
            distinct case
                when f.sum_click > 0
                    then concat(
                        cast(f.id_student as string),
                        '||',
                        cast(f.relative_day as string)
                    )
            end
        ) as total_student_active_days,
        cast(null as double) as avg_active_days_per_active_student
    from vle_with_time_group f
    inner join presentation_population p
        on  f.code_module = p.code_module
        and f.code_presentation = p.code_presentation
    group by
        f.code_module,
        f.code_presentation,
        f.relative_time_group,
        f.time_group_order,
        p.enrolled_students
),
combined as (
    select * from presentation_summary
    union all
    select * from activity_type_summary
    union all
    select * from relative_time_summary
)
select
    analysis_level,
    code_module,
    code_presentation,
    activity_type,
    relative_time_group,
    time_group_order,
    enrolled_students,
    active_students,
    enrolled_students - active_students as inactive_students,
    round(
        100.0 * active_students
        / nullif(enrolled_students, 0),
        2
    ) as participation_rate_pct,
    total_clicks,
    total_student_active_days,
    round(
        avg_active_days_per_active_student,
        2
    ) as avg_active_days_per_active_student
from combined
order by
    code_module,
    code_presentation,
    case analysis_level
        when 'PRESENTATION' then 1
        when 'ACTIVITY_TYPE' then 2
        when 'RELATIVE_TIME' then 3
    end,
    activity_type,
    time_group_order;
