-- Nagfa-fail ang test kapag may kulang o duplicate na business key.
-- Kapag walang lumabas na row, unique at complete ang grain ng fact table.

with fact_rows as (

    select
        code_module,
        code_presentation,
        id_student,
        id_site,
        date
    from {{ ref('fact_vle_interactions') }}

),

missing_keys as (

    -- Hindi dapat NULL ang kahit anong bahagi ng five-column business key.
    select
        'MISSING_KEY' as failure_type,
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        1 as failure_count
    from fact_rows
    where code_module is null
        or code_presentation is null
        or id_student is null
        or id_site is null
        or date is null

),

duplicate_keys as (

    -- Mahigit isang row sa parehong key ay ibig sabihin nadoble ang daily activity.
    select
        'DUPLICATE_KEY' as failure_type,
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        count(*) as failure_count
    from fact_rows
    group by
        code_module,
        code_presentation,
        id_student,
        id_site,
        date
    having count(*) > 1

)

select * from missing_keys
union all
select * from duplicate_keys
