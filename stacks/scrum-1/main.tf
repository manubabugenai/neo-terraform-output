# main.tf for scrum-1 stack

# Terraform and Provider Block
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

provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region for resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources."
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev" # This will be overridden by terraform.tfvars for staging
}

# Locals Block for Labels
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
}

# Requirement: Create a VPC with one subnet and a firewall rule allowing HTTP/HTTPS inbound

# VPC Network
resource "google_compute_network" "scrum1_vpc" {
  name                    = "vpc-quantum-${var.environment}-scrum1"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Subnet
resource "google_compute_subnetwork" "scrum1_subnet_api" {
  name          = "subnet-quantum-${var.environment}-scrum1-api"
  project       = var.project_id
  ip_cidr_range = "10.10.0.0/20"
  region        = var.region
  network       = google_compute_network.scrum1_vpc.id
}

# Firewall Rule for HTTP/HTTPS inbound
resource "google_compute_firewall" "scrum1_fw_http_https" {
  name    = "fw-quantum-${var.environment}-scrum1-http-https"
  project = var.project_id
  network = google_compute_network.scrum1_vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"] # Required for public web traffic
  target_tags   = ["scrum1-api"] # Tag for the VM
}

# Requirement: Create a Cloud Storage bucket for application file uploads

# Random ID for bucket suffix
resource "random_id" "bucket_suffix" {
  byte_length = 4 # Generates 8 hex characters
}

# Cloud Storage Bucket
resource "google_storage_bucket" "scrum1_uploads_bucket" {
  name                        = "quantum-${var.environment}-scrum1-uploads-${random_id.bucket_suffix.hex}"
  project                     = var.project_id
  location                    = "US"                       # Standard default
  uniform_bucket_level_access = true                       # Standard default
  public_access_prevention    = "enforced"                 # Standard default
  force_destroy               = false                      # Standard default

  labels = local.labels
}

# Requirement: Configure a service account for the VM with least-privilege access to the bucket

# Service Account for the VM
resource "google_service_account" "scrum1_api_sa" {
  account_id   = "sa-quantum-${var.environment}-scrum1-api" # Max 30 chars: sa-quantum-staging-scrum1-api (29 chars)
  display_name = "scrum-1 API Service Account"
  project      = var.project_id
}

# IAM binding for the service account to the bucket
resource "google_storage_bucket_iam_member" "scrum1_bucket_iam" {
  bucket = google_storage_bucket.scrum1_uploads_bucket.name
  role   = "roles/storage.objectAdmin" # Least privilege for file uploads
  member = "serviceAccount:${google_service_account.scrum1_api_sa.email}"
}

# Requirement: Provision one Compute Engine VM (e2-small, us-central1) to host a small Node.js API

# Compute Engine VM Instance
resource "google_compute_instance" "scrum1_api_vm" {
  name         = "quantum-${var.environment}-scrum1-api-01"
  project      = var.project_id
  machine_type = "e2-small" # Requirement overrides default e2-medium
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20 # Standard default
    }
  }

  network_interface {
    network    = google_compute_network.scrum1_vpc.id
    subnetwork = google_compute_subnetwork.scrum1_subnet_api.id
    # No external IP as per standard unless required, and it's not required here.
  }

  service_account {
    email  = google_service_account.scrum1_api_sa.email
    scopes = ["cloud-platform"] # Required for service account to function, even with specific IAM roles.
                                # The IAM role on the bucket is the primary control for least privilege.
  }

  tags = ["scrum1-api"] # For firewall rule targeting

  labels = local.labels
}
