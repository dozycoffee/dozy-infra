# VPC, 서브넷, Cloud NAT, 방화벽, Private Service Access.
# 올리고 내리는 스택(stacks/gcp)에서 쓴다. 설계는 docs/system-architecture.md 4절을 따른다.

locals {
  gke_subnet_name = "${var.name}-gke"
  ops_subnet_name = "${var.name}-ops"

  pods_range_name     = "pods"
  services_range_name = "services"

  # 대역이 서로 겹치면 나중에 AWS VPC나 사내망과 연결(피어링)할 수 없고 GKE 생성도 실패한다
  ranges = {
    nodes    = var.gke_nodes_cidr
    pods     = var.pods_cidr
    services = var.services_cidr
    ops      = var.ops_cidr
    psa      = var.psa_cidr
  }
  range_start = {
    for name, cidr in local.ranges :
    name => sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
  }
  range_size = {
    for name, cidr in local.ranges :
    name => pow(2, 32 - tonumber(split("/", cidr)[1]))
  }
  range_names = keys(local.ranges)
  overlaps = flatten([
    for i, a in local.range_names : [
      for j, b in local.range_names : "${a}/${b}"
      if i < j
      && local.range_start[a] < local.range_start[b] + local.range_size[b]
      && local.range_start[b] < local.range_start[a] + local.range_size[a]
    ]
  ])
}

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  lifecycle {
    precondition {
      condition     = length(local.overlaps) == 0
      error_message = "CIDR 대역이 서로 겹친다: ${join(", ", local.overlaps)}"
    }
  }
}

resource "google_compute_subnetwork" "gke" {
  project                  = var.project_id
  name                     = local.gke_subnet_name
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.gke_nodes_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = local.services_range_name
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_subnetwork" "ops" {
  project                  = var.project_id
  name                     = local.ops_subnet_name
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.ops_cidr
  private_ip_google_access = true
}

# 프라이빗 노드는 외부 IP가 없어서 NAT가 없으면 ghcr.io 이미지 pull과 SMTP가 막힌다
resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_address" "nat" {
  count = var.nat_static_ip ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_router_nat" "this" {
  project = var.project_id
  name    = "${var.name}-nat"
  region  = var.region
  router  = google_compute_router.this.name

  nat_ip_allocate_option             = var.nat_static_ip ? "MANUAL_ONLY" : "AUTO_ONLY"
  nat_ips                            = var.nat_static_ip ? google_compute_address.nat[*].self_link : null
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 기본은 수신 거부(암묵적 deny)이고, 아래 두 가지만 연다.
# 파드 사이 통신은 GKE가 자동으로 만드는 규칙이 맡는다.

# IAP TCP 포워딩 대역에서 점검용 VM으로 SSH만 허용한다 (VM에는 외부 IP가 없다)
resource "google_compute_firewall" "iap_ssh" {
  project     = var.project_id
  name        = "${var.name}-allow-iap-ssh"
  network     = google_compute_network.this.id
  direction   = "INGRESS"
  description = "IAP 대역에서 ${var.ops_network_tag} 태그 VM으로 SSH"

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.ops_network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# 구글 로드밸런서의 헬스 체크 대역에서 노드와 파드의 서비스 포트로 들어오는 것을 허용한다
resource "google_compute_firewall" "lb_health_check" {
  project     = var.project_id
  name        = "${var.name}-allow-lb-health-check"
  network     = google_compute_network.this.id
  direction   = "INGRESS"
  description = "로드밸런서 헬스 체크 대역에서 GKE 노드와 파드의 서비스 포트"

  source_ranges      = ["130.211.0.0/22", "35.191.0.0/16"]
  destination_ranges = [var.gke_nodes_cidr, var.pods_cidr]

  allow {
    protocol = "tcp"
    ports    = var.lb_health_check_ports
  }
}

# Private Service Access: Cloud SQL이 프라이빗 IP로 이 VPC에 붙는다 (VPC 피어링)
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(var.psa_cidr, 0)
  prefix_length = tonumber(split("/", var.psa_cidr)[1])
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]

  # 피어링을 쓰는 Cloud SQL이 남아 있으면 연결 삭제가 실패하므로, destroy 때는 연결을 추적에서만 뺀다
  deletion_policy = "ABANDON"
}
