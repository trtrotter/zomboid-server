# Persistent disk for world saves -- separate from the boot disk so it
# survives VM recreation (necessary if the machin_type or image needs to be changed)
resource "google_compute_disk" "zomboid_data" {
  name = "zomboid-data-disk"
  type = "pd-standard"
  zone = var.zone
  size = var.data_disk_size_gb
}

resource "google_compute_instance" "zomboid_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["zomboid-server"] # matches target_tags in network.tf firewall rules

  metadata = {
    rcon-port    = var.rcon_port
    server-name  = var.server_name
    dns-hostname = var.dns_hostname
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.zomboid_data.self_link
    device_name = "zomboid-data-disk"
  }

  network_interface {
    network = data.google_compute_network.default.name

    access_config {
      # Empty block = ephemeral external IP, reassigned on every start
      # (intentional -- this is what our Cloudflare Dynamic DNS step updates)
    }
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  # Spot instance: reclaimable by GCP with 30 seconds' notice. Automatic_restart = false since Terraform/Discord
  # bot controls the lifecycle, not GCP's own restart behavior.
  scheduling {
    provisioning_model  = "SPOT"
    preemptible         = true
    automatic_restart   = false
  }

  metadata_startup_script = file("${path.module}/startup.sh")

  allow_stopping_for_update = true
}
