terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.5"
}

# Declare exactly these variables as per Quantum Terraform standards
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

# Requirement: 1 BigQuery dataset in us-central1
resource "google_bigquery_dataset" "it3_monthly_reports_dataset" {
  # Naming: quantum_<env>_data, including stack name 'it3' for uniqueness
  dataset_id = "quantum_${var.environment}_it3_data"
  project    = var.project_id
  # Resource default: location = var.region (us-central1 from requirements/default)
  location = var.region
  # Resource default: default_table_expiration_ms = 3600000
  default_table_expiration_ms = 3600000
  description                 = "BigQuery dataset for monthly reports for IT-3 stack."
  # Labels: Apply to every resource that supports a labels argument
  labels = local.labels
}
