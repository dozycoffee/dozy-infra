output "network_id" {
  description = "VPC ID"
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC 이름"
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "VPC self link (GKE, Cloud SQL이 사용)"
  value       = google_compute_network.this.self_link
}

output "gke_subnet_name" {
  description = "GKE 노드 서브넷 이름"
  value       = google_compute_subnetwork.gke.name
}

output "gke_subnet_self_link" {
  description = "GKE 노드 서브넷 self link"
  value       = google_compute_subnetwork.gke.self_link
}

output "pods_range_name" {
  description = "GKE 파드 보조 대역 이름"
  value       = local.pods_range_name
}

output "services_range_name" {
  description = "GKE 서비스 보조 대역 이름"
  value       = local.services_range_name
}

output "ops_subnet_name" {
  description = "점검용·부하 발생기 서브넷 이름"
  value       = google_compute_subnetwork.ops.name
}

output "ops_subnet_self_link" {
  description = "점검용·부하 발생기 서브넷 self link"
  value       = google_compute_subnetwork.ops.self_link
}

output "nat_ip_addresses" {
  description = "Cloud NAT 고정 외부 IP (자동 할당이면 빈 목록)"
  value       = google_compute_address.nat[*].address
}

output "psa_connection_id" {
  description = "Private Service Access 연결 ID. Cloud SQL이 이 연결 뒤에 만들어지도록 depends_on에 쓴다."
  value       = google_service_networking_connection.psa.id
}
