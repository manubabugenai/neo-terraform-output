# main.tf for stack it-3

# Terraform and Provider Configuration
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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
  default     = "dev"
}

# Locals for common configurations
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
  # Naming: quantum_<env>_<stack>_<purpose>_data
  dataset_id                  = "quantum_${var.environment}_it3_reports_data"
  project                     = var.project_id
  location                    = var.region # Defaults to us-central1 as per standards and requirement
  default_table_expiration_ms = 3600000    # From resource defaults

  labels = local.labels
}
