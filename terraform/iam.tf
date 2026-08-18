# Service account for the VM itself - logging/monitoring only, no compute self-management
resource "google_service_account" "vm_sa" {
  account_id   = "zomboid-vm-sa"
  display_name = "Zomboid VM service account"
  description  = "Minimal-permission SA attached to the Zomboid game server VM"
}

resource "google_project_iam_member" "vm_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "vm_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Service account shared by the start-handler and idle-checker Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "zomboid-function-sa"
  display_name = "Zomboid Cloud Function service account"
  description  = "Used by the Discord start-handler and idle-checker functions to control the VM"
}

# Custom role: only what's needed to start/stop/check the VM -- nothing else
resource "google_project_iam_custom_role" "compute_start_stop" {
  role_id     = "zomboidComputeOperator"
  title       = "Zomboid Compute Operator"
  description = "Start, stop, and check status of the Zomboid VM only -- no disk/image/snapshot management"
  permissions = [
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.get",
    "compute.instances.list",
  ]
}

resource "google_project_iam_member" "function_sa_compute_operator" {
  project = var.project_id
  role    = google_project_iam_custom_role.compute_start_stop.id
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}