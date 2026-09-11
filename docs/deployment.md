# Databricks CD setup

The deployment workflow triggers the existing Databricks dbt Job and waits for it to finish. It does not create or update a Job, so reruns do not produce duplicate Databricks resources.

## Authentication

Use a Databricks service principal with OAuth machine-to-machine authentication. Do not create or configure a personal access token.

1. Create a service principal named `github-oulad-cd` in Databricks.
2. Add the service principal to the target workspace.
3. Generate an OAuth secret scoped to `jobs` and copy it immediately.
4. Grant the service principal `CAN MANAGE RUN` on the existing OULAD dbt Job.
5. Keep the Job's current **Run as** identity during the first CD test. Changing **Run as** to the service principal is a separate production-hardening step that requires warehouse, Unity Catalog, and Git source permissions.

## GitHub production environment

Create a GitHub environment named `production`, then configure:

| Type | Name | Value |
|---|---|---|
| Variable | `DATABRICKS_HOST` | Databricks workspace URL, without `/api` |
| Variable | `DATABRICKS_CLIENT_ID` | Service principal application/client ID |
| Variable | `DATABRICKS_JOB_ID` | Existing OULAD dbt Job ID |
| Secret | `DATABRICKS_CLIENT_SECRET` | Service principal OAuth secret |

Do not add `DATABRICKS_TOKEN`.

## First deployment test

1. Merge the workflow into `main` only after the service principal and GitHub environment are ready.
2. Open **Actions > Deploy OULAD Gold > Run workflow**.
3. Select `main` and run the workflow.
4. Confirm the workflow summary contains the GitHub revision, Databricks Job ID, and Databricks run ID.
5. Confirm the Databricks run finishes with all dbt models and tests passing.

The first version is intentionally manual. An automatic post-CI trigger can be enabled after the manual development test succeeds.

## Deployment scope

The Job configuration shown during validation runs `dbt deps`, `dbt parse`, and `dbt build` from the `dbt` project directory on Git branch `main`. It builds and tests Gold models; it does not execute the Bronze or Silver SQL scripts or source freshness.

## Revision integrity

The GitHub workflow triggers an existing Databricks Job; it does not upload repository files. Before using the workflow as a release mechanism, configure the Job's Git source and release process so the Job runs the same commit that passed CI. Record that commit in the job run metadata or deployment summary. A successful GitHub workflow alone is not proof that the Databricks Job used the same source revision.

The verified command sequence is:

```bash
dbt deps
dbt parse
dbt build
```

`dbt source freshness` is an additional check, not part of the recorded successful run. Before enabling it, document whether the static OULAD batch is expected to be refreshed. The configured `clean_load_timestamp` measures load time, not source event recency. Validate the target/profile separately before adopting a production-specific command.
