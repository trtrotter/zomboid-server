resource "google_cloud_scheduler_job" "idle_checker_trigger" {
  name      = "zomboid-idle-checker-trigger"
  schedule  = "*/5 * * * *"
  time_zone = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloud_run_v2_service.idle_checker.uri

    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }
}