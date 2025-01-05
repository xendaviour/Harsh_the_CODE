provider "google" {
  project     = "harshthecode"
  region      = "asia-south1"
  zone        = "asia-south1-a"
  credentials = "key.json"
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.htc_argo.endpoint}"
  client_certificate     = base64decode(google_container_cluster.htc_argo.master_auth[0].client_certificate)
  client_key             = base64decode(google_container_cluster.htc_argo.master_auth[0].client_key)
  cluster_ca_certificate = base64decode(google_container_cluster.htc_argo.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}
