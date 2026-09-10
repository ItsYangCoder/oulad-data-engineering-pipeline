# OULAD Data Engineering Pipeline

A Databricks and dbt data engineering project that transforms the Open University Learning Analytics Dataset (OULAD) through Bronze, Silver, and Gold layers for student performance, withdrawal, demographic, assessment, and engagement analysis.

## Project status

### Completed and merged into `main`

- Databricks catalog and schema setup
- Bronze ingestion for all seven OULAD source files
- Bronze source checks and ingestion validation
- All seven Silver transformations
- Silver table-level checks and final cross-table reconciliation
- dbt project setup with all seven Silver sources
- Five Gold dimensions
- `fact_assessments` with model documentation and dbt tests
- Assessment analytics queries and read-only business checks
- Beginner-friendly comments in implemented SQL files
- Real GitHub Actions static CI for YAML, SQL, and dbt validation

### Still in progress

- `fact_vle_interactions` and its final integration validation
- Remaining Gold reporting objects, including `vw_student_outcomes`
- Remaining analytics and Metabase dashboard evidence
- Live Databricks development deployment and production deployment
- Final VLE incremental-safety changes in draft PR #46

The README only marks work as completed when it is already merged and supported by repository or Databricks validation evidence.

## Architecture

```text
OULAD CSV files
      ↓
Bronze: open_university.oulad_bronze
      ↓
Silver: open_university.oulad_silver
      ↓
Gold/dbt: open_university.oulad_gold
      ↓
Analytics and Metabase
```

Quality and reconciliation checks use `open_university.oulad_quality`.

## Repository structure

| Path | Purpose | Current state |
| --- | --- | --- |
| `src/sql/00_setup/` | Creates the Databricks catalog and schemas | Completed |
| `src/sql/01_raw/` | Loads all seven source CSV files into Bronze Delta tables | Completed |
| `src/sql/02_clean/` | Cleans, types, deduplicates, and merges the Silver data | Completed |
| `dbt/` | Contains Silver source definitions, Gold models, documentation, and dbt tests | In progress |
| `src/sql/03_analytics/` | Contains business queries prepared for reporting | In progress |
| `tests/01_source_checks/` | Validates Bronze ingestion and source quality | Completed |
| `tests/02_clean_checks/` | Validates Silver keys, values, relationships, counts, and reconciliation | Completed |
| `tests/03_mart_checks/` | Validates Gold model grain and reconciliation | In progress |
| `tests/04_business_checks/` | Contains read-only checks for analytics results | In progress |
| `docs/` | Contains the source assessment, assumptions, and pipeline plan | Available |
| `.github/workflows/` | Runs repository CI and contains deployment workflow work | CI completed; deployment pending |

## Databricks schemas

| Schema | Purpose |
| --- | --- |
| `open_university.oulad_bronze` | Original source records with ingestion metadata |
| `open_university.oulad_silver` | Cleaned and standardized source-aligned tables |
| `open_university.oulad_gold` | Analytics-ready dimensions, facts, and reporting objects |
| `open_university.oulad_quality` | Rejected records and quality-related outputs |

## Bronze source tables

| Source file | Bronze table | Validated rows |
| --- | --- | ---: |
| `assessments.csv` | `assessment_raw` | 206 |
| `courses.csv` | `courses_raw` | 22 |
| `studentAssessment.csv` | `student_assessment_raw` | 173,912 |
| `studentInfo.csv` | `student_info_raw` | 32,593 |
| `studentRegistration.csv` | `student_registration_raw` | 32,593 |
| `studentVle.csv` | `student_vle_raw` | 10,655,280 |
| `vle.csv` | `vle_raw` | 6,364 |

Bronze preserves the source data and adds ingestion metadata. Source CSV files, credentials, tokens, generated dbt files, and local environment files must not be committed.

## Silver layer

All seven source areas now have implemented Silver transformations:

- Courses
- Assessments
- Student assessment results
- Student information and enrollment
- Student registration
- VLE resources
- Daily student VLE interactions

The Silver scripts standardize data types, preserve documented source nulls, reject invalid required keys, deduplicate at the correct business grain, and use repeatable Delta processing.

### Verified Silver results

| Validation | Result |
| --- | ---: |
| Course rows | 22 |
| Assessment rows | 206 |
| Student-assessment rows | 173,912 |
| Student enrollment rows | 32,593 |
| Student registration rows | 32,593 |
| VLE resource rows | 6,364 |
| Bronze student-VLE interaction rows | 10,655,280 |
| Silver student-VLE daily rows | 8,459,320 |
| Bronze click total | 39,605,099 |
| Silver click total | 39,605,099 |
| Required or duplicate key failures | 0 |
| Relationship orphan failures | 0 |
| Assessment reconciliation | PASS |
| VLE reconciliation | PASS |

The student-VLE row count becomes smaller because the Silver table aggregates interactions to the documented daily key. The click total is preserved.

Documented source nulls are not treated as pipeline failures:

- 11 Exam assessment rows have no assessment date.
- 173 TMA student-assessment rows have no score.
- 5,243 VLE resource rows have both week fields missing.

## Gold layer

The approved Gold scope contains exactly five dimensions, two facts, and one supporting reporting view.

### Completed Gold models

- `dim_student`
- `dim_course`
- `dim_module_presentation`
- `dim_date`
- `dim_demographics`
- `fact_assessments`

The merged dbt work includes model documentation, required-key tests, relationship tests, composite uniqueness tests, grain checks, and assessment reconciliation checks.

### Remaining Gold work

- `fact_vle_interactions`
- `vw_student_outcomes`
- Final integrated Gold validation

`fact_student_enrollment` is not part of the approved model. Enrollment and outcome details are represented through the approved dimensions and supporting view design.

## dbt setup

The `dbt/` folder now includes:

- Project configuration for `oulad_project`
- Environment-driven Databricks profile example
- Definitions for all seven validated Silver sources
- Basic source key and audit-column tests
- Gold model SQL, YAML documentation, and custom tests
- Pinned `dbt-databricks==1.12.5`
- `dbt_utils` for supported model tests

No real Databricks credentials are stored in the repository.

## CI and deployment status

GitHub Actions now performs real static validation on pull requests to `main`, pushes to `main`, and manual runs.

The current CI:

- Validates repository YAML syntax
- Confirms the YAML checker can reject an invalid example
- Parses non-dbt SQL using the Databricks SQL dialect
- Installs the pinned dbt Databricks adapter
- Installs dbt packages
- Parses the full dbt project
- Uses read-only GitHub permissions
- Cancels older runs for the same branch
- Avoids uploading generated artifacts that can bloat the repository

This is a parse-only CI job and does not connect to Databricks or modify data. Separate live development and production deployment are still pending.

## How to run the completed pipeline

### Requirements

- Databricks workspace with Unity Catalog
- Permission to create the project catalog, schemas, and Delta tables
- Access to the seven OULAD CSV files
- GitHub access to this repository
- dbt environment only when running the Gold models

### 1. Clone the repository

```bash
git clone https://github.com/ItsYangCoder/oulad-data-engineering-pipeline.git
cd oulad-data-engineering-pipeline
```

### 2. Connect the repository to Databricks

In Databricks, open **Workspace**, create or open a Git folder, and connect it to this repository.

### 3. Prepare the source files

Upload all seven OULAD CSV files to an accessible Unity Catalog Volume. Confirm that the source paths used by the ingestion scripts match the Databricks environment.

### 4. Run the SQL layers in order

1. Run `src/sql/00_setup/00_init_setup.sql`.
2. Run the scripts in `src/sql/01_raw/`.
3. Run the checks in `tests/01_source_checks/`.
4. Run the scripts in `src/sql/02_clean/`.
5. Run the checks in `tests/02_clean_checks/`.
6. Do not continue to Gold until the final Silver reconciliation returns PASS.

### 5. Run the available dbt models

From the configured dbt environment:

```bash
cd dbt
dbt deps
dbt parse --no-partial-parse
dbt build
```

Use environment variables or a local ignored profile for Databricks connection details. Never commit a real host, token, HTTP path, or profile containing credentials.

## Important processing rules

- Bronze is the source-preserving layer and must not be rebuilt destructively for ordinary new batches.
- Missing source values remain unknown unless a documented rule provides a valid replacement.
- Silver output must reconcile to Bronze using independent checks.
- Re-running the same input must not create duplicate records or change totals.
- A record missing from a partial incoming batch must not automatically delete valid stored history.
- Destructive delete behavior is only safe when the incoming data is independently confirmed as a complete authoritative snapshot.
- Production deployment must remain separate from parse-only CI.

## Documentation

- [Pipeline plan](docs/pipeline_plan.md)
- [Source assessment](docs/source_assessment.md)
- [Project assumptions](docs/assumptions.md)

## Contribution workflow

1. Pull the latest `main`.
2. Create a branch for the assigned issue.
3. Update only the assigned implementation and related checks.
4. Run the affected code in a development schema.
5. Record the actual validation results in the pull request.
6. Confirm the GitHub Actions checks pass.
7. Request a teammate review.
8. Merge only after the code, checks, and evidence agree.
