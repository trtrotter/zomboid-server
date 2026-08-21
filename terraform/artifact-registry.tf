resource "google_artifact_registry_repository" "zomboid_functions" {
  location      = var.region
  repository_id = "zomboid-functions"
  format        = "DOCKER"
  description   = "Container images for the Zomboid idle-checker and Discord start-handler"
}