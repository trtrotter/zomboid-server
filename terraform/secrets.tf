resource "random_password" "rcon_password" {
  length  = 24
  special = false # simple to avoid edge cases with the .ini file parser
}

resource "google_secret_manager_secret" "rcon_password" {
  secret_id = "zomboid-rcon-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "rcon_password" {
  secret      = google_secret_manager_secret.rcon_password.id
  secret_data = random_password.rcon_password.result
}

resource "google_secret_manager_secret_iam_member" "vm_sa_rcon_accessor" {
  secret_id = google_secret_manager_secret.rcon_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret" "admin_password" {
  secret_id = "zomboid-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "vm_sa_admin_accessor" {
  secret_id = google_secret_manager_secret.admin_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_secret_manager_secret" "server_password" {
  secret_id = "zomboid-server-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "vm_sa_server_password_accessor" {
  secret_id = google_secret_manager_secret.server_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_sa.email}"
}