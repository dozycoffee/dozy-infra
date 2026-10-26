output "node_service_account_email" {
  description = "GKE 노드 서비스 계정. 역할 부여가 끝난 뒤에 쓰이도록 의존성을 건다."
  value       = google_service_account.nodes.email
  depends_on  = [google_project_iam_member.nodes]
}

output "workload_service_account_emails" {
  description = "Workload Identity 서비스 계정 이메일(키별). 쿠버네티스 서비스 계정에 iam.gke.io/gcp-service-account 주석으로 단다."
  value       = { for key, sa in google_service_account.workload : key => sa.email }
  depends_on  = [google_service_account_iam_member.workload_identity, google_project_iam_member.workload]
}
