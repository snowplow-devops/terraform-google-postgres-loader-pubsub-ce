variable "accept_limited_use_license" {
  description = "Acceptance of the SLULA terms (https://docs.snowplow.io/limited-use-license-1.0/)"
  type        = bool
  default     = false

  validation {
    condition     = var.accept_limited_use_license
    error_message = "Please accept the terms of the Snowplow Limited Use License Agreement to proceed."
  }
}

variable "name" {
  description = "A name which will be pre-pended to the resources created"
  type        = string
}

variable "app_version" {
  description = "App version to use. This variable facilitates dev flow, the modules may not work with anything other than the default value."
  type        = string
  default     = "0.3.1"
}

variable "project_id" {
  description = "The project ID in which the stack is being deployed"
  type        = string
}

variable "network_project_id" {
  description = "The project ID of the shared VPC in which the stack is being deployed"
  type        = string
  default     = ""
}

variable "region" {
  description = "The name of the region to deploy within"
  type        = string
}

variable "network" {
  description = "The name of the network to deploy within"
  type        = string
}

variable "subnetwork" {
  description = "The name of the sub-network to deploy within; if populated will override the 'network' setting"
  type        = string
  default     = ""
}

variable "machine_type" {
  description = "The machine type to use"
  type        = string
  default     = "e2-small"
}

variable "target_size" {
  description = "The number of servers to deploy"
  default     = 1
  type        = number
}

variable "associate_public_ip_address" {
  description = "Whether to assign a public ip address to this instance; if false this instance must be behind a Cloud NAT to connect to the internet"
  type        = bool
  default     = true
}

variable "ssh_ip_allowlist" {
  description = "The list of CIDR ranges to allow SSH traffic from"
  type        = list(any)
  default     = ["0.0.0.0/0"]
}

variable "ssh_block_project_keys" {
  description = "Whether to block project wide SSH keys"
  type        = bool
  default     = true
}

variable "ssh_key_pairs" {
  description = "The list of SSH key-pairs to add to the servers"
  default     = []
  type = list(object({
    user_name  = string
    public_key = string
  }))
}

variable "ubuntu_24_04_source_image" {
  description = "The source image to use which must be based of of Ubuntu 24.04; by default the latest community version is used"
  default     = ""
  type        = string
}

variable "labels" {
  description = "The labels to append to this resource"
  default     = {}
  type        = map(string)
}

variable "gcp_logs_enabled" {
  description = "Whether application logs should be reported to GCP Logging"
  default     = true
  type        = bool
}

variable "java_opts" {
  description = "Custom JAVA Options"
  default     = "-XX:InitialRAMPercentage=75 -XX:MaxRAMPercentage=75"
  type        = string
}

# --- Configuration options

variable "in_topic_name" {
  description = "The name of the input pubsub topic that the loader will pull data from"
  type        = string
}

variable "in_max_concurrent_checkpoints" {
  description = "The maximum number of concurrent effects for the topic checkpointing system - essentially how many concurrent acks we will make to PubSub"
  type        = number
  default     = 100
}

variable "purpose" {
  description = "The type of data the loader will be pulling which can be one of ENRICHED_EVENTS or JSON (Note: JSON can be used for loading bad rows)"
  type        = string
}

variable "schema_name" {
  description = "The database schema to load data into (e.g atomic | atomic_bad)"
  type        = string
}

variable "db_instance_name" {
  description = "The instance name of the CloudSQL instance to connect to (Note: if set db_host will be ignored and a proxy established instead)"
  type        = string
  default     = ""
}

variable "db_host" {
  description = "The hostname of the database to connect to (Note: if db_instance_name is non-empty this setting is ignored)"
  type        = string
  default     = ""
}

variable "db_port" {
  description = "The port the database is running on"
  type        = number
}

variable "db_name" {
  description = "The name of the database to connect to"
  type        = string
}

variable "db_username" {
  description = "The username to use to connect to the database"
  type        = string
}

variable "db_password" {
  description = "The password to use to connect to the database"
  type        = string
  sensitive   = true
}

variable "db_max_connections" {
  description = "The maximum number of connections to the backing database"
  type        = number
  default     = 10
}

# --- Iglu Resolver

variable "default_iglu_resolvers" {
  description = "The default Iglu Resolvers that will be used by the loader to resolve and validate events"
  default = [
    {
      name            = "Iglu Central"
      priority        = 10
      uri             = "http://iglucentral.com"
      api_key         = ""
      vendor_prefixes = []
    },
    {
      name            = "Iglu Central - Mirror 01"
      priority        = 20
      uri             = "http://mirror01.iglucentral.com"
      api_key         = ""
      vendor_prefixes = []
    }
  ]
  type = list(object({
    name            = string
    priority        = number
    uri             = string
    api_key         = string
    vendor_prefixes = list(string)
  }))
}

variable "custom_iglu_resolvers" {
  description = "The custom Iglu Resolvers that will be used by the loader to resolve and validate events"
  default     = []
  type = list(object({
    name            = string
    priority        = number
    uri             = string
    api_key         = string
    vendor_prefixes = list(string)
  }))
}

# --- Telemetry

variable "telemetry_enabled" {
  description = "Whether or not to send telemetry information back to Snowplow Analytics Ltd"
  type        = bool
  default     = true
}

variable "user_provided_id" {
  description = "An optional unique identifier to identify the telemetry events emitted by this stack"
  type        = string
  default     = ""
}
