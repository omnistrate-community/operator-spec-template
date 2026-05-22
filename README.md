# Service Spec Based Service Template

Example on how to build and deploy a Container Based Service in (Omnistrate)[https://www.omnistrate.com]

## Install Omnistrate CTL

Follow the instructions for [omnistrate-ctl installation](https://ctl.omnistrate.cloud/install/)

Detailed documentation on the commands available can be found in the [omnistrate-ctl manual](https://ctl.omnistrate.cloud/omnistrate-ctl/)

## Configuration Setup

Before using the make commands, you need to set up the following configuration files:

1. `.env` file:

   ```bash
   OMNISTRATE_EMAIL=your-email@example.com
   POSTGRESQL_PASSWORD=your-postgres-password
   ```

2. `.omnistrate.password` file:

   ```bash
   your-omnistrate-password
   ```

Make sure to keep this file secure and never commit it to version control.

## Available Make Commands

- `make install-ctl`: Installs the Omnistrate CLI tool (omnistrate-ctl) via Homebrew
- `make upgrade-ctl`: Upgrades the Omnistrate CLI tool to the latest version
- `make login`: Logs in to Omnistrate using credentials from your environment
- `make release`: Builds and releases the service using the compose.yaml configuration
- `make create`: Creates a new instance of the service with the following defaults:
  - Environment: Dev
  - Cloud Provider: AWS
  - Region: ap-south-1
  - PostgreSQL password: read from `POSTGRESQL_PASSWORD`
- `make list`: Lists all instances in JSON format
- `make delete-all`: Deletes all running instances immediately
- `make delete-all-wait`: Deletes all instances and waits for completion
- `make destroy`: Deletes all instances and removes the service completely

## Operator Workflow Example

The service spec demonstrates CloudNativePG lifecycle workflows:

- `operatorCRDConfiguration` keeps `outputParameters` and the CNPG Helm chart dependency. The deprecated `template`, `supplementalFiles`, and `readinessConditions` fields are intentionally omitted when lifecycle is managed by system workflows.
- `systemWorkflows.create` creates the `basic-auth` secret, applies the CNPG `Cluster` resource through an Argo DAG, and waits for the CNPG Ready condition.
- `systemWorkflows.modify` reapplies the CNPG `Cluster` resource through an Argo DAG and waits for the CNPG Ready condition.
- `systemWorkflows.delete` deletes the CNPG `Cluster` resource and then deletes the `basic-auth` secret.
- CREATE and MODIFY readiness is expressed on the workflow resource tasks with `successCondition`, for example `status.conditions.#(type=="Ready").status == True`.
- `systemWorkflows.backup` is used by manual backups, periodic backups from `backupPeriodInHours`, and backup-before-delete when `snapshotBeforeDeletion` is enabled.
- `systemWorkflows.restore` uses the Omnistrate restore API context. The restored CNPG cluster name comes from `$sys.targetInstanceId`; snapshot identity comes from `$sys.restore.snapshotId` and `$sys.restore.snapshotTime`.
- `systemWorkflows.deleteBackup` is used by explicit snapshot deletion and retention cleanup. It receives the same `$sys.snapshot.*` values as backup.
- `customWorkflows.failover` is a provider-defined action. It does not receive restore context; it uses `$sys.namespace`, `$sys.instanceId`, and the user-supplied `primaryPodName`.

The CNPG backup workflow creates a `Backup` resource using the `barmanObjectStore` method for S3-backed backups. A production spec must also configure the CNPG cluster backup backend, credentials, and WAL/archive settings.
