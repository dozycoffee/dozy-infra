output "database_connections" {
  description = "서비스별 접속 정보(비밀번호 제외). 서비스 values에 주입한다."
  value = {
    for service, d in var.databases : service => {
      engine = d.engine
      host   = local.private_ip[d.engine]
      port   = local.ports[d.engine]
      name   = google_sql_database.this[service].name
      user   = google_sql_user.this[service].name
    }
  }
}

output "database_passwords" {
  description = "서비스별 DB 비밀번호. Secret Manager에 넣는 데에만 쓴다."
  value       = { for service, p in random_password.db : service => p.result }
  sensitive   = true
}

output "instance_names" {
  description = "엔진별 인스턴스 이름. Cloud SQL Auth Proxy나 점검 접속에 쓴다."
  value       = { for engine, name in local.instance_by : engine => name if name != null }
}
