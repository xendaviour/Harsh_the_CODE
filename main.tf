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

########################## VM with Static IP ##########################################

resource "google_compute_address" "static_ip" {
  name   = "new-static-ip"
  region = "asia-south1"
}

resource "google_service_account" "default" {
  account_id   = "terraform-vm-sa"
  display_name = "terraform-gcp-sa VM Instance"
}

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

   metadata = {
    ssh-keys = " "
    # Add a startup script to install Kubernetes and Apache
    metadata_startup_script = <<-EOT
      #!/bin/bash

      # Update and install necessary packages
      apt-get update -y
      apt-get upgrade -y

      # Install Docker (required by Kubernetes)
      apt-get install -y apt-transport-https ca-certificates curl software-properties-common
      curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
      add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
      apt-get update -y
      apt-get install -y docker-ce

      # Enable and start Docker
      systemctl enable docker
      systemctl start docker

      # Install Kubernetes tools (kubectl, kubeadm, kubelet)
      curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
      apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
      apt-get update -y
      apt-get install -y kubeadm kubelet kubectl

      # Mark Kubernetes packages to prevent accidental updates
      apt-mark hold kubeadm kubelet kubectl

      # Install Apache
      apt-get install -y apache2
      systemctl enable apache2
      systemctl start apache2

      # Output a message for debugging
      echo "Startup script executed: Kubernetes and Apache installed" >> /var/log/startup-script.log
    EOT
  }
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
