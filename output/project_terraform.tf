# Required Terraform and providers
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Declare exactly these variables
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

# Define labels once in a locals block
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
}

# Supporting resource: Random ID for Cloud Storage bucket suffix
resource "random_id" "bucket_suffix" {
  byte_length = 4
  keepers = {
    environment = var.environment
  }
}

# Requirement 3: Create a VPC
resource "google_compute_network" "app_vpc" {
  project                 = var.project_id
  name                    = "vpc-quantum-${var.environment}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  # Labels are not supported on google_compute_network
}

# Requirement 3: Create one subnet
resource "google_compute_subnetwork" "app_subnet" {
  project       = var.project_id
  name          = "subnet-quantum-${var.environment}-app-network"
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.app_vpc.id
  # Labels are not supported on google_compute_subnetwork
}

# Requirement 3: Create a firewall rule allowing HTTP/HTTPS inbound
resource "google_compute_firewall" "allow_http_https" {
  project     = var.project_id
  name        = "fw-quantum-${var.environment}-allow-http-https"
  network     = google_compute_network.app_vpc.id
  description = "Allow HTTP and HTTPS inbound traffic to Node.js API instances."

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nodejs-api"] # VM will have this tag
  # Labels are not supported on google_compute_firewall
}

# Requirement 2: Create a Cloud Storage bucket for application file uploads
resource "google_storage_bucket" "app_uploads_bucket" {
  project                       = var.project_id
  name                          = "quantum-${var.environment}-app-uploads-${random_id.bucket_suffix.hex}"
  location                      = "US"
  uniform_bucket_level_access   = true
  public_access_prevention      = "enforced"
  force_destroy                 = false
  labels                        = local.labels
  # Default storage class is STANDARD, which is fine.
}

# Requirement 4: Configure a service account for the VM
resource "google_service_account" "nodejs_api_sa" {
  project      = var.project_id
  account_id   = "sa-quantum-${var.environment}-nodejs-api"
  display_name = "Service Account for Node.js API VM in ${var.environment}"
  # Labels are not supported on google_service_account
}

# Requirement 4: Grant least-privilege access to the bucket
resource "google_storage_bucket_iam_member" "nodejs_api_bucket_access" {
  bucket = google_storage_bucket.app_uploads_bucket.name
  role   = "roles/storage.objectUser" # Allows uploading, downloading, deleting objects
  member = "serviceAccount:${google_service_account.nodejs_api_sa.email}"
  # Labels are not supported on google_storage_bucket_iam_member
}

# Requirement 1: Provision one Compute Engine VM
resource "google_compute_instance" "nodejs_api_vm" {
  project      = var.project_id
  name         = "quantum-${var.environment}-nodejs-api-01"
  machine_type = "e2-small" # Overrides default e2-medium as per requirement
  zone         = var.zone
  labels       = local.labels
  tags         = ["nodejs-api"] # For firewall rule targeting

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20 # GB, as per default
    }
  }

  network_interface {
    network    = google_compute_network.app_vpc.id
    subnetwork = google_compute_subnetwork.app_subnet.id
    # No external IP unless required, as per security standard
  }

  service_account {
    email  = google_service_account.nodejs_api_sa.email
    scopes = ["cloud-platform"] # Required for service account to function, IAM roles provide fine-grained access
  }
}
