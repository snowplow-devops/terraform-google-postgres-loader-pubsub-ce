locals {
  module_name    = "postgres-loader-pubsub-ce"
  module_version = "0.4.1"

  app_name    = "snowplow-postgres-loader"
  app_version = var.app_version

  local_labels = {
    name           = var.name
    app_name       = local.app_name
    app_version    = replace(local.app_version, ".", "-")
    module_name    = local.module_name
    module_version = replace(local.module_version, ".", "-")
  }

  labels = merge(
    var.labels,
    local.local_labels
  )
}

module "telemetry" {
  source  = "snowplow-devops/telemetry/snowplow"
  version = "0.5.0"

  count = var.telemetry_enabled ? 1 : 0

  user_provided_id = var.user_provided_id
  cloud            = "GCP"
  region           = var.region
  app_name         = local.app_name
  app_version      = local.app_version
  module_name      = local.module_name
  module_version   = local.module_version
}

# --- IAM: Service Account setup

resource "google_service_account" "sa" {
  account_id   = var.name
  display_name = "Snowplow PG Loader service account - ${var.name}"
}

resource "google_project_iam_member" "sa_pubsub_viewer" {
  project = var.project_id
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_logging_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_cloud_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

# --- CE: Firewall rules

resource "google_compute_firewall" "ingress_ssh" {
  project = (var.network_project_id != "") ? var.network_project_id : var.project_id
  name    = "${var.name}-ssh-in"

  network     = var.network
  target_tags = [var.name]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_ip_allowlist
}

resource "google_compute_firewall" "egress" {
  project = (var.network_project_id != "") ? var.network_project_id : var.project_id
  name    = "${var.name}-traffic-out"

  network     = var.network
  target_tags = [var.name]

  allow {
    protocol = "tcp"
    ports    = ["80", "443", var.db_port]
  }

  allow {
    protocol = "udp"
    ports    = ["123"]
  }

  direction          = "EGRESS"
  destination_ranges = ["0.0.0.0/0"]
}

# --- CE: Instance group setup

resource "google_pubsub_subscription" "in" {
  name  = var.name
  topic = var.in_topic_name

  expiration_policy {
    ttl = ""
  }

  labels = local.labels
}

locals {
  resolvers_raw = concat(var.default_iglu_resolvers, var.custom_iglu_resolvers)

  resolvers_open = [
    for resolver in local.resolvers_raw : merge(
      {
        name           = resolver["name"],
        priority       = resolver["priority"],
        vendorPrefixes = resolver["vendor_prefixes"],
        connection = {
          http = {
            uri = resolver["uri"]
          }
        }
      }
    ) if resolver["api_key"] == ""
  ]

  resolvers_closed = [
    for resolver in local.resolvers_raw : merge(
      {
        name           = resolver["name"],
        priority       = resolver["priority"],
        vendorPrefixes = resolver["vendor_prefixes"],
        connection = {
          http = {
            uri    = resolver["uri"]
            apikey = resolver["api_key"]
          }
        }
      }
    ) if resolver["api_key"] != ""
  ]

  resolvers = flatten([
    local.resolvers_open,
    local.resolvers_closed
  ])

  iglu_resolver = templatefile("${path.module}/templates/iglu_resolver.json.tmpl", { resolvers = jsonencode(local.resolvers) })

  # Note: If we are provided a valid DB Instance Name leverage CloudSQL proxy
  db_host = var.db_instance_name == "" ? var.db_host : "127.0.0.1"

  config = templatefile("${path.module}/templates/config.json.tmpl", {
    project_id                    = var.project_id
    in_subscription_name          = google_pubsub_subscription.in.name
    in_max_concurrent_checkpoints = var.in_max_concurrent_checkpoints

    db_host            = local.db_host
    db_port            = var.db_port
    db_name            = var.db_name
    db_username        = var.db_username
    db_password        = var.db_password
    db_max_connections = var.db_max_connections

    schema_name = var.schema_name
    purpose     = var.purpose
  })

  startup_script = templatefile("${path.module}/templates/startup-script.sh.tmpl", {
    accept_limited_use_license = var.accept_limited_use_license

    config_b64        = base64encode(local.config)
    iglu_resolver_b64 = base64encode(local.iglu_resolver)
    version           = local.app_version
    db_host           = local.db_host
    db_port           = var.db_port
    db_name           = var.db_name
    db_username       = var.db_username
    db_password       = var.db_password
    schema_name       = var.schema_name

    db_instance_name        = var.db_instance_name
    cloud_sql_proxy_enabled = var.db_instance_name != ""

    telemetry_script = join("", module.telemetry.*.gcp_ubuntu_20_04_user_data)

    gcp_logs_enabled = var.gcp_logs_enabled

    java_opts = var.java_opts
  })
}

module "service" {
  source  = "snowplow-devops/service-ce/google"
  version = "0.1.0"

  user_supplied_script        = local.startup_script
  name                        = var.name
  instance_group_version_name = "${local.app_name}-${local.app_version}"
  labels                      = local.labels

  region     = var.region
  network    = var.network
  subnetwork = var.subnetwork

  ubuntu_20_04_source_image   = var.ubuntu_20_04_source_image
  machine_type                = var.machine_type
  target_size                 = var.target_size
  ssh_block_project_keys      = var.ssh_block_project_keys
  ssh_key_pairs               = var.ssh_key_pairs
  service_account_email       = google_service_account.sa.email
  associate_public_ip_address = var.associate_public_ip_address
}
