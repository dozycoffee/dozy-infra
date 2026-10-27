# GKE Autopilot. 프라이빗 노드이고, 컨트롤 플레인은 승인된 대역(내 IP)에서만 접근한다.
# Workload Identity는 Autopilot에서 기본으로 켜져 있다(<프로젝트>.svc.id.goog).

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region

  enable_autopilot    = true
  deletion_protection = var.deletion_protection

  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs

      content {
        cidr_block   = cidr_blocks.value
        display_name = "승인된 접근 ${cidr_blocks.key + 1}"
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  dynamic "cluster_autoscaling" {
    for_each = var.node_service_account_email == null ? [] : [var.node_service_account_email]

    content {
      auto_provisioning_defaults {
        service_account = cluster_autoscaling.value
        oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
      }
    }
  }
}
