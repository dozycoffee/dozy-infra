# 실제 GCP를 부르지 않고 mock provider로 네트워크 구성을 검증한다.

mock_provider "google" {
  mock_resource "google_compute_network" {
    defaults = {
      id        = "projects/test-project/global/networks/dozy-vpc"
      self_link = "https://www.googleapis.com/compute/v1/projects/test-project/global/networks/dozy-vpc"
    }
  }

  mock_resource "google_compute_subnetwork" {
    defaults = {
      self_link = "https://www.googleapis.com/compute/v1/projects/test-project/regions/asia-northeast3/subnetworks/dozy-gke"
    }
  }

  mock_resource "google_compute_address" {
    defaults = {
      self_link = "https://www.googleapis.com/compute/v1/projects/test-project/regions/asia-northeast3/addresses/dozy-nat-ip"
      address   = "203.0.113.10"
    }
  }

  mock_resource "google_service_networking_connection" {
    defaults = {
      id = "projects/test-project/global/networks/dozy-vpc:servicenetworking.googleapis.com"
    }
  }
}

variables {
  project_id = "test-project"
}

run "vpc_is_custom_mode" {
  command = apply

  assert {
    condition     = google_compute_network.this.name == "dozy-vpc"
    error_message = "VPC 이름은 <name>-vpc여야 한다."
  }

  assert {
    condition     = google_compute_network.this.auto_create_subnetworks == false
    error_message = "VPC는 custom 모드(자동 서브넷 없음)여야 한다."
  }
}

run "gke_subnet_has_pod_and_service_ranges" {
  command = apply

  assert {
    condition     = google_compute_subnetwork.gke.ip_cidr_range == "10.10.0.0/22"
    error_message = "GKE 노드 서브넷 대역이 설계와 같아야 한다."
  }

  assert {
    condition     = google_compute_subnetwork.gke.private_ip_google_access == true
    error_message = "NAT 없이 구글 API로 가도록 Private Google Access를 켜야 한다."
  }

  assert {
    condition = (
      google_compute_subnetwork.gke.secondary_ip_range[0].range_name == "pods" &&
      google_compute_subnetwork.gke.secondary_ip_range[0].ip_cidr_range == "10.20.0.0/16"
    )
    error_message = "파드 보조 대역이 pods / 10.20.0.0/16이어야 한다."
  }

  assert {
    condition = (
      google_compute_subnetwork.gke.secondary_ip_range[1].range_name == "services" &&
      google_compute_subnetwork.gke.secondary_ip_range[1].ip_cidr_range == "10.30.0.0/20"
    )
    error_message = "서비스 보조 대역이 services / 10.30.0.0/20이어야 한다."
  }

  assert {
    condition     = output.pods_range_name == "pods" && output.services_range_name == "services"
    error_message = "GKE가 쓸 보조 대역 이름을 출력해야 한다."
  }
}

run "ops_subnet" {
  command = apply

  assert {
    condition     = google_compute_subnetwork.ops.ip_cidr_range == "10.10.8.0/24" && google_compute_subnetwork.ops.name == "dozy-ops"
    error_message = "ops 서브넷 이름과 대역이 설계와 같아야 한다."
  }
}

run "nat_uses_static_ip_by_default" {
  command = apply

  assert {
    condition     = google_compute_router_nat.this.nat_ip_allocate_option == "MANUAL_ONLY"
    error_message = "기본은 고정 외부 IP를 쓰는 MANUAL_ONLY여야 한다."
  }

  assert {
    condition     = length(google_compute_address.nat) == 1 && length(output.nat_ip_addresses) == 1
    error_message = "고정 IP를 하나 예약하고 출력해야 한다."
  }

  assert {
    condition     = google_compute_router_nat.this.source_subnetwork_ip_ranges_to_nat == "ALL_SUBNETWORKS_ALL_IP_RANGES"
    error_message = "노드와 파드 대역 모두 NAT를 거쳐야 한다."
  }
}

run "nat_auto_allocates_when_static_ip_disabled" {
  command = apply

  variables {
    nat_static_ip = false
  }

  assert {
    condition     = google_compute_router_nat.this.nat_ip_allocate_option == "AUTO_ONLY"
    error_message = "고정 IP를 끄면 AUTO_ONLY여야 한다."
  }

  assert {
    condition     = length(google_compute_address.nat) == 0 && length(output.nat_ip_addresses) == 0
    error_message = "고정 IP를 끄면 주소를 예약하지 않아야 한다."
  }
}

run "iap_ssh_firewall_only_allows_ssh_from_iap" {
  command = apply

  assert {
    condition     = google_compute_firewall.iap_ssh.source_ranges == toset(["35.235.240.0/20"])
    error_message = "SSH는 IAP 대역에서만 허용해야 한다."
  }

  assert {
    condition     = google_compute_firewall.iap_ssh.target_tags == toset(["dozy-ops"])
    error_message = "SSH는 ops 태그가 붙은 VM으로만 허용해야 한다."
  }

  assert {
    condition     = one(google_compute_firewall.iap_ssh.allow).protocol == "tcp" && one(google_compute_firewall.iap_ssh.allow).ports == tolist(["22"])
    error_message = "SSH(tcp 22)만 허용해야 한다."
  }

  assert {
    condition     = google_compute_firewall.iap_ssh.direction == "INGRESS"
    error_message = "수신 규칙이어야 한다."
  }
}

run "lb_health_check_firewall" {
  command = apply

  assert {
    condition     = google_compute_firewall.lb_health_check.source_ranges == toset(["130.211.0.0/22", "35.191.0.0/16"])
    error_message = "구글 로드밸런서 헬스 체크 대역만 허용해야 한다."
  }

  assert {
    condition     = one(google_compute_firewall.lb_health_check.allow).ports == tolist(["8080", "8082"])
    error_message = "서비스 포트 8080, 8082만 허용해야 한다."
  }

  assert {
    condition     = google_compute_firewall.lb_health_check.destination_ranges == toset(["10.10.0.0/22", "10.20.0.0/16"])
    error_message = "노드와 파드 대역으로 들어오는 트래픽만 대상이어야 한다."
  }
}

run "health_check_ports_are_configurable" {
  command = apply

  variables {
    lb_health_check_ports = ["9000"]
  }

  assert {
    condition     = one(google_compute_firewall.lb_health_check.allow).ports == tolist(["9000"])
    error_message = "헬스 체크 포트를 바꿀 수 있어야 한다."
  }
}

run "private_service_access" {
  command = apply

  assert {
    condition = (
      google_compute_global_address.psa.address == "10.40.0.0" &&
      google_compute_global_address.psa.prefix_length == 20 &&
      google_compute_global_address.psa.purpose == "VPC_PEERING"
    )
    error_message = "PSA 예약 대역이 10.40.0.0/20 VPC_PEERING이어야 한다."
  }

  assert {
    condition     = google_service_networking_connection.psa.service == "servicenetworking.googleapis.com"
    error_message = "servicenetworking 서비스로 연결해야 한다."
  }

  assert {
    condition     = google_service_networking_connection.psa.reserved_peering_ranges == tolist(["dozy-psa"])
    error_message = "예약한 대역을 연결에 써야 한다."
  }

  assert {
    condition     = google_service_networking_connection.psa.deletion_policy == "ABANDON"
    error_message = "destroy 때 연결 삭제 실패를 피하도록 ABANDON이어야 한다."
  }

  assert {
    condition     = output.psa_connection_id != ""
    error_message = "Cloud SQL이 기다릴 수 있게 연결 ID를 출력해야 한다."
  }
}

run "name_prefix_changes_resource_names" {
  command = apply

  variables {
    name = "test"
  }

  assert {
    condition = (
      google_compute_network.this.name == "test-vpc" &&
      google_compute_subnetwork.gke.name == "test-gke" &&
      google_compute_router.this.name == "test-router" &&
      google_compute_router_nat.this.name == "test-nat"
    )
    error_message = "이름 접두사가 모든 자원 이름에 적용되어야 한다."
  }
}

run "overlapping_ranges_are_rejected" {
  command = plan

  variables {
    pods_cidr = "10.10.0.0/16"
  }

  expect_failures = [google_compute_network.this]
}

run "psa_overlapping_nodes_is_rejected" {
  command = plan

  variables {
    psa_cidr = "10.10.0.0/20"
  }

  expect_failures = [google_compute_network.this]
}

run "adjacent_ranges_are_allowed" {
  command = plan

  variables {
    gke_nodes_cidr = "10.10.0.0/24"
    ops_cidr       = "10.10.1.0/24"
  }
}

run "invalid_cidr_is_rejected" {
  command = plan

  variables {
    gke_nodes_cidr = "10.10.0.0/40"
  }

  expect_failures = [var.gke_nodes_cidr]
}

run "empty_health_check_ports_are_rejected" {
  command = plan

  variables {
    lb_health_check_ports = []
  }

  expect_failures = [var.lb_health_check_ports]
}

run "invalid_name_is_rejected" {
  command = plan

  variables {
    name = "Dozy_VPC"
  }

  expect_failures = [var.name]
}
