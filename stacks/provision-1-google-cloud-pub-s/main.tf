# main.tf for provision-1-google-cloud-pub-s

# Terraform and Provider configuration
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

# Requirement: Provision 1 Google Cloud Pub/Sub topic
resource "google_pubsub_topic" "provision1_pubsub_topic" {
  project = var.project_id
  # Naming: quantum-<env>-<stack>-<purpose>
  name    = "quantum-${var.environment}-provision1-pubsub-topic"
  labels  = local.labels
}

# Requirement: with 1 pull subscription and 7 days message retention
resource "google_pubsub_subscription" "provision1_pubsub_subscription" {
  project = var.project_id
  # Naming: quantum-<env>-<stack>-<purpose>
  name  = "quantum-${var.environment}-provision1-pubsub-sub"
  topic = google_pubsub_topic.provision1_pubsub_topic.id

  # Default subscription type is pull, no push_config means it's pull.
  # Default ack_deadline_seconds is 10 seconds, which is acceptable.

  # 7 days message retention (7 * 24 * 60 * 60 seconds)
  message_retention_duration = "604800s"
  labels                     = local.labels
}
