terraform {
    backend "gcs" {
        bucket = "zomboid-server-prod-tfstate"
        prefix = "terraform/state"
    }
}