[![Release][release-image]][release] [![CI][ci-image]][ci] [![License][license-image]][license] [![Registry][registry-image]][registry] [![Source][source-image]][source]

# terraform-google-postgres-loader-pubsub-ce

A Terraform module which deploys a Snowplow Postgres Loader application on Google running on top of Compute Engine.  If you want to use a custom image for this deployment you will need to ensure it is based on top of Ubuntu 20.04.

_WARNING_: If you are upgrading from module version 0.1.x you will need to issue a manual table update - [details can be found here](https://discourse.snowplowanalytics.com/t/snowplow-postgres-loader-0-3-0-released/5553#changing-some-of-the-column-types-7).  You will need to adjust the alter table command with the schema that your `events` table is deployed within.

## Telemetry

This module by default collects and forwards telemetry information to Snowplow to understand how our applications are being used.  No identifying information about your sub-account or account fingerprints are ever forwarded to us - it is very simple information about what modules and applications are deployed and active.

If you wish to subscribe to our mailing list for updates to these modules or security advisories please set the `user_provided_id` variable to include a valid email address which we can reach you at.

### How do I disable it?

To disable telemetry simply set variable `telemetry_enabled = false`.

### What are you collecting?

For details on what information is collected please see this module: https://github.com/snowplow-devops/terraform-snowplow-telemetry

## Usage

The Postgres Loader can load both your enriched and bad data into a Postgres database - by default we are using CloudSQL as it affords a simple and cost effective way to get started.

To start loading "enriched" data into Postgres:

```hcl
module "enriched_topic" {
  source  = "snowplow-devops/pubsub-topic/google"
  version = "0.1.0"

  name = "enriched-topic"
}

module "pipeline_db" {
  source  = "snowplow-devops/cloud-sql/google"
  version = "0.1.0"

  name = "pipeline-db"

  region      = var.region
  db_name     = local.pipeline_db_name
  db_username = local.pipeline_db_username
  db_password = local.pipeline_db_password

  # Note: this exposes your data to the internet - take care to ensure your allowlist is strict enough
  authorized_networks = local.pipeline_authorized_networks

  # Note: required for higher concurrent connections count which is neccesary for loading both good and bad data at the same time
  tier = "db-g1-small"
}

module "postgres_loader_enriched" {
  source = "snowplow-devops/postgres-loader-pubsub-ce/google"

  name = "pg-loader-enriched-server"

  network    = var.network
  subnetwork = var.subnetwork
  region     = var.region
  project_id = var.project_id

  ssh_key_pairs    = []
  ssh_ip_allowlist = ["0.0.0.0/0"]

  in_topic_name = module.enriched_topic.name
  purpose       = "ENRICHED_EVENTS"
  schema_name   = "atomic"

  # Note: Using the connection_name will enforce the use of a Cloud SQL Proxy rather than a direct connection
  #       To instead use a direct connection you will need to define the `db_host` parameter instead.
  db_instance_name = module.pipeline_db.connection_name
  db_port          = module.pipeline_db.port
  db_name          = local.pipeline_db_name
  db_username      = local.pipeline_db_username
  db_password      = local.pipeline_db_password

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]
}
```

To load the "bad" data instead:

```hcl
module "bad_1_topic" {
  source  = "snowplow-devops/pubsub-topic/google"
  version = "0.1.0"

  name = "bad-1-topic"
}

module "postgres_loader_bad" {
  source = "snowplow-devops/postgres-loader-pubsub-ce/google"

  name = "pg-loader-bad-server"

  network    = var.network
  subnetwork = var.subnetwork
  region     = var.region
  project_id = var.project_id

  ssh_key_pairs    = []
  ssh_ip_allowlist = ["0.0.0.0/0"]

  in_topic_name = module.bad_1_topic.name

  # Note: The purpose defines what the input data set should look like
  purpose = "JSON"

  # Note: This schema is created automatically by the VM on launch
  schema_name = "atomic_bad"

  # Note: Using the connection_name will enforce the use of a Cloud SQL Proxy rather than a direct connection
  #       To instead use a direct connection you will need to define the `db_host` parameter instead.
  db_instance_name = module.pipeline_db.connection_name
  db_port          = module.pipeline_db.port
  db_name          = local.pipeline_db_name
  db_username      = local.pipeline_db_username
  db_password      = local.pipeline_db_password

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.15 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 3.44.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 3.44.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_telemetry"></a> [telemetry](#module\_telemetry) | snowplow-devops/telemetry/snowplow | 0.2.0 |

## Resources

| Name | Type |
|------|------|
| [google_compute_firewall.egress](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_firewall.ingress_ssh](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_instance_template.tpl](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template) | resource |
| [google_compute_region_instance_group_manager.grp](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_instance_group_manager) | resource |
| [google_project_iam_member.sa_cloud_sql_client](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.sa_logging_log_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.sa_pubsub_publisher](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.sa_pubsub_subscriber](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.sa_pubsub_viewer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_pubsub_subscription.in](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_service_account.sa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_compute_image.ubuntu_20_04](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_image) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | The name of the database to connect to | `string` | n/a | yes |
| <a name="input_db_password"></a> [db\_password](#input\_db\_password) | The password to use to connect to the database | `string` | n/a | yes |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | The port the database is running on | `number` | n/a | yes |
| <a name="input_db_username"></a> [db\_username](#input\_db\_username) | The username to use to connect to the database | `string` | n/a | yes |
| <a name="input_in_topic_name"></a> [in\_topic\_name](#input\_in\_topic\_name) | The name of the input pubsub topic that the loader will pull data from | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | A name which will be pre-pended to the resources created | `string` | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | The name of the network to deploy within | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The id of the project in which this resource is created | `string` | n/a | yes |
| <a name="input_purpose"></a> [purpose](#input\_purpose) | The type of data the loader will be pulling which can be one of ENRICHED\_EVENTS or JSON (Note: JSON can be used for loading bad rows) | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The name of the region to deploy within | `string` | n/a | yes |
| <a name="input_schema_name"></a> [schema\_name](#input\_schema\_name) | The database schema to load data into (e.g atomic \| atomic\_bad) | `string` | n/a | yes |
| <a name="input_associate_public_ip_address"></a> [associate\_public\_ip\_address](#input\_associate\_public\_ip\_address) | Whether to assign a public ip address to this instance; if false this instance must be behind a Cloud NAT to connect to the internet | `bool` | `true` | no |
| <a name="input_custom_iglu_resolvers"></a> [custom\_iglu\_resolvers](#input\_custom\_iglu\_resolvers) | The custom Iglu Resolvers that will be used by the loader to resolve and validate events | <pre>list(object({<br>    name            = string<br>    priority        = number<br>    uri             = string<br>    api_key         = string<br>    vendor_prefixes = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_db_host"></a> [db\_host](#input\_db\_host) | The hostname of the database to connect to (Note: if db\_instance\_name is non-empty this setting is ignored) | `string` | `""` | no |
| <a name="input_db_instance_name"></a> [db\_instance\_name](#input\_db\_instance\_name) | The instance name of the CloudSQL instance to connect to (Note: if set db\_host will be ignored and a proxy established instead) | `string` | `""` | no |
| <a name="input_db_max_connections"></a> [db\_max\_connections](#input\_db\_max\_connections) | The maximum number of connections to the backing database | `number` | `10` | no |
| <a name="input_default_iglu_resolvers"></a> [default\_iglu\_resolvers](#input\_default\_iglu\_resolvers) | The default Iglu Resolvers that will be used by the loader to resolve and validate events | <pre>list(object({<br>    name            = string<br>    priority        = number<br>    uri             = string<br>    api_key         = string<br>    vendor_prefixes = list(string)<br>  }))</pre> | <pre>[<br>  {<br>    "api_key": "",<br>    "name": "Iglu Central",<br>    "priority": 10,<br>    "uri": "http://iglucentral.com",<br>    "vendor_prefixes": []<br>  },<br>  {<br>    "api_key": "",<br>    "name": "Iglu Central - Mirror 01",<br>    "priority": 20,<br>    "uri": "http://mirror01.iglucentral.com",<br>    "vendor_prefixes": []<br>  }<br>]</pre> | no |
| <a name="input_gcp_logs_enabled"></a> [gcp\_logs\_enabled](#input\_gcp\_logs\_enabled) | Whether application logs should be reported to GCP Logging | `bool` | `true` | no |
| <a name="input_in_max_concurrent_checkpoints"></a> [in\_max\_concurrent\_checkpoints](#input\_in\_max\_concurrent\_checkpoints) | The maximum number of concurrent effects for the topic checkpointing system - essentially how many concurrent acks we will make to PubSub | `number` | `100` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | The labels to append to this resource | `map(string)` | `{}` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | The machine type to use | `string` | `"e2-small"` | no |
| <a name="input_ssh_block_project_keys"></a> [ssh\_block\_project\_keys](#input\_ssh\_block\_project\_keys) | Whether to block project wide SSH keys | `bool` | `true` | no |
| <a name="input_ssh_ip_allowlist"></a> [ssh\_ip\_allowlist](#input\_ssh\_ip\_allowlist) | The list of CIDR ranges to allow SSH traffic from | `list(any)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |
| <a name="input_ssh_key_pairs"></a> [ssh\_key\_pairs](#input\_ssh\_key\_pairs) | The list of SSH key-pairs to add to the servers | <pre>list(object({<br>    user_name  = string<br>    public_key = string<br>  }))</pre> | `[]` | no |
| <a name="input_subnetwork"></a> [subnetwork](#input\_subnetwork) | The name of the sub-network to deploy within; if populated will override the 'network' setting | `string` | `""` | no |
| <a name="input_target_size"></a> [target\_size](#input\_target\_size) | The number of servers to deploy | `number` | `1` | no |
| <a name="input_telemetry_enabled"></a> [telemetry\_enabled](#input\_telemetry\_enabled) | Whether or not to send telemetry information back to Snowplow Analytics Ltd | `bool` | `true` | no |
| <a name="input_ubuntu_20_04_source_image"></a> [ubuntu\_20\_04\_source\_image](#input\_ubuntu\_20\_04\_source\_image) | The source image to use which must be based of of Ubuntu 20.04; by default the latest community version is used | `string` | `""` | no |
| <a name="input_user_provided_id"></a> [user\_provided\_id](#input\_user\_provided\_id) | An optional unique identifier to identify the telemetry events emitted by this stack | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_group_url"></a> [instance\_group\_url](#output\_instance\_group\_url) | The full URL of the instance group created by the manager |
| <a name="output_manager_id"></a> [manager\_id](#output\_manager\_id) | Identifier for the instance group manager |
| <a name="output_manager_self_link"></a> [manager\_self\_link](#output\_manager\_self\_link) | The URL for the instance group manager |

# Copyright and license

The Terraform Google Postgres Loader on Compute Engine project is Copyright 2021-2021 Snowplow Analytics Ltd.

Licensed under the [Apache License, Version 2.0][license] (the "License");
you may not use this software except in compliance with the License.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[release]: https://github.com/snowplow-devops/terraform-google-postgres-loader-pubsub-ce/releases/latest
[release-image]: https://img.shields.io/github/v/release/snowplow-devops/terraform-google-postgres-loader-pubsub-ce

[ci]: https://github.com/snowplow-devops/terraform-google-postgres-loader-pubsub-ce/actions?query=workflow%3Aci
[ci-image]: https://github.com/snowplow-devops/terraform-google-postgres-loader-pubsub-ce/workflows/ci/badge.svg

[license]: https://www.apache.org/licenses/LICENSE-2.0
[license-image]: https://img.shields.io/badge/license-Apache--2-blue.svg?style=flat

[registry]: https://registry.terraform.io/modules/snowplow-devops/postgres-loader-pubsub-ce/google/latest
[registry-image]: https://img.shields.io/static/v1?label=Terraform&message=Registry&color=7B42BC&logo=terraform

[source]: https://github.com/snowplow-incubator/snowplow-postgres-loader
[source-image]: https://img.shields.io/static/v1?label=Snowplow&message=Postgres%20Loader&color=0E9BA4&logo=GitHub
