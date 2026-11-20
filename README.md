# CloudNativePG Operator Service Plan Template

This repository contains an Omnistrate service spec for building a PostgreSQL SaaS product with the CloudNativePG operator. The template keeps the database lifecycle in Kubernetes-native custom resources and uses Omnistrate `systemWorkflows` to expose provisioning, update, start, stop, backup, restore, and cleanup through Omnistrate APIs, Customer Portal, CLI, and Operations Center.

The service plan is defined in [`spec.yaml`](spec.yaml). It installs CloudNativePG and the Barman Cloud plugin as Helm dependencies, creates a CNPG `Cluster`, exposes writer and reader endpoints, stores backups in S3, and restores a new target cluster from Omnistrate snapshot metadata.

## Deployment models

The `deployment-models` folder holds variants of this plan for other deployment models. The Omnistrate AI architect produced each one from `spec.yaml`, then validated it and built and released it in a Dev environment. Each folder has the spec and screenshots of what Omnistrate generated from it: the architecture with its account boundaries, the security posture, the data flow, the resource graph, the customer operations with their API parameters, and the build.

| Model | Folder | Where the data plane runs |
|---|---|---|
| BYOC | [`deployment-models/byoc`](deployment-models/byoc) | Each instance runs in the customer's own AWS account, and the dataplane agent connects outbound to the generated control plane in the provider's account. |
| Multi-tenant hosted | [`deployment-models/multi-tenant-hosted`](deployment-models/multi-tenant-hosted) | Tenants share a deployment cell in the provider's account, and each tenant gets its own namespace with a NetworkPolicy, a ResourceQuota and a LimitRange. |
| Dedicated hosted | [`deployment-models/dedicated-hosted`](deployment-models/dedicated-hosted) | Tenants share a deployment cell in the provider's account, and node affinity, taints and pod anti-affinity give each tenant its own nodes. |

In every model, Omnistrate turns the system workflows in the spec into APIs, Customer Portal actions and CLI commands for provisioning, modify, stop, start, backup, restore and delete.

## Prerequisites

- An Omnistrate account.
- [`omnistrate-ctl`](https://ctl.omnistrate.cloud/install/).
- `jq`, used by the Makefile to build JSON parameters.
- AWS credentials for an S3 bucket that CloudNativePG can use for backups.

## Configuration

Copy the templates and fill in your values:

```bash
cp .env.template .env
cp .omnistrate.password.template .omnistrate.password
```

`.env` must include:

```bash
OMNISTRATE_EMAIL=your-email@example.com
POSTGRESQL_PASSWORD=your-postgres-password
BACKUP_S3_BUCKET_NAME=your-backup-bucket
BACKUP_S3_BUCKET_REGION=ap-south-1
BACKUP_S3_ACCESS_KEY_ID=your-access-key-id
BACKUP_S3_SECRET_ACCESS_KEY=your-secret-access-key
```

`.omnistrate.password` should contain only your Omnistrate password. Do not commit `.env` or `.omnistrate.password`.

## Build and Run

Log in:

```bash
make login
```

Build and release the service plan:

```bash
make release
```

Create an instance in the default AWS region configured by the Makefile:

```bash
make create
```

List or describe instances:

```bash
make list
make list INSTANCE_ID=<instance-id>
```

Start and stop an instance:

```bash
make stop-instance INSTANCE_ID=<instance-id>
make start-instance INSTANCE_ID=<instance-id>
```

Upgrade an instance:

```bash
make upgrade-instance INSTANCE_ID=<instance-id> TARGET_VERSION=<version|latest|preferred>
```

Delete all matching instances and remove the service:

```bash
make destroy
```

## Template Structure

The current template uses:

- `apiParameters` for instance type, PostgreSQL credentials, database name, replica count, storage size, and S3 backup settings.
- `endpointConfiguration` for public writer and reader PostgreSQL endpoints.
- `operatorCRDConfiguration.helmChartDependencies` to install CloudNativePG and the Barman Cloud plugin.
- `capabilities.backupConfiguration` to enable periodic backups, retention cleanup, and backup-before-delete.
- `systemWorkflows` for the managed resource lifecycle.

The deprecated `operatorCRDConfiguration.template`, `operatorCRDConfiguration.supplementalFiles`, and `operatorCRDConfiguration.readinessConditions` fields are intentionally omitted. Resource manifests, readiness checks, and output parameters are modeled in `systemWorkflows` instead.

## System Workflows

The template defines these workflows:

| Workflow | Purpose |
| --- | --- |
| `create` | Creates the PostgreSQL credentials secret, S3 credentials secret, Barman Cloud `ObjectStore`, and CNPG `Cluster`. |
| `modify` | Reapplies the CNPG `Cluster` with updated inputs such as replica count, storage size, endpoints, and placement metadata. |
| `start` | Patches CNPG hibernation to `off`. |
| `stop` | Patches CNPG hibernation to `on`. |
| `delete` | Deletes the CNPG `Cluster`, PostgreSQL credentials secret, Barman Cloud `ObjectStore`, and S3 credentials secret. |
| `backup` | Rehydrates the cluster if needed, creates a CNPG `Backup`, and returns backup metadata to Omnistrate. |
| `restore` | Creates a new target CNPG `Cluster` from the selected Omnistrate snapshot and captured backup metadata. |
| `deleteBackup` | Deletes the CNPG `Backup` resource during explicit snapshot deletion or retention cleanup. |

At minimum, operator-backed service plans should define `create`, `modify`, and `delete` so Omnistrate can provision, update, and remove the managed resource through standard lifecycle APIs. This template also includes start/stop and snapshot workflows for a complete database lifecycle.

## Backup and Restore

Backups are configured as a resource capability:

```yaml
capabilities:
  backupConfiguration:
    backupRetentionInDays: 1
    backupPeriodInHours: 1
    snapshotBeforeDeletion: true
```

`systemWorkflows.backup` receives:

- `$sys.snapshot.id`
- `$sys.snapshot.time`
- `$sys.namespace`
- `$sys.instanceId`
- `$var.numberOfInstances`

It patches hibernation to `off`, waits for the configured number of ready instances, creates a CNPG `Backup`, and returns `backupId` and `backupName` from the CNPG backup status.

`systemWorkflows.restore` receives the same create-time context needed to render the target CNPG `Cluster`, plus restore-specific context:

- `$sys.restore.snapshotId`
- `$sys.restore.snapshotTime`
- `$sys.restore.metadata.backupId`
- `$sys.restore.metadata.backupName`
- `$sys.sourceInstanceId`
- `$sys.targetInstanceId`

The restored cluster uses `$sys.targetInstanceId` as the new CNPG cluster name. It restores from the selected backup under the source instance S3 prefix and annotates the target cluster with the Omnistrate snapshot and backup metadata.

`systemWorkflows.deleteBackup` receives `$sys.snapshot.id` and `$sys.snapshot.time` and removes the matching CNPG `Backup` resource. Automated backups are expired by the backup retention policy; manual snapshots are user-controlled.

## Workflow Syntax

Workflow definitions use Argo Workflow-style structure:

- `entrypoint`
- `arguments.parameters`
- `templates`
- DAG `tasks`
- Kubernetes `resource` templates
- `successCondition` and `failureCondition`

Omnistrate renders `$sys.*`, `$var.*`, and `$func.*` expressions before executing the workflow.

## Notes

- The template does not define provider `customWorkflows`; it only uses standard Omnistrate `systemWorkflows`.
- Replica count changes are handled through the modifiable `numberOfInstances` API parameter and the `modify` workflow.
- The create and modify workflows expose output parameters from the CNPG `Cluster` status, including container image, phase, and topology.
