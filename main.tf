########################## Google Kubernetes Engine Cluster ##########################

resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork" {
  name                    = "subnetwork"
  ip_cidr_range           = "10.0.0.0/16"
  region                  = "asia-south1"
  network                 = google_compute_network.vpc_network.id
  private_ip_google_access = true  # Enable Private Google Access
}

resource "google_container_cluster" "htc_argo" {
  name     = "htc-argo"
  location = "asia-south1-a"

  # Use a single node to minimize costs
  initial_node_count = 1

  # Node configuration
  node_config {
    # Cheapest machine type
    machine_type = "e2-micro"

    # Minimum disk size (10 GB is the smallest allowed size)
    disk_size_gb = 10

    # Use standard persistent disk for lower cost
    disk_type = "pd-standard"

    # Use the default service account
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Use the VPC network and subnetwork
  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnetwork.id

  # Disable various addons to reduce costs
  remove_default_node_pool = true

  # Enable only essential features under the addons_config block
  addons_config {
    http_load_balancing {
      disabled = true
    }
    horizontal_pod_autoscaling {
      disabled = true
    }
  }

  # Enable private nodes
  private_cluster_config {
    enable_private_nodes    = true  # Equivalent to --enable-private-nodes
    enable_private_endpoint = false
  }

  # Enable IP allocation policy
  ip_allocation_policy {
    cluster_ipv4_cidr_block = "/14"
  }

  # Set deletion protection to false
  deletion_protection = false
}

resource "google_container_node_pool" "cheap_pool" {
  cluster    = google_container_cluster.htc_argo.id
  location   = google_container_cluster.htc_argo.location
  node_count = 1 # Keep node count minimal

  node_config {
    machine_type = "e2-micro" # Smallest and cheapest machine type
    disk_size_gb = 10         # Minimum disk size
    disk_type    = "pd-standard"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # Ensure no external IP is assigned to node
    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    tags = ["no-external-ip"]
  }

  # Prevent external IP assignment to nodes
  management {
    auto_upgrade = true
    auto_repair  = true
  }
}

########################## Kubernetes Resources ##########################################

resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx-deployment"
    namespace = "default"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:1.14.2"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx" {
  metadata {
    name      = "nginx-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"  # Use ClusterIP to avoid external IP cost
  }
}

########################## Storage ##########################################

resource "google_storage_bucket" "gcsfirst" {
  name          = "harsh_the_code_bucket"
  location      = "asia-south1"
  
  public_access_prevention = "enforced"
}
########################## VM ###############################################

resource "google_service_account" "default" {
  account_id   = "terraform-vm-sa"
  display_name = "terraform-gcp-sa VM Instance"
}

# VM instance configuration with static external IP
resource "google_compute_instance" "confidential_instance" {
  name         = "first-instance"
  zone         = "asia-south1-a"
  machine_type = "e2-micro"

  tags = ["http-server", "ssh-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10 # Disk size in GB (minimum for Persistent Disk)
      type  = "pd-standard" # Standard Persistent Disk (cheapest option)
      labels = {
        my_label = "value"
      }
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnetwork.id

    # Use the provided static external IP for SSH access
    access_config {
      nat_ip = "34.93.86.66"
    }
  }

  service_account {
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }

  # Add metadata to allow SSH keys
  metadata = {
    ssh-keys = " "
      }
}

# Data source to get authenticated user's email via OpenID
data "google_client_openid_userinfo" "me" {}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name  # Use your network if different

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  # Allow SSH traffic from anywhere

  target_tags = ["ssh-server"]  # Ensure your VM is tagged with "ssh-server"
}

resource "google_compute_firewall" "allow_http_server" {
  name    = "allow-http-server"
  network = google_compute_network.vpc_network.name  # Use your network if different

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8001"]
  }

  source_ranges = ["0.0.0.0/0"]  # Allow traffic from anywhere

  target_tags = ["http-server"]  # You can tag your VM with "http-server"
}

# New Firewall Rules to Allow All Connections to Node Group

resource "google_compute_firewall" "allow_all_tcp_to_node_group" {
  name    = "allow-all-tcp-to-node-group"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
  }

  source_ranges = ["0.0.0.0/0"]  # Allow all TCP traffic from anywhere

  target_tags = ["no-external-ip"]  # Ensure your nodes are tagged with "no-external-ip"
}

resource "google_compute_firewall" "allow_all_udp_to_node_group" {
  name    = "allow-all-udp-to-node-group"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "udp"
  }

  source_ranges = ["0.0.0.0/0"]  # Allow all UDP traffic from anywhere

  target_tags = ["no-external-ip"]  # Ensure your nodes are tagged with "no-external-ip"
}

resource "google_compute_firewall" "allow_all_sctp_to_node_group" {
  name    = "allow-all-sctp-to-node-group"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "sctp"
  }

  source_ranges = ["0.0.0.0/0"]  # Allow all SCTP traffic from anywhere

  target_tags = ["no-external-ip"]  # Ensure your nodes are tagged with "no-external-ip"
}

########################## End of Configuration ##############################
