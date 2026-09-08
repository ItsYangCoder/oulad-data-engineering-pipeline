-- Suggested branch: test/bronze-checks
-- For checks tied to one transformation, use that transformation's branch instead.

-- Shows sample repeated student VLE daily keys.

SELECT
    code_module,
    code_presentation,
    id_student,
    id_site,
    date,
    COUNT(*) AS source_row_count,
    SUM(sum_click) AS total_clicks
FROM open_university.oulad_bronze.student_vle_raw
GROUP BY
    code_module,
    code_presentation,
    id_student,
    id_site,
    date
HAVING COUNT(*) > 1
ORDER BY source_row_count DESC
LIMIT 20;


SELECT
    COUNT(*) AS repeated_key_groups,
    SUM(source_row_count - 1) AS repeated_key_rows
FROM (
    SELECT
        code_module,
        code_presentation,
        id_student,
        id_site,
        date,
        COUNT(*) AS source_row_count
    FROM open_university.oulad_bronze.student_vle_raw
    GROUP BY
        code_module,
        code_presentation,
        id_student,
        id_site,
        date
    HAVING COUNT(*) > 1
);