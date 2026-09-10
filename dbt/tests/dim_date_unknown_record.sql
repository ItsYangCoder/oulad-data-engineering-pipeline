-- Returns a row unless exactly one Unknown date record exists.
select count(*) as unknown_row_count
from {{ ref('dim_date') }}
where date_key = 'UNKNOWN'
  and relative_day is null
having count(*) <> 1
