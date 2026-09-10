-- Compares Silver and Gold at the daily key, presentation and dataset levels.
-- The test returns rows when a key, row count or click total differs.

with silver_daily as (

    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        count(*) as row_count,
        sum(sum_click) as click_total
    from {{ source('oulad_silver', 'student_vle_clean') }}
    group by
        code_module,
        code_presentation,
        id_student,
        id_site,
        date

),

gold_daily as (

    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day as date,
        count(*) as row_count,
        sum(sum_click) as click_total
    from {{ ref('fact_vle_interactions') }}
    group by
        code_module,
        code_presentation,
        id_student,
        id_site,
        relative_day

),

daily_failures as (

    -- The full join finds keys that exist on only one side.
    select
        'DAILY_KEY' as check_level,
        coalesce(s.code_module, g.code_module) as code_module,
        coalesce(s.code_presentation, g.code_presentation) as code_presentation,
        coalesce(s.row_count, 0) as silver_rows,
        coalesce(g.row_count, 0) as gold_rows,
        coalesce(s.click_total, 0) as silver_clicks,
        coalesce(g.click_total, 0) as gold_clicks
    from silver_daily s
    full outer join gold_daily g
        on s.code_module = g.code_module
        and s.code_presentation = g.code_presentation
        and s.id_student = g.id_student
        and s.id_site = g.id_site
        and s.date = g.date
    where s.code_module is null
        or g.code_module is null
        or s.row_count <> g.row_count
        or not (s.click_total <=> g.click_total)

),

silver_presentation as (

    select
        code_module,
        code_presentation,
        count(*) as row_count,
        sum(sum_click) as click_total
    from {{ source('oulad_silver', 'student_vle_clean') }}
    group by code_module, code_presentation

),

gold_presentation as (

    select
        code_module,
        code_presentation,
        count(*) as row_count,
        sum(sum_click) as click_total
    from {{ ref('fact_vle_interactions') }}
    group by code_module, code_presentation

),

presentation_failures as (

    -- Row and click totals must match within every presentation.
    select
        'PRESENTATION' as check_level,
        coalesce(s.code_module, g.code_module) as code_module,
        coalesce(s.code_presentation, g.code_presentation) as code_presentation,
        coalesce(s.row_count, 0) as silver_rows,
        coalesce(g.row_count, 0) as gold_rows,
        coalesce(s.click_total, 0) as silver_clicks,
        coalesce(g.click_total, 0) as gold_clicks
    from silver_presentation s
    full outer join gold_presentation g
        on s.code_module = g.code_module
        and s.code_presentation = g.code_presentation
    where s.code_module is null
        or g.code_module is null
        or s.row_count <> g.row_count
        or not (s.click_total <=> g.click_total)

),

global_failures as (

    -- Dataset totals provide a final reconciliation check.
    select
        'GLOBAL' as check_level,
        cast(null as string) as code_module,
        cast(null as string) as code_presentation,
        s.row_count as silver_rows,
        g.row_count as gold_rows,
        s.click_total as silver_clicks,
        g.click_total as gold_clicks
    from (
        select count(*) as row_count, sum(sum_click) as click_total
        from {{ source('oulad_silver', 'student_vle_clean') }}
    ) s
    cross join (
        select count(*) as row_count, sum(sum_click) as click_total
        from {{ ref('fact_vle_interactions') }}
    ) g
    where s.row_count <> g.row_count
        or not (s.click_total <=> g.click_total)

)

select * from daily_failures
union all
select * from presentation_failures
union all
select * from global_failures
