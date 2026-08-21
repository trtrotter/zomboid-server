resource "google_cloud_run_v2_service" "idle_checker" {
  name     = "zomboid-idle-checker"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.function_sa.email

    containers {
      image = "us-central1-docker.pkg.dev/${var.project_id}/zomboid-functions/idle-checker:latest"

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_ZONE"
        value = var.zone
      }
      env {
        name  = "INSTANCE_NAME"
        value = var.instance_name
      }
      env {
        name  = "RCON_PORT"
        value = tostring(var.rcon_port)
      }

    }

    vpc_access {
      network_interfaces {
        network    = data.google_compute_network.default.name
        subnetwork = data.google_compute_subnetwork.default.name
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }
  }
}

# Only Cloud Scheduler (via function_sa) is allowed to invoke this service --
# not open to the public internet
resource "google_cloud_run_v2_service_iam_member" "scheduler_invoker" {
  location = google_cloud_run_v2_service.idle_checker.location
  name     = google_cloud_run_v2_service.idle_checker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_cloud_run_v2_service" "start_handler" {
  name     = "zomboid-start-handler"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.function_sa.email

    containers {
      image = "us-central1-docker.pkg.dev/${var.project_id}/zomboid-functions/start-handler:latest"

      env {
        name  = "DISCORD_PUBLIC_KEY"
        value = var.discord_public_key
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_ZONE"
        value = var.zone
      }
      env {
        name  = "INSTANCE_NAME"
        value = var.instance_name
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
  }
}

# Discord calls this directly from the internet using its own Ed25519 signature
# scheme -- not Google IAM -- so this must allow unauthenticated invocation.
# Security is enforced in the code itself via signature verification.
resource "google_cloud_run_v2_service_iam_member" "start_handler_public" {
  location = google_cloud_run_v2_service.start_handler.location
  name     = google_cloud_run_v2_service.start_handler.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}