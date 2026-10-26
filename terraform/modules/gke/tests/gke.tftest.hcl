# 실제 GCP를 부르지 않고 mock provider로 GKE 구성을 검증한다.

mock_provider "google" {
  mock_resource "google_container_cluster" {
    defaults = {
      endpoint = "203.0.113.5"
    }
  }
}

variables {
  project_id                 = "test-project"
  network_self_link          = "https://www.googleapis.com/compute/v1/projects/test-project/global/networks/dozy-vpc"
  subnet_self_link           = "https://www.googleapis.com/compute/v1/projects/test-project/regions/asia-northeast3/subnetworks/dozy-gke"
  master_authorized_cidrs    = ["203.0.113.7/32"]
  node_service_account_email = "dozy-gke-nodes@test-project.iam.gserviceaccount.com"
}

run "cluster_is_autopilot_and_private" {
  command = apply

  assert {
    condition     = google_container_cluster.this.name == "dozy" && google_container_cluster.this.location == "asia-northeast3"
    error_message = "클러스터 이름과 위치(리전)가 맞아야 한다."
  }

  assert {
    condition     = google_container_cluster.this.enable_autopilot == true
    error_message = "Autopilot이어야 한다."
  }

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes == true
    error_message = "노드는 외부 IP가 없는 프라이빗이어야 한다."
  }

  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_endpoint == false && google_container_cluster.this.private_cluster_config[0].master_ipv4_cidr_block == "172.16.0.0/28"
    error_message = "컨트롤 플레인은 승인된 대역에서 접근하도록 공개 엔드포인트를 두고 /28 대역을 써야 한다."
  }

  assert {
    condition     = google_container_cluster.this.deletion_protection == false
    error_message = "올리고 내리는 환경이라 삭제 방지는 기본으로 꺼야 한다."
  }
}

run "network_and_secondary_ranges_are_wired" {
  command = apply

  assert {
    condition     = google_container_cluster.this.network == var.network_self_link && google_container_cluster.this.subnetwork == var.subnet_self_link
    error_message = "VPC와 서브넷을 연결해야 한다."
  }

  assert {
    condition     = google_container_cluster.this.ip_allocation_policy[0].cluster_secondary_range_name == "pods" && google_container_cluster.this.ip_allocation_policy[0].services_secondary_range_name == "services"
    error_message = "서브넷의 pods, services 보조 대역을 써야 한다."
  }
}

run "control_plane_is_reachable_only_from_authorized_cidrs" {
  command = apply

  variables {
    master_authorized_cidrs = ["203.0.113.7/32", "198.51.100.0/24"]
  }

  assert {
    condition     = toset([for b in google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks : b.cidr_block]) == toset(["203.0.113.7/32", "198.51.100.0/24"])
    error_message = "승인한 대역만 컨트롤 플레인에 접근할 수 있어야 한다."
  }
}

run "nodes_use_dedicated_service_account" {
  command = apply

  assert {
    condition     = google_container_cluster.this.cluster_autoscaling[0].auto_provisioning_defaults[0].service_account == "dozy-gke-nodes@test-project.iam.gserviceaccount.com"
    error_message = "노드는 전용 서비스 계정을 써야 한다(기본 Compute 서비스 계정 금지)."
  }
}

run "release_channel_defaults_to_regular_and_is_configurable" {
  command = apply

  assert {
    condition     = google_container_cluster.this.release_channel[0].channel == "REGULAR"
    error_message = "기본 릴리스 채널은 REGULAR여야 한다."
  }
}

run "release_channel_can_be_changed" {
  command = apply

  variables {
    release_channel = "STABLE"
  }

  assert {
    condition     = google_container_cluster.this.release_channel[0].channel == "STABLE"
    error_message = "릴리스 채널을 바꿀 수 있어야 한다."
  }
}

run "outputs_help_connecting" {
  command = apply

  assert {
    condition     = output.workload_pool == "test-project.svc.id.goog"
    error_message = "Workload Identity 풀을 출력해야 한다."
  }

  assert {
    condition     = strcontains(output.get_credentials_command, "get-credentials dozy --region asia-northeast3 --project test-project")
    error_message = "kubectl 접속 명령을 출력해야 한다."
  }

  assert {
    condition     = output.cluster_endpoint == "203.0.113.5"
    error_message = "엔드포인트를 출력해야 한다."
  }
}

run "open_to_everyone_is_rejected" {
  command = plan

  variables {
    master_authorized_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.master_authorized_cidrs]
}

run "empty_authorized_cidrs_are_rejected" {
  command = plan

  variables {
    master_authorized_cidrs = []
  }

  expect_failures = [var.master_authorized_cidrs]
}

run "invalid_authorized_cidr_is_rejected" {
  command = plan

  variables {
    master_authorized_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.master_authorized_cidrs]
}

run "master_cidr_must_be_slash_28" {
  command = plan

  variables {
    master_ipv4_cidr = "172.16.0.0/24"
  }

  expect_failures = [var.master_ipv4_cidr]
}

run "invalid_release_channel_is_rejected" {
  command = plan

  variables {
    release_channel = "NIGHTLY"
  }

  expect_failures = [var.release_channel]
}
