output "cluster_name" {
  description = "클러스터 이름"
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "클러스터 위치(리전)"
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "컨트롤 플레인 공개 엔드포인트 IP. 승인된 대역에서만 접근할 수 있다."
  value       = google_container_cluster.this.endpoint
}

output "workload_pool" {
  description = "Workload Identity 풀 (<프로젝트>.svc.id.goog). 풀은 클러스터가 만들어질 때 생기므로 클러스터 뒤에 쓰이도록 의존성을 건다."
  value       = "${var.project_id}.svc.id.goog"
  depends_on  = [google_container_cluster.this]
}

output "get_credentials_command" {
  description = "kubectl 접속 정보를 받는 명령"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${google_container_cluster.this.location} --project ${var.project_id}"
}
