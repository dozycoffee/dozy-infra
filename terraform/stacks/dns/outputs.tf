output "name_servers" {
  description = "도메인 소유자가 가비아에 NS 레코드로 등록할 네임서버"
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

output "gabia_ns_records" {
  description = "가비아에 등록할 NS 레코드 (호스트: 서브도메인 이름, 값: 네임서버)"
  value = {
    host        = split(".", var.domain)[0]
    name_server = module.dns.name_servers
  }
}
