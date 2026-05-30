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
- `make upgrade-instance INSTANCE_ID=<instance-id> TARGET_VERSION=<version|latest|preferred>`: Triggers an upgrade for an instance to the target service version
- `make delete-all`: Deletes all running instances immediately
- `make delete-all-wait`: Deletes all instances and waits for completion
- `make destroy`: Deletes all instances and removes the service completely

## Operator Workflow Example

The service spec demonstrates CloudNativePG lifecycle workflows:

- `operatorCRDConfiguration` keeps `outputParameters` and the CNPG Helm chart dependency. The deprecated `template`, `supplementalFiles`, and `readinessConditions` fields are intentionally omitted when lifecycle is managed by system workflows.
- `systemWorkflows.create` creates the `basic-auth` secret, the S3 backup credentials secret, the Barman Cloud `ObjectStore`, applies the CNPG `Cluster` resource through an Argo DAG, and waits for the CNPG Ready condition.
- `systemWorkflows.modify` reapplies the CNPG `Cluster` resource through an Argo DAG and waits for the CNPG Ready condition.
- `systemWorkflows.start` and `systemWorkflows.stop` toggle CNPG declarative hibernation. `systemWorkflows.addCapacity` and `systemWorkflows.removeCapacity` patch the CNPG `Cluster` instance count and wait until CNPG reports the requested number of total and ready instances.
- `systemWorkflows.delete` deletes the CNPG `Cluster` resource and then deletes the `basic-auth` secret, Barman Cloud `ObjectStore`, and S3 backup credentials secret.
- CREATE and MODIFY readiness is expressed on the workflow resource tasks with `successCondition`, for example `status.conditions.#(type=="Ready").status == True`.
- `systemWorkflows.backup` is used by manual backups, periodic backups from `backupPeriodInHours`, and backup-before-delete when `snapshotBeforeDeletion` is enabled. It rehydrates the CNPG cluster and waits for ready instances before creating the `Backup` resource because CNPG cannot back up a hibernated cluster.
- `systemWorkflows.restore` uses the Omnistrate restore API context. The restored CNPG cluster name comes from `$sys.targetInstanceId`; snapshot identity comes from `$sys.restore.snapshotId` and `$sys.restore.snapshotTime`. The restore workflow only references restore-time system parameters plus service input parameters because it runs before the normal create reconciliation has full deployment, network, and compute system parameters available.
- `systemWorkflows.deleteBackup` is used by explicit snapshot deletion and retention cleanup. It receives the same `$sys.snapshot.*` values as backup.
- `customWorkflows.failover` is a provider-defined action. It does not receive restore context; it uses `$sys.namespace`, `$sys.instanceId`, and the user-supplied `primaryPodName`.

The CNPG backup workflow rehydrates the cluster and then creates a `Backup` resource using the Barman Cloud plugin for S3-backed backups. The create workflow also creates an S3 credentials secret and a Barman Cloud `ObjectStore` for the configured backup bucket and region, with base-backup settings only and no WAL archiving configuration.
