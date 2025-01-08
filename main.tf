########################## Static IP Address ##########################################

resource "google_compute_address" "static_ip" {
  name   = "new-static-ip"
  region = "asia-south1"
}

########################## Service Account ##########################################

resource "google_service_account" "default" {
  account_id   = "terraform-vm-sa"
  display_name = "Terraform Service Account"
}

########################## Google Kubernetes Engine Cluster ##########################

resource "google_compute_network" "vpc_network" {
  name                    = "vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnetwork" {
  name                     = "subnetwork"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = "asia-south1"
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = true
}

resource "google_container_cluster" "htc_argo" {
  name     = "htc-argo"
  location = "asia-south1-a"

  initial_node_count = 1

  node_config {
    machine_type = "e2-micro"
    disk_size_gb = 10
    disk_type    = "pd-standard"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnetwork.id

  remove_default_node_pool = true

  addons_config {
    http_load_balancing {
      disabled = true
    }
    horizontal_pod_autoscaling {
      disabled = true
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block = "/14"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "cheap_pool" {
  cluster    = google_container_cluster.htc_argo.id
  location   = google_container_cluster.htc_argo.location
  node_count = 1

  node_config {
    machine_type = "e2-small"
    disk_size_gb = 10
    disk_type    = "pd-standard"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    tags = ["no-external-ip"]
  }

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

    type = "ClusterIP"
  }
}

########################## Storage ##########################################

resource "google_storage_bucket" "gcsfirst" {
  name          = "harsh_the_code_bucket"
  location      = "asia-south1"
  public_access_prevention = "enforced"
}

########################## VM Instance ##########################################

resource "google_compute_instance" "confidential_instance" {
  name         = "first-instance"
  zone         = "asia-south1-a"
  machine_type = "e2-micro"

  tags = ["http-server", "ssh-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
      labels = {
        my_label = "value"
      }
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnetwork.id

    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  service_account {
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash

    sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    sudo echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    curl -LO https://dl.k8s.io/release/v1.23.0/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /bin/kubectl
    wget -O helm.tar.gz https://get.helm.sh/helm-v3.5.4-linux-amd64.tar.gz
    tar -zxvf helm.tar.gz
    sudo mv linux-amd64/helm /bin/helm
    sudo apt update -y
    sudo apt install azure-cli -y
    sudo snap install kubelogin -y
    sudo mkdir /home/user/terraform
    sudo chown user:user /home/user/terraform
    EOF
}

########################## Firewall Rules ##########################################

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["ssh-server"]
}

resource "google_compute_firewall" "allow_http_server" {
  name    = "allow-http-server"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8001"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["http-server"]
}

resource "google_compute_firewall" "allow_all_tcp_to_node_group" {
  name    = "allow-all-tcp-to-node-group"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["no-external-ip"]
}

resource "google_compute_firewall" "allow_all_udp_to_node_group" {
  name    = "allow-all-udp-to-node-group"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "udp"
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["no-external-ip"]
}

resource "google_compute_firewall" "allow_all_sctp_to_node_group" {
  name    = "allow-all-sctp-to-node-group"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "sctp"
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["no-external-ip"]
}

resource "google_compute_firewall" "allow_egress" {
  name    = "allow-egress"
  network = google_compute_network.vpc_network.name

  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
}

########################## End of Configuration ##############################
