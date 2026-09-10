# OULAD Data Engineering Pipeline

A Databricks data engineering project that transforms the Open University Learning Analytics Dataset (OULAD) through Bronze, Silver, and Gold layers for student learning analytics.

## Project status

The repository currently includes:

- Databricks catalog and schema setup
- Bronze ingestion scripts for all seven OULAD source files
- Bronze data-quality and source validation checks
- Source assessment, assumptions, and pipeline planning documents
- Silver transformations and validation checks for all seven source tables
- dbt definitions for five Gold dimensions, two facts, and an enrollment-level reporting view
- Analytics and validation SQL aligned to the declared fact grains
- Databricks execution and reconciliation pending for the redesigned Gold models

Work that is still in progress is not presented as completed in this README.

## Why we use dbt

This project uses dbt to manage the transformation logic in the Gold layer as version-controlled, reviewable code.

Instead of creating transformations manually in Databricks and leaving the logic only inside the database, dbt allows the team to:

- keep the SQL models in GitHub;
- review and track changes through pull requests;
- define dependencies between models with `source()` and `ref()`;
- run data-quality tests on the models; and
- rebuild the same transformations consistently in another environment.

The database stores the created tables and views. dbt stores and runs the transformation instructions that create or update them. Jinja and other dbt features support the models, but the main purpose is to make data transformations reproducible, testable, and easier for a team to maintain.

## Current architecture

```text
Source CSV files
      ↓
Bronze: open_university.oulad_bronze
      ↓
Silver: open_university.oulad_silver
      ↓
Gold: open_university.oulad_gold
      ↓
Analytics and Metabase
```

Quality checks use `open_university.oulad_quality`.

## Repository structure

| Path | Purpose |
| --- | --- |
| `src/sql/00_setup/` | Creates the Databricks catalog and schemas |
| `src/sql/01_raw/` | Loads the seven source CSV files into Bronze |
| `src/sql/02_clean/` | Contains the Silver cleaning transformations |
| `dbt/` | Contains the planned Gold dimensions, facts, reporting view, and dbt tests |
| `src/sql/03_analytics/` | Contains the four analytics queries for Metabase |
| `tests/` | Contains Bronze, Silver, Gold, and business validation checks |
| `docs/` | Contains the source assessment, assumptions, and pipeline plan |
| `.github/workflows/` | Contains the CI and deployment workflow files |

## Source tables

| Source file | Bronze table | Current rows |
| --- | --- | ---: |
| `assessments.csv` | `assessment_raw` | 206 |
| `courses.csv` | `courses_raw` | 22 |
| `studentAssessment.csv` | `student_assessment_raw` | 173,912 |
| `studentInfo.csv` | `student_info_raw` | 32,593 |
| `studentRegistration.csv` | `student_registration_raw` | 32,593 |
| `studentVle.csv` | `student_vle_raw` | 10,655,280 |
| `vle.csv` | `vle_raw` | 6,364 |

## Basic setup

### Requirements

- A Databricks workspace
- Permission to create a Unity Catalog catalog and schemas
- Access to the seven OULAD CSV files
- GitHub access to this repository

### 1. Clone the repository

```bash
git clone https://github.com/ItsYangCoder/oulad-data-engineering-pipeline.git
cd oulad-data-engineering-pipeline
```

### 2. Add the project to Databricks

In Databricks, open **Workspace**, create or open a Git folder, and connect it to this repository.

### 3. Prepare the source files

Upload the seven OULAD CSV files to an accessible Unity Catalog Volume. Before running the ingestion scripts, confirm that the source paths match your Databricks environment.

Do not commit source CSV files, credentials, tokens, or generated datasets to GitHub.

### 4. Run the completed setup and Bronze layer

Run the files in this order:

1. `src/sql/00_setup/00_init_setup.sql`
2. The seven scripts in `src/sql/01_raw/`
3. The validation scripts in `tests/01_source_checks/`

The setup creates these schemas:

- `open_university.oulad_bronze`
- `open_university.oulad_silver`
- `open_university.oulad_gold`
- `open_university.oulad_quality`

### 5. Run the Silver transformations

After Bronze validation passes, run the seven files in:

```text
src/sql/02_clean/
```

Then run the applicable checks in:

```text
tests/02_clean_checks/
```

Run the checks in `tests/02_clean_checks/`, then build the Gold models from the
`dbt/` directory:

```bash
dbt deps --profiles-dir .
dbt build --profiles-dir . --target dev
```

The Gold layer produces five dimensions, `fact_student_enrollment`,
`fact_vle_interactions`, and `vw_student_outcomes`.

## Important notes

- Bronze preserves the original source records and ingestion metadata.
- Missing source values must remain unknown unless a documented rule says otherwise.
- The Gold model is a fact constellation with five shared dimensions and two facts:
  `fact_student_enrollment` and `fact_vle_interactions`.
- `vw_student_outcomes` combines enrollment measures with an enrollment-level VLE summary for reporting.
- CI and deployment workflows are not considered complete until their real validation and deployment jobs are enabled and tested.

## Documentation

- [Pipeline plan](docs/pipeline_plan.md)
- [Source assessment](docs/source_assessment.md)
- [Project assumptions](docs/assumptions.md)
- [Fact constellation diagram guide](docs/images/oulad_fact_constellation.md)

## Contribution workflow

1. Pull the latest `main`.
2. Create a task branch.
3. Update only the assigned files and related checks.
4. Run the code in Databricks.
5. Record the actual validation results.
6. Open a pull request into `main`.
7. Request a teammate review before merging.
