# Databricks CD setup

The deployment workflow triggers the existing Databricks dbt Job and waits for it to finish. It does not create or update a Job, so reruns do not produce duplicate Databricks resources.

## Authentication

Use a Databricks service principal with GitHub OIDC workload identity federation. This lets GitHub obtain short-lived Databricks OAuth tokens without storing a personal access token or a Databricks client secret.

1. Create a service principal named `github-oulad-cd` in Databricks.
2. Add the service principal to the target workspace.
3. Create a federation policy for the service principal with these GitHub identity values:

   | Field | Value |
   |---|---|
   | Issuer | `https://token.actions.githubusercontent.com` |
   | Organization or owner | `ItsYangCoder` |
   | Repository | `oulad-data-engineering-pipeline` |
   | Entity type | `Environment` |
   | Environment | `production` |

4. Grant the service principal `CAN MANAGE RUN` on the existing OULAD dbt Job.
5. Keep the Job's current **Run as** identity during the first CD test. Changing **Run as** to the service principal is a separate production-hardening step that requires warehouse, Unity Catalog, and Git source permissions.

## GitHub production environment

Create a GitHub environment named `production`, then configure:

| Type | Name | Value |
|---|---|---|
| Variable | `DATABRICKS_HOST` | Databricks workspace URL, without `/api` |
| Variable | `DATABRICKS_CLIENT_ID` | Service principal application/client ID |
| Variable | `DATABRICKS_JOB_ID` | Existing OULAD dbt Job ID |

No Databricks secret is required. Do not add `DATABRICKS_TOKEN` or `DATABRICKS_CLIENT_SECRET`.

## First deployment test

1. Merge the workflow into `main` only after the service principal and GitHub environment are ready.
2. Open **Actions > Deploy OULAD Gold > Run workflow**.
3. Select `main` and run the workflow.
4. Confirm the workflow summary contains the GitHub revision, Databricks Job ID, and Databricks run ID.
5. Confirm the Databricks run finishes with all dbt models and tests passing.

The first version is intentionally manual. An automatic post-CI trigger can be enabled after the manual development test succeeds.

## Deployment scope

The existing Databricks Job runs `dbt deps` followed by `dbt build` for the dbt project. It builds and tests the modeled layers according to dbt dependencies; it does not run the raw-data setup notebook.
