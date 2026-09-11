-- Run before rebuilding Gold; missing demographic labels belong in Silver.
select code_module, code_presentation, id_student
from {{ source('oulad_silver', 'student_info_clean') }}
where gender is null or trim(gender) = ''
   or region is null or trim(region) = ''
   or highest_education is null or trim(highest_education) = ''
   or imd_band is null or trim(imd_band) = ''
   or age_band is null or trim(age_band) = ''
   or disability is null or trim(disability) = ''
