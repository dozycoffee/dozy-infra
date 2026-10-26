output "network_name" {
  description = "VPC 이름"
  value       = module.network.network_name
}

output "gke_subnet_name" {
  description = "GKE 노드 서브넷 이름"
  value       = module.network.gke_subnet_name
}

output "nat_ip_addresses" {
  description = "Cloud NAT 고정 외부 IP"
  value       = module.network.nat_ip_addresses
}

output "cluster_name" {
  description = "GKE 클러스터 이름"
  value       = module.gke.cluster_name
}

output "get_credentials_command" {
  description = "kubectl 접속 정보를 받는 명령"
  value       = module.gke.get_credentials_command
}

output "database_connections" {
  description = "서비스별 DB 접속 정보(비밀번호 제외). render-config.sh가 서비스 values로 옮긴다."
  value       = module.cloudsql.database_connections
}

output "database_instance_names" {
  description = "엔진별 Cloud SQL 인스턴스 이름"
  value       = module.cloudsql.instance_names
}

output "secret_ids" {
  description = "Secret Manager 비밀값 ID(키: <서비스>/<이름>)"
  value       = module.secrets.secret_ids
}

output "eso_service_account_email" {
  description = "External Secrets Operator가 Workload Identity로 쓸 서비스 계정"
  value       = module.iam.workload_service_account_emails["eso"]
}
