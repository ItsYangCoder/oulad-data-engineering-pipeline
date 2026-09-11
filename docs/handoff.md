# OULAD handoff — September 11, 2026

## Verified before final integration

Rhea supplied Databricks output showing 32,593 unique Silver enrollments,
1,111 Unknown IMD bands, and zero NULL demographic attributes after the MERGE.
The subsequent dbt Job completed with PASS=132, WARN=0, ERROR=0, SKIP=0:
7 table models, 1 reporting view, and 124 data tests.
This evidence predates the analytics integration below.

## Reviewed integration

- PR #47 (Virna): cohort reporting and checks. Tie ordering is deterministic;
  Unknown labels follow Silver. The former always-passing zero-activity check
  now compares the Silver population to the reporting view.
- PR #50 (Shiena): existing main already covers VLE keys, relationships, grain,
  and click ranges. The two missing audit-column checks are retained without
  duplicating the fact model definition or restoring the obsolete date column.
- PR #51 (Shiena): presentation, resource-type and time-group engagement.
  Uses relative_day and the full enrollment denominator. Positive-click days
  in analytics differ from the view's recorded-day count; neither is study time.
- PR #58 (Angela): withdrawal totals, missing timing, relative-week timing,
  demographics, and checks. Missing demographics are handled in Silver.

## Remaining delivery evidence

| Item | Status |
| --- | --- |
| Integrated analytics and new audit tests | Local fixture/static verification only; run against Databricks after integration |
| Cohort dashboard | Attach the accessible Databricks SQL dashboard link and interpretation |
| Dropout dashboard | Attach the accessible Databricks SQL dashboard link and interpretation |
| VLE dashboard | Add completed Databricks SQL dashboard visual evidence |
| Assessment dashboard | Collect its Databricks SQL dashboard link with the other three sections for a complete handoff |
| CD release evidence | Capture the workflow run, Job ID, Databricks run ID and executed commit together |

Do not mark the overall documentation/review issues complete until these items
are linked and reviewed. GitHub issue checkboxes alone do not prove dashboard
content or successful runtime execution.

## Final validation

After CI passes, run the existing full dbt Job against the integrated revision.
Run all four files in tests/04_business_checks and the corresponding analytics.
These SQL files are manual checks and are not automatically executed by dbt build.
Record outputs and interpret the four business areas in the Databricks SQL dashboard.
The deployment guide records the observed Job configuration; source freshness
remains a separately configured check.

The CD workflow authenticates with an OAuth service principal to trigger the
Job. The observed Job runs as its existing user identity. These are separate
identities; do not describe the Job execution itself as service-principal-owned.
