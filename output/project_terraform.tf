# Terraform block for required version and providers
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Standard variables as per Quantum standards
variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources into."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone to deploy resources into."
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev"
}

# Local values for standard labels and common prefixes
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
  company_prefix = "quantum"
  project_env    = "${local.company_prefix}-${var.environment}"
}

# --- Requirement: Create a Cloud Storage bucket for application file uploads ---

# Random ID for unique bucket suffix as per naming standards
resource "random_id" "bucket_suffix" {
  byte_length = 4 # Generates 8 hex characters
}

resource "google_storage_bucket" "app_uploads" {
  name                        = "${local.project_env}-app-uploads-${random_id.bucket_suffix.hex}"
  location                    = "US"                           # Standard default
  uniform_bucket_level_access = true                           # Standard default
  public_access_prevention    = "enforced"                     # Standard default
  force_destroy               = false                          # Standard default
  labels                      = local.labels                   # Apply standard labels

  project = var.project_id
}

# --- Requirement: Create a VPC with one subnet and a firewall rule allowing HTTP/HTTPS inbound ---

resource "google_compute_network" "vpc_network" {
  name                    = "vpc-${local.project_env}"         # Naming standard
  auto_create_subnetworks = false                              # Manually create subnet for better control
  routing_mode            = "REGIONAL"
  labels                  = local.labels                       # Apply standard labels

  project = var.project_id
}

resource "google_compute_subnetwork" "nodeapi_subnet" {
  name          = "subnet-${local.project_env}-nodeapi"        # Naming standard
  ip_cidr_range = "10.0.0.0/20"                                # Example CIDR range
  region        = var.region
  network       = google_compute_network.vpc_network.id
  labels        = local.labels                                 # Apply standard labels

  project = var.project_id
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "fw-${local.project_env}-allow-http-https"       # Naming standard
  network = google_compute_network.vpc_network.name
  project = var.project_id
  labels  = local.labels                                     # Apply standard labels

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]                                # Standard allows this for HTTP/HTTPS public web traffic
  target_tags   = ["http-https-server"]                        # Apply to instances that need this rule
}

# --- Requirement: Configure a service account for the VM with least-privilege access to the bucket ---

resource "google_service_account" "nodeapi_sa" {
  account_id   = "sa-${local.project_env}-nodeapi"             # Naming standard (max 30 chars)
  display_name = "${local.company_prefix} ${var.environment} Node API Service Account"
  project      = var.project_id
  labels       = local.labels                                  # Apply standard labels
}

# Least privilege: Grant object user role on the specific bucket
resource "google_storage_bucket_iam_member" "nodeapi_bucket_access" {
  bucket = google_storage_bucket.app_uploads.name
  role   = "roles/storage.objectUser"                          # Least privilege for object read/write/delete
  member = "serviceAccount:${google_service_account.nodeapi_sa.email}"
}

# --- Requirement: Provision one Compute Engine VM (e2-small, us-central1) to host a small Node.js API ---

resource "google_compute_instance" "nodeapi_vm" {
  name         = "${local.project_env}-nodeapi-01"             # Naming standard
  machine_type = "e2-small"                                    # Requirement overrides standard default
  zone         = var.zone
  project      = var.project_id
  labels       = local.labels                                  # Apply standard labels

  # Boot disk from debian-cloud/debian-12, 20GB (standard defaults)
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.nodeapi_subnet.name
    # External IP is required because the firewall rule allows public HTTP/HTTPS traffic,
    # justifying "unless required" clause in standards.
    access_config {
      # Ephemeral IP
    }
  }

  service_account {
    email  = google_service_account.nodeapi_sa.email
    scopes = ["https://www.googleapis.com/auth/devstorage.read_write"] # Least privilege scope for GCS access
  }

  tags = ["http-https-server"]                                 # Associate with the firewall rule
}
