
CREATE TABLE IF NOT EXISTS open_university.oulad_silver.courses_clean (
  code_module STRING,
  code_presentation STRING,
  module_presentation_length INT,
  is_valid_key BOOLEAN,
  is_valid_length BOOLEAN,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

CREATE TABLE IF NOT EXISTS open_university.oulad_silver.courses_invalid_key_quarantine (
  quarantine_id STRING,
  code_module STRING,
  code_presentation STRING,
  module_presentation_length INT,
  is_valid_key BOOLEAN,
  is_valid_length BOOLEAN,
  quarantine_reason STRING,
  source_row_count BIGINT,
  clean_load_timestamp TIMESTAMP,
  clean_load_date DATE
) USING DELTA;

-- Normalize the source and flag invalid values.
CREATE OR REPLACE TEMPORARY VIEW courses_flagged_staging AS (

  WITH normalized AS (

    SELECT

      CASE
        WHEN UPPER(TRIM(CAST(code_module AS STRING)))
             IN ('?', '', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE UPPER(TRIM(CAST(code_module AS STRING)))
      END AS code_module,

      CASE
        WHEN UPPER(TRIM(CAST(code_presentation AS STRING)))
             IN ('?', '', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE UPPER(TRIM(CAST(code_presentation AS STRING)))
      END AS code_presentation,

      CASE
        WHEN UPPER(TRIM(CAST(module_presentation_length AS STRING)))
             IN ('?', '', 'NA', 'N/A', 'NULL')
          THEN NULL
        ELSE TRIM(CAST(module_presentation_length AS STRING))
      END AS module_presentation_length_raw

    FROM open_university.oulad_bronze.courses_raw
  ),

  casted AS (

    SELECT

      code_module,
      code_presentation,

      TRY_CAST(module_presentation_length_raw AS INT)
        AS module_presentation_length

    FROM normalized
  )

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,

    CASE
      WHEN code_module IS NOT NULL
       AND code_presentation IS NOT NULL
      THEN TRUE
      ELSE FALSE
    END AS is_valid_key,

    CASE
      WHEN module_presentation_length IS NOT NULL
       AND module_presentation_length > 0
      THEN TRUE
      ELSE FALSE
    END AS is_valid_length

  FROM casted
);

-- Classify valid, duplicate and conflicting records.
CREATE OR REPLACE TEMPORARY VIEW courses_classified_staging AS (

  SELECT

    f.*,

    COUNT(*) OVER (
      PARTITION BY code_module, code_presentation
    ) AS key_row_count,

    SIZE(
      COLLECT_SET(
        COALESCE(
          CAST(module_presentation_length AS STRING),
          '__NULL__'
        )
      ) OVER (
        PARTITION BY code_module, code_presentation
      )
    ) AS distinct_length_count

  FROM courses_flagged_staging f

  WHERE is_valid_key = TRUE
);

WITH clean_records AS (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length

  FROM courses_classified_staging

  WHERE distinct_length_count = 1

  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY code_module, code_presentation
    ORDER BY module_presentation_length DESC NULLS LAST
  ) = 1
)

-- Load valid records without duplicating the business key.
MERGE INTO open_university.oulad_silver.courses_clean AS target

USING (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date

  FROM clean_records

) AS source

ON  target.code_module = source.code_module
AND target.code_presentation = source.code_presentation

WHEN MATCHED THEN UPDATE SET

  target.module_presentation_length = source.module_presentation_length,
  target.is_valid_key                = source.is_valid_key,
  target.is_valid_length             = source.is_valid_length,
  target.clean_load_timestamp        = source.clean_load_timestamp,
  target.clean_load_date             = source.clean_load_date

WHEN NOT MATCHED THEN INSERT (

  code_module,
  code_presentation,
  module_presentation_length,
  is_valid_key,
  is_valid_length,
  clean_load_timestamp,
  clean_load_date

)

VALUES (

  source.code_module,
  source.code_presentation,
  source.module_presentation_length,
  source.is_valid_key,
  source.is_valid_length,
  source.clean_load_timestamp,
  source.clean_load_date

);

WITH invalid_key_records AS (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,

    'INVALID_BUSINESS_KEY' AS quarantine_reason,

    COUNT(*) OVER (
      PARTITION BY
        COALESCE(code_module, '__NULL__'),
        COALESCE(code_presentation, '__NULL__'),
        COALESCE(
          CAST(module_presentation_length AS STRING),
          '__NULL__'
        )
    ) AS source_row_count

  FROM courses_flagged_staging

  WHERE is_valid_key = FALSE
),

conflicting_records AS (

  SELECT

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,

    'CONFLICTING_BUSINESS_KEY' AS quarantine_reason,

    COUNT(*) OVER (
      PARTITION BY code_module, code_presentation
    ) AS source_row_count

  FROM courses_classified_staging

  WHERE distinct_length_count > 1
),

quarantine_records AS (

  SELECT
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count

  FROM invalid_key_records

  UNION ALL

  SELECT
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count

  FROM conflicting_records
),

quarantine_prepared AS (

  SELECT

    CONCAT_WS(
      '||',
      COALESCE(code_module, '__NULL__'),
      COALESCE(code_presentation, '__NULL__'),
      COALESCE(
        CAST(module_presentation_length AS STRING),
        '__NULL__'
      ),
      quarantine_reason
    ) AS quarantine_id,

    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count

  FROM quarantine_records

  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY
      COALESCE(code_module, '__NULL__'),
      COALESCE(code_presentation, '__NULL__'),
      COALESCE(
        CAST(module_presentation_length AS STRING),
        '__NULL__'
      ),
      quarantine_reason
    ORDER BY source_row_count DESC
  ) = 1
)

-- Keep rejected records for review.
MERGE INTO open_university.oulad_silver.courses_invalid_key_quarantine AS target

USING (

  SELECT

    quarantine_id,
    code_module,
    code_presentation,
    module_presentation_length,
    is_valid_key,
    is_valid_length,
    quarantine_reason,
    source_row_count,
    CURRENT_TIMESTAMP() AS clean_load_timestamp,
    CURRENT_DATE() AS clean_load_date

  FROM quarantine_prepared

) AS source

ON target.quarantine_id = source.quarantine_id

WHEN MATCHED THEN UPDATE SET

  target.code_module                 = source.code_module,
  target.code_presentation           = source.code_presentation,
  target.module_presentation_length  = source.module_presentation_length,
  target.is_valid_key                = source.is_valid_key,
  target.is_valid_length             = source.is_valid_length,
  target.quarantine_reason           = source.quarantine_reason,
  target.source_row_count            = source.source_row_count,
  target.clean_load_timestamp        = source.clean_load_timestamp,
  target.clean_load_date             = source.clean_load_date

WHEN NOT MATCHED THEN INSERT (

  quarantine_id,
  code_module,
  code_presentation,
  module_presentation_length,
  is_valid_key,
  is_valid_length,
  quarantine_reason,
  source_row_count,
  clean_load_timestamp,
  clean_load_date

)

VALUES (

  source.quarantine_id,
  source.code_module,
  source.code_presentation,
  source.module_presentation_length,
  source.is_valid_key,
  source.is_valid_length,
  source.quarantine_reason,
  source.source_row_count,
  source.clean_load_timestamp,
  source.clean_load_date

);
-- Cleans course presentations at the code_module + code_presentation grain.
-- Invalid or conflicting keys are stored in the quarantine table.
