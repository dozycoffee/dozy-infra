# GKE 노드용 서비스 계정과, Workload Identity로 클라우드 API를 쓰는 워크로드용 서비스 계정.
# 기본 Compute 서비스 계정은 편집자 권한이라 노드에 쓰지 않는다.

locals {
  workload_pool = coalesce(var.workload_pool, "${var.project_id}.svc.id.goog")

  workload_role_pairs = merge([
    for key, w in var.workload_identities : {
      for role in w.roles : "${key}/${role}" => { key = key, role = role }
    }
  ]...)
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-gke-nodes"
  display_name = "GKE 노드 (${var.name})"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(var.node_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}

resource "google_service_account" "workload" {
  for_each = var.workload_identities

  project      = var.project_id
  account_id   = "${var.name}-${each.key}"
  display_name = "워크로드 ${each.key} (${var.name})"
}

# 쿠버네티스 서비스 계정이 이 구글 서비스 계정으로 동작하도록 허용한다
resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.workload_identities

  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_pool}[${each.value.namespace}/${each.value.ksa_name}]"
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_role_pairs

  project = var.project_id
  role    = each.value.role
  member  = google_service_account.workload[each.value.key].member
}
