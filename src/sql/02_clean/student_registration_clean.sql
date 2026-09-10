
CREATE TABLE IF NOT EXISTS
    open_university.oulad_silver.student_registration_clean
(
    code_module              STRING,
    code_presentation        STRING,
    id_student               BIGINT,
    date_registration        INT,
    date_unregistration      INT,
    clean_load_timestamp     TIMESTAMP,
    clean_load_date          DATE
)
USING DELTA;

-- Report incomplete business keys before loading.
WITH normalized_keys AS (

    SELECT

        CASE
            WHEN UPPER(TRIM(code_module)) IN
                 ('', '?', 'NA', 'N/A', 'NULL')
            THEN NULL

            ELSE UPPER(TRIM(code_module))
        END AS code_module,

        CASE
            WHEN UPPER(TRIM(code_presentation)) IN
                 ('', '?', 'NA', 'N/A', 'NULL')
            THEN NULL

            ELSE UPPER(TRIM(code_presentation))
        END AS code_presentation,

        TRY_CAST(id_student AS BIGINT) AS id_student

    FROM open_university.oulad_bronze.student_registration_raw
)

SELECT
    COUNT(*) AS invalid_business_key_rows

FROM normalized_keys

WHERE code_module IS NULL
   OR code_presentation IS NULL
   OR id_student IS NULL;

-- Update existing registrations and insert new ones.
MERGE INTO
    open_university.oulad_silver.student_registration_clean AS target

USING (

    WITH normalized AS (

        SELECT

            CASE
                WHEN UPPER(TRIM(code_module)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(code_module))
            END AS code_module,

            CASE
                WHEN UPPER(TRIM(code_presentation)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE UPPER(TRIM(code_presentation))
            END AS code_presentation,

            TRY_CAST(id_student AS BIGINT) AS id_student,

            CASE
                WHEN UPPER(TRIM(date_registration)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRY_CAST(
                    TRIM(date_registration) AS INT
                )
            END AS date_registration,

            CASE
                WHEN UPPER(TRIM(date_unregistration)) IN
                     ('', '?', 'NA', 'N/A', 'NULL')
                THEN NULL

                ELSE TRY_CAST(
                    TRIM(date_unregistration) AS INT
                )
            END AS date_unregistration

        FROM
            open_university.oulad_bronze.student_registration_raw
    ),

    prepared AS (

        SELECT
            code_module,
            code_presentation,
            id_student,
            date_registration,
            date_unregistration,

            CURRENT_TIMESTAMP() AS clean_load_timestamp,
            CURRENT_DATE() AS clean_load_date

        FROM normalized

        WHERE code_module IS NOT NULL
          AND code_presentation IS NOT NULL
          AND id_student IS NOT NULL
    )

    SELECT *
    FROM prepared

) AS source

ON  target.code_module       = source.code_module
AND target.code_presentation = source.code_presentation
AND target.id_student        = source.id_student

WHEN MATCHED THEN UPDATE SET

    target.date_registration    = source.date_registration,
    target.date_unregistration  = source.date_unregistration,
    target.clean_load_timestamp = source.clean_load_timestamp,
    target.clean_load_date      = source.clean_load_date

WHEN NOT MATCHED THEN INSERT
(
    code_module,
    code_presentation,
    id_student,
    date_registration,
    date_unregistration,
    clean_load_timestamp,
    clean_load_date
)

VALUES
(
    source.code_module,
    source.code_presentation,
    source.id_student,
    source.date_registration,
    source.date_unregistration,
    source.clean_load_timestamp,
    source.clean_load_date
);
-- Cleans registration dates at the student enrollment grain.
-- Business key: code_module + code_presentation + id_student.
