-- Initial load: creates and loads the table only if it does not exist.

CREATE TABLE IF NOT EXISTS
    open_university.oulad_bronze.assessment_raw
USING DELTA
AS
SELECT
    *,
    current_timestamp() AS ingestion_timestamp,
    current_date() AS ingestion_date
FROM read_files(
    '/Volumes/open_university/oulad_bronze/ftw-b12/shared/week07/assessments.csv'
);




