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

locals {
  # Labels: Define them once in a locals block and reference local.labels
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
}

# Requirement: 1 Pub/Sub topic
resource "google_pubsub_topic" "it2_app_events_topic" {
  # Naming: quantum-<env>-<service>
  name    = "quantum-${var.environment}-it2-app-events"
  project = var.project_id

  # Requirement: Message retention: 7 days (604800 seconds)
  message_retention_duration = "604800s"

  # Labels: Apply to every resource that supports a labels argument
  labels = local.labels
}

# Requirement: 1 subscription (pull)
resource "google_pubsub_subscription" "it2_app_events_subscription" {
  # Naming: quantum-<env>-<service>
  name  = "quantum-${var.environment}-it2-app-events-sub"
  topic = google_pubsub_topic.it2_app_events_topic.id
  project = var.project_id

  # Requirement: Message retention: 7 days (604800 seconds)
  message_retention_duration = "604800s"

  # Default: pull delivery type
  ack_deadline_seconds = 10

  # Labels: Apply to every resource that supports a labels argument
  labels = local.labels
}
