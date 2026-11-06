# main.tf for it-2 stack

# --- Terraform and Provider Configuration ---
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
  zone    = var.zone
}

# --- Variables ---
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

# --- Locals ---
locals {
  labels = {
    environment = var.environment
    owner       = "quantum-neo"
    company     = "quantum"
    managed_by  = "terraform"
    project     = "quantum-infra-neo"
  }
  # Network tag for the web app VM, used by firewall rules
  webapp_network_tag = "it2-webapp"
}

# --- VPC with one subnet ---
resource "google_compute_network" "it2_vpc" {
  name                    = "vpc-quantum-${var.environment}-it2"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "it2_subnet_webapp" {
  name          = "subnet-quantum-${var.environment}-it2-webapp"
  project       = var.project_id
  ip_cidr_range = "10.10.0.0/20" # Example CIDR, adjust if needed
  region        = var.region
  network       = google_compute_network.it2_vpc.self_link
}

# --- Cloud Storage bucket for uploads (regional, public access prevented) ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "it2_uploads_bucket" {
  name                        = "quantum-${var.environment}-it2-uploads-${random_id.bucket_suffix.hex}"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false # Standard default
  labels                      = local.labels
}

# --- Compute Engine VM (e2-medium, Debian 12, 50 GB disk) in us-central1, no external IP ---
# Dedicated Service Account for the VM
resource "google_service_account" "it2_webapp_sa" {
  account_id   = "sa-quantum-${var.environment}-it2-webapp" # Max 30 chars
  display_name = "Service Account for IT-2 Web App VM"
  project      = var.project_id
}

resource "google_compute_instance" "it2_webapp_vm" {
  name         = "quantum-${var.environment}-it2-webapp-01"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-medium" # Requirement matches standard default

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50 # Requirement: 50 GB disk (overrides default 20 GB)
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.it2_subnet_webapp.self_link
    # No access_config block means no external IP, as per standard and requirement
  }

  # Example startup script to install Nginx for load balancer testing
  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y nginx
    echo "Hello from IT-2 Web App VM!" | sudo tee /var/www/html/index.nginx-debian.html
    sudo systemctl start nginx
    sudo systemctl enable nginx
  EOF

  service_account {
    email  = google_service_account.it2_webapp_sa.email
    scopes = ["cloud-platform"] # General scope for basic VM operations (e.g., logging)
  }

  tags   = [local.webapp_network_tag] # Used by firewall rules
  labels = local.labels
}

# --- HTTP(S) load balancer in front of the VM ---
# Unmanaged Instance Group for the single VM
resource "google_compute_instance_group" "it2_webapp_ig" {
  name        = "quantum-${var.environment}-it2-webapp-ig"
  project     = var.project_id
  zone        = var.zone
  description = "Instance group for IT-2 web app VM"
  instances   = [google_compute_instance.it2_webapp_vm.self_link]
  # Labels not supported directly on instance_group resource
}

# Health Check for the backend service
resource "google_compute_health_check" "it2_webapp_hc" {
  name                = "hc-quantum-${var.environment}-it2-webapp"
  project             = var.project_id
  check_interval_sec  = 5
  timeout_sec         = 5
  unhealthy_threshold = 2
  healthy_threshold   = 2
  request_path        = "/"
  port                = 80
  protocol            = "HTTP"
  # Labels not supported
}

# Backend Service for the load balancer
resource "google_compute_backend_service" "it2_webapp_bs" {
  name                  = "bs-quantum-${var.environment}-it2-webapp"
  project               = var.project_id
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.it2_webapp_hc.self_link]
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL"

  backend {
    group = google_compute_instance_group.it2_webapp_ig.self_link
  }
  labels = local.labels
}

# URL Map to direct traffic to the backend service
resource "google_compute_url_map" "it2_webapp_url_map" {
  name            = "urlmap-quantum-${var.environment}-it2-webapp"
  project         = var.project_id
  default_service = google_compute_backend_service.it2_webapp_bs.self_link
  # Labels not supported
}

# Target HTTP Proxy to route requests to the URL map
resource "google_compute_target_http_proxy" "it2_webapp_http_proxy" {
  name    = "proxy-quantum-${var.environment}-it2-webapp"
  project = var.project_id
  url_map = google_compute_url_map.it2_webapp_url_map.self_link
  # Labels not supported
}

# Global Forwarding Rule to expose the load balancer publicly
resource "google_compute_global_forwarding_rule" "it2_webapp_forwarding_rule" {
  name                  = "fr-quantum-${var.environment}-it2-webapp"
  project               = var.project_id
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.it2_webapp_http_proxy.self_link
  load_balancing_scheme = "EXTERNAL"
  labels                = local.labels
}

# --- Firewall allows only the load balancer to reach the VM ---
resource "google_compute_firewall" "it2_fw_allow_lb_http" {
  name    = "fw-quantum-${var.environment}-it2-webapp-lb"
  project = var.project_id
  network = google_compute_network.it2_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = [
    "130.211.0.0/22", # Google Cloud Load Balancer
    "35.191.0.0/16"   # Google Cloud Health Checks
  ]
  target_tags = [local.webapp_network_tag]
  # Labels not supported
}

# --- Cloud SQL for PostgreSQL (db-f1-micro, 10 GB, private IP only) ---
# Enable Service Networking API for private IP connections
resource "google_project_service" "servicenetworking_api" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false # Keep API enabled even if Terraform resource is destroyed
}

# Allocate a private IP range for Cloud SQL service networking
resource "google_compute_address" "it2_sql_private_ip_alloc" {
  name          = "quantum-${var.environment}-it2-sql-private-ip-alloc"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20 # /20 is a common size for service networking
  network       = google_compute_network.it2_vpc.self_link
}

# Create the private connection to Google's service producer network
resource "google_service_networking_connection" "it2_sql_private_vpc_connection" {
  network                 = google_compute_network.it2_vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_address.it2_sql_private_ip_alloc.name]
  depends_on              = [google_project_service.servicenetworking_api]
}

resource "google_sql_database_instance" "it2_sql_db" {
  name             = "quantum-${var.environment}-it2-db"
  project          = var.project_id
  database_version = "POSTGRES_15" # Standard default
  region           = var.region
  settings {
    tier              = "db-f1-micro" # Requirement: db-f1-micro
    disk_size         = 10            # Requirement: 10 GB
    disk_type         = "PD_SSD"      # Default for performance
    availability_type = "ZONAL"       # Standard default
    backup_configuration {
      enabled            = true
      binary_log_enabled = true # Required for point-in-time recovery
      start_time         = "03:00"
    }
    ip_configuration {
      ipv4_enabled    = false # Requirement: private IP only (standard default)
      private_network = google_compute_network.it2_vpc.self_link
    }
  }
  deletion_protection = true # Standard default
  depends_on          = [google_service_networking_connection.it2_sql_private_vpc_connection]
  labels              = local.labels
}

# Optional: Create a default database within the instance
resource "google_sql_database" "it2_sql_default_db" {
  name      = "it2_app_db"
  instance  = google_sql_database_instance.it2_sql_db.name
  project   = var.project_id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Optional: Create a user for the database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*()_+-="
}

resource "google_sql_user" "it2_sql_user" {
  name     = "app_user"
  instance = google_sql_database_instance.it2_sql_db.name
  project  = var.project_id
  host     = "%" # Allow connections from any host within the private network
  password = random_password.db_password.result
}
