# 실제 GCP를 부르지 않고 mock provider로 IAM 구성을 검증한다.

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email  = "mock-account@test-project.iam.gserviceaccount.com"
      member = "serviceAccount:mock-account@test-project.iam.gserviceaccount.com"
      name   = "projects/test-project/serviceAccounts/mock-account@test-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id = "test-project"
}

run "node_service_account_has_only_logging_and_monitoring_roles" {
  command = apply

  assert {
    condition     = google_service_account.nodes.account_id == "dozy-gke-nodes"
    error_message = "노드 서비스 계정 ID는 <name>-gke-nodes여야 한다."
  }

  assert {
    condition     = toset([for m in google_project_iam_member.nodes : m.role]) == toset(["roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/monitoring.viewer", "roles/stackdriver.resourceMetadata.writer", "roles/autoscaling.metricsWriter"])
    error_message = "노드에는 로그와 지표를 쓰는 최소 역할만 줘야 한다."
  }

  assert {
    condition     = length([for m in google_project_iam_member.nodes : m if contains(["roles/editor", "roles/owner"], m.role)]) == 0
    error_message = "노드에 편집자나 소유자 역할을 주면 안 된다."
  }

  assert {
    condition     = output.node_service_account_email == "mock-account@test-project.iam.gserviceaccount.com"
    error_message = "노드 서비스 계정 이메일을 출력해야 한다."
  }
}

run "no_workload_identity_by_default" {
  command = apply

  assert {
    condition     = length(google_service_account.workload) == 0 && length(google_service_account_iam_member.workload_identity) == 0 && length(google_project_iam_member.workload) == 0
    error_message = "workload_identities를 주지 않으면 워크로드 서비스 계정을 만들지 않아야 한다."
  }
}

run "workload_identity_binds_kubernetes_service_account" {
  command = apply

  variables {
    workload_identities = {
      eso = {
        namespace = "external-secrets"
        ksa_name  = "external-secrets"
        roles     = ["roles/secretmanager.secretAccessor"]
      }
    }
  }

  assert {
    condition     = google_service_account.workload["eso"].account_id == "dozy-eso"
    error_message = "워크로드 서비스 계정 ID는 <name>-<키>여야 한다."
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity["eso"].role == "roles/iam.workloadIdentityUser"
    error_message = "쿠버네티스 서비스 계정에 workloadIdentityUser 역할을 줘야 한다."
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity["eso"].member == "serviceAccount:test-project.svc.id.goog[external-secrets/external-secrets]"
    error_message = "멤버는 <프로젝트>.svc.id.goog[<네임스페이스>/<서비스 계정>] 형식이어야 한다."
  }

  assert {
    condition     = google_project_iam_member.workload["eso/roles/secretmanager.secretAccessor"].role == "roles/secretmanager.secretAccessor"
    error_message = "지정한 역할을 서비스 계정에 줘야 한다."
  }

  assert {
    condition     = length(output.workload_service_account_emails) == 1
    error_message = "워크로드 서비스 계정 이메일을 출력해야 한다."
  }
}

run "invalid_workload_key_is_rejected" {
  command = plan

  variables {
    workload_identities = {
      "Bad_Key" = { namespace = "a", ksa_name = "b", roles = [] }
    }
  }

  expect_failures = [var.workload_identities]
}

run "long_name_is_rejected" {
  command = plan

  variables {
    name = "this-name-is-way-too-long"
  }

  expect_failures = [var.name]
}
