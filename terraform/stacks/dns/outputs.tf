output "name_servers" {
  description = "가비아의 네임서버 설정에 넣을 이 존의 네임서버"
  value       = module.dns.name_servers
}

output "zone_name" {
  description = "Cloud DNS 존 이름 (stacks/gcp가 서비스 레코드를 만들 때 사용)"
  value       = module.dns.zone_name
}

output "certificate_map_name" {
  description = "Ingress가 붙일 certificate map 이름"
  value       = module.dns.certificate_map_name
}
