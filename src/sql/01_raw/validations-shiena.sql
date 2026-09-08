--1 student_info_bronze

SELECT *
FROM week7.bronze.student_info_bronze
WHERE (code_module IS NULL OR code_module IN ('?', ''))
   OR (code_presentation IS NULL OR code_presentation IN ('?', ''))
   OR id_student IS NULL
   OR (gender IS NULL OR gender IN ('?', ''))
   OR (region IS NULL OR region IN ('?', ''))
   OR (highest_education IS NULL OR highest_education IN ('?', ''))
   OR (imd_band IS NULL OR imd_band IN ('?', ''))
   OR (age_band IS NULL OR age_band IN ('?', ''))
   OR num_of_prev_attempts IS NULL
   OR studied_credits IS NULL
   OR (disability IS NULL OR disability IN ('?', ''))
   OR (final_result IS NULL OR final_result IN ('?', ''));


-- 2 vle_bronze
SELECT *
FROM week7.bronze.vle_bronze
WHERE id_site IS NULL
   OR (code_module IS NULL OR code_module IN ('?', ''))
   OR (code_presentation IS NULL OR code_presentation IN ('?', ''))
   OR (activity_type IS NULL OR activity_type IN ('?', ''))
   OR CAST(week_from AS STRING) IN ('?', '') OR week_from IS NULL
   OR CAST(week_to AS STRING) IN ('?', '') OR week_to IS NULL;

-- 3 unique checks
SELECT
    id_site,
    code_module,
    code_presentation,
    COUNT(*) AS duplicate_count
FROM week7.bronze.vle_bronze
GROUP BY id_site, code_module, code_presentation
HAVING COUNT(*) > 1;

-- 4 student_info_bronze
SELECT
    id_student,
    code_module,
    code_presentation,
    COUNT(*) AS duplicate_count
FROM week7.bronze.student_info_bronze
GROUP BY id_student, code_module, code_presentation
HAVING COUNT(*) > 1;

-------------- Expected Source Relationships --------------------
---5 assessments -> courses
SELECT COUNT(*) AS unmatched_records
FROM week7.bronze.assessments_bronze child
LEFT JOIN week7.bronze.courses_bronze parent
  ON child.code_module = parent.code_module 
 AND child.code_presentation = parent.code_presentation
WHERE parent.code_module IS NULL;

--6 studentInfo -> courses
SELECT COUNT(*) AS unmatched_records
FROM week7.bronze.student_info_bronze child
LEFT JOIN week7.bronze.courses_bronze parent
  ON child.code_module = parent.code_module 
 AND child.code_presentation = parent.code_presentation
WHERE parent.code_module IS NULL;


--7 vle -> courses
SELECT COUNT(*) AS unmatched_records
FROM week7.bronze.vle_bronze child
LEFT JOIN week7.bronze.courses_bronze parent
  ON child.code_module = parent.code_module 
 AND child.code_presentation = parent.code_presentation
WHERE parent.code_module IS NULL;


-----------------Initial Data-Quality Risks
--Risk 1: Duplicate candidate keys
---Verify that the composite key for registrations and the single key for VLE sites are completely unique.
-- 8 student_registration_bronze (Composite Key)
SELECT id_student, code_module, code_presentation, COUNT(*) as duplicate_count
FROM week7.bronze.student_registration_bronze
GROUP BY id_student, code_module, code_presentation
HAVING COUNT(*) > 1;

-- 9 vle_bronze (Single Key)
SELECT id_site, COUNT(*) as duplicate_count
FROM week7.bronze.vle_bronze
GROUP BY id_site
HAVING COUNT(*) > 1;


--Risk 2: Missing student or module identifiers
---Check for fundamental NULL values in the identifier columns for both tables.
--10 student_registration_bronze
SELECT COUNT(*) as missing_identifiers
FROM week7.bronze.student_registration_bronze
WHERE id_student IS NULL OR code_module IS NULL OR code_presentation IS NULL;

-- 11 vle_bronze
SELECT COUNT(*) as missing_identifiers
FROM week7.bronze.vle_bronze
WHERE id_site IS NULL OR code_module IS NULL OR code_presentation IS NULL;


--Risk 6: Null date_unregistration values
---12 Investigate nulls in the unregistration date field. In the OULAD dataset, a null here typically indicates a student who stayed enrolled and completed the course, but the volume must be verified before making that assumption in the Mart layer.
SELECT COUNT(*) as active_students_null_unregistration
FROM week7.bronze.student_registration_bronze
WHERE date_unregistration IS NULL;


---Risk 9: Unmatched student registrations
---13 Check if there are registration records for students that do not exist in the master student_info_bronze table.
SELECT sr.id_student, sr.code_module, sr.code_presentation
FROM week7.bronze.student_registration_bronze sr
LEFT JOIN week7.bronze.student_info_bronze si 
  ON sr.id_student = si.id_student 
 AND sr.code_module = si.code_module 
 AND sr.code_presentation = si.code_presentation
WHERE si.id_student IS NULL;


--Risk 12: Join multiplication caused by incomplete composite-key joins
---Verify that joining student_registration_bronze or vle_bronze to the courses_bronze table requires the full composite key (code_module, code_presentation). If code_presentation is omitted, joining on code_module alone will cause row duplication because modules repeat across different semesters.

-- 14 Check how many presentations exist per module to understand the multiplication risk
SELECT code_module, COUNT(DISTINCT code_presentation) as presentations_per_module
FROM week7.bronze.vle_bronze
GROUP BY code_module
HAVING COUNT(DISTINCT code_presentation) > 1;

--
SELECT COUNT(*) as active_students_unregistered
FROM week7.bronze.student_registration_bronze
WHERE date_unregistration = '?';
