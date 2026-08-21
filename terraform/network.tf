# Reference the default VPC network
data "google_compute_network" "default" {
  name = "default"
}

# Reference the default subnet's actual CIDR range -- Cloud Functions using
# Direct VPC egress share this same subnet
data "google_compute_subnetwork" "default" {
  name   = "default"
  region = var.region
}

# Allow inbound Zomboid game traffic (UDP) from anywhere -- this is the actual game connection
resource "google_compute_firewall" "allow_zomboid" {
  name    = "allow-zomboid-game-port"
  network = data.google_compute_network.default.name

  allow {
    protocol = "udp"
    ports    = [tostring(var.zomboid_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["zomboid-server"]

  description = "Allow Project Zomboid game clients to connect"
}

# Allow RCON only from the internal VPC range used by Cloud Functions -- never public
resource "google_compute_firewall" "allow_rcon_internal" {
  name    = "allow-rcon-internal-only"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.rcon_port)]
  }

  source_ranges = [data.google_compute_subnetwork.default.ip_cidr_range]
  target_tags   = ["zomboid-server"]

  description = "Allow RCON only from the default subnet (Cloud Functions use Direct VPC egress into this same subnet)"
}

# Allow SSH only via Identity-Aware Proxy, not an open port to the internet
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google's fixed IAP forwarding range
  target_tags   = ["zomboid-server"]

  description = "Allow SSH only via GCP Identity-Aware Proxy tunnel"
}