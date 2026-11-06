terraform {
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
  required_version = ">= 1.5"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Declare exactly these variables, with these names and no others
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

# Supporting resource: random_id for unique bucket suffix
resource "random_id" "it1_bucket_suffix" {
  byte_length = 4
}

# Requirement: 1 Cloud Storage bucket for internal PDFs
resource "google_storage_bucket" "it1_internal_docs_bucket" {
  # Naming: quantum-<env>-<purpose>-<unique-suffix>
  name          = "quantum-${var.environment}-it1-internal-docs-${random_id.it1_bucket_suffix.hex}"
  project       = var.project_id
  # Requirement: regional, us-central1 (default region)
  location      = var.region
  # Standard: uniform_bucket_level_access = true
  uniform_bucket_level_access = true
  # Standard: public_access_prevention = "enforced"
  public_access_prevention = "enforced"
  # Standard: force_destroy = false
  force_destroy = false

  # Requirement: Versioning enabled
  versioning {
    enabled = true
  }

  # Standard: Apply labels
  labels = local.labels
}
