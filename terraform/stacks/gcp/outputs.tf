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
