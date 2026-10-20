output "name_servers" {
  description = "이 존의 네임서버. 가비아의 도메인 네임서버 설정에 이 값을 넣는다."
  value       = google_dns_managed_zone.this.name_servers
}

output "zone_name" {
  description = "Cloud DNS 존 이름. 서비스 레코드를 만드는 스택이 이 존에 레코드를 추가한다."
  value       = google_dns_managed_zone.this.name
}

output "certificate_map_name" {
  description = "Certificate Manager certificate map 이름. Ingress가 이 이름으로 인증서를 붙인다."
  value       = google_certificate_manager_certificate_map.this.name
}
