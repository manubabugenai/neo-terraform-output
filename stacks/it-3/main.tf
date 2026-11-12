# Terraform Block
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.5"
}

# Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
# Declare exactly these variables, with these names and no others.
# They are set by terraform.tfvars.
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

# Locals for Labels
# Define labels once and reference local.labels.
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
}

# Requirement: 1 BigQuery dataset in us-central1 for monthly reports
# Naming: Adapted from `quantum_<env>_data` to include stack name `it3` and purpose `monthly_reports`
# for uniqueness across stacks, as per naming standards.
resource "google_bigquery_dataset" "it3_monthly_reports_dataset" {
  project                     = var.project_id
  dataset_id                  = "quantum_${var.environment}_it3_monthly_reports"
  friendly_name               = "Quantum IT-3 Monthly Reports Dataset (${var.environment})"
  description                 = "BigQuery dataset for IT-3 stack's monthly reports in ${var.environment} environment."
  location                    = var.region                  # Standard default
  default_table_expiration_ms = 3600000                     # Standard default
  labels                      = local.labels                # Apply standard labels
}
