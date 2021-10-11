locals {
  module_name    = "postgres-loader-pubsub-ce"
  module_version = "0.2.1"

  app_name    = "snowplow-postgres-loader"
  app_version = "0.3.1"

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
  version = "0.2.0"

  count = var.telemetry_enabled ? 1 : 0

  user_provided_id = var.user_provided_id
  cloud            = "GCP"
  region           = var.region
  app_name         = local.app_name
  app_version      = local.app_version
  module_name      = local.module_name
  module_version   = local.module_version
}

data "google_compute_image" "ubuntu_20_04" {
  family  = "ubuntu-2004-lts"
  project = "ubuntu-os-cloud"
}

# --- IAM: Service Account setup

resource "google_service_account" "sa" {
  account_id   = var.name
  display_name = "Snowplow PG Loader service account - ${var.name}"
}

resource "google_project_iam_member" "sa_pubsub_viewer" {
  role   = "roles/pubsub.viewer"
  member = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_pubsub_subscriber" {
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_pubsub_publisher" {
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_logging_log_writer" {
  role   = "roles/logging.logWriter"
  member = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_project_iam_member" "sa_cloud_sql_client" {
  role   = "roles/cloudsql.client"
  member = "serviceAccount:${google_service_account.sa.email}"
}

# --- CE: Firewall rules

resource "google_compute_firewall" "ingress_ssh" {
  name = "${var.name}-ssh-in"

  network     = var.network
  target_tags = [var.name]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_ip_allowlist
}

resource "google_compute_firewall" "egress" {
  name = "${var.name}-traffic-out"

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
    config        = local.config
    iglu_resolver = local.iglu_resolver
    version       = local.app_version
    db_host       = local.db_host
    db_port       = var.db_port
    db_name       = var.db_name
    db_username   = var.db_username
    db_password   = var.db_password
    schema_name   = var.schema_name

    db_instance_name        = var.db_instance_name
    cloud_sql_proxy_enabled = var.db_instance_name != ""

    telemetry_script = join("", module.telemetry.*.gcp_ubuntu_20_04_user_data)

    gcp_logs_enabled = var.gcp_logs_enabled
  })

  ssh_keys_metadata = <<EOF
%{for v in var.ssh_key_pairs~}
    ${v.user_name}:${v.public_key}
%{endfor~}
EOF
}

resource "google_compute_instance_template" "tpl" {
  name_prefix = "${var.name}-"
  description = "This template is used to create Postgres Loader instances"

  instance_description = var.name
  machine_type         = var.machine_type

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  disk {
    source_image = var.ubuntu_20_04_source_image == "" ? data.google_compute_image.ubuntu_20_04.self_link : var.ubuntu_20_04_source_image
    auto_delete  = true
    boot         = true
    disk_type    = "pd-standard"
    disk_size_gb = 10
  }

  # Note: Only one of either network or subnetwork can be supplied
  #       https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template#network_interface
  network_interface {
    network    = var.subnetwork == "" ? var.network : ""
    subnetwork = var.subnetwork

    dynamic "access_config" {
      for_each = var.associate_public_ip_address ? [1] : []

      content {
        network_tier = "PREMIUM"
      }
    }
  }

  service_account {
    email  = google_service_account.sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = local.startup_script

  metadata = {
    block-project-ssh-keys = var.ssh_block_project_keys

    ssh-keys = local.ssh_keys_metadata
  }

  tags = [var.name]

  labels = local.labels

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "grp" {
  name = "${var.name}-grp"

  base_instance_name = var.name
  region             = var.region

  target_size = var.target_size

  version {
    name              = "${local.app_name}-${local.app_version}"
    instance_template = google_compute_instance_template.tpl.self_link
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_unavailable_fixed = 3
  }

  wait_for_instances = true

  timeouts {
    create = "20m"
    update = "20m"
    delete = "30m"
  }
}
