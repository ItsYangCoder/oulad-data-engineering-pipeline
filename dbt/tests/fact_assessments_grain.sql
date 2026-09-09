{{ config(enabled=true) }}

with null_grain as (
    select
        id_assessment,
        id_student,
        'NULL_GRAIN_KEY' as failure_type,
        cast(null as bigint) as row_count
    from {{ ref('fact_assessments') }}
    where id_assessment is null
       or id_student is null
),

duplicate_grain as (
    select
        id_assessment,
        id_student,
        'DUPLICATE_GRAIN' as failure_type,
        count(*) as row_count
    from {{ ref('fact_assessments') }}
    group by id_assessment, id_student
    having count(*) > 1
)

select * from null_grain
union all
select * from duplicate_grain
