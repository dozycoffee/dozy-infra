# Cloud SQL (MySQL, PostgreSQL). 프라이빗 IP 전용이고 HA는 끈다(학습용 최소 구성).
# DB 비밀번호는 테라폼이 무작위로 만든다. 값은 테라폼 상태 파일에 남는다.

locals {
  engines     = toset([for service, d in var.databases : d.engine])
  need_mysql  = contains(local.engines, "mysql")
  need_pg     = contains(local.engines, "postgres")
  mysql_name  = "${var.name}-mysql-${random_id.suffix.hex}"
  pg_name     = "${var.name}-postgres-${random_id.suffix.hex}"
  instance_by = { mysql = one(google_sql_database_instance.mysql[*].name), postgres = one(google_sql_database_instance.postgres[*].name) }
  private_ip  = { mysql = one(google_sql_database_instance.mysql[*].private_ip_address), postgres = one(google_sql_database_instance.postgres[*].private_ip_address) }
  ports       = { mysql = 3306, postgres = 5432 }
}

# 삭제한 인스턴스의 이름은 한동안 다시 쓸 수 없으므로, 올릴 때마다 다른 이름이 되도록 접미사를 둔다
resource "random_id" "suffix" {
  byte_length = 2
}

# PSA 연결이 만들어진 뒤에 인스턴스를 만들도록 순서를 건다
resource "terraform_data" "psa_ready" {
  input = var.psa_connection_id
}

resource "google_sql_database_instance" "mysql" {
  count = local.need_mysql ? 1 : 0

  project             = var.project_id
  name                = local.mysql_name
  region              = var.region
  database_version    = var.mysql_version
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.mysql_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size_gb
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
    }

    backup_configuration {
      enabled    = true
      start_time = var.backup_start_time
    }

    database_flags {
      name  = "character_set_server"
      value = "utf8mb4"
    }

    database_flags {
      name  = "default_time_zone"
      value = "+09:00"
    }
  }

  depends_on = [terraform_data.psa_ready]
}

resource "google_sql_database_instance" "postgres" {
  count = local.need_pg ? 1 : 0

  project             = var.project_id
  name                = local.pg_name
  region              = var.region
  database_version    = var.postgres_version
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.postgres_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size_gb
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
    }

    backup_configuration {
      enabled    = true
      start_time = var.backup_start_time
    }
  }

  depends_on = [terraform_data.psa_ready]
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project_id
  name      = each.value.name
  instance  = local.instance_by[each.value.engine]
  charset   = each.value.engine == "mysql" ? "utf8mb4" : null
  collation = each.value.engine == "mysql" ? "utf8mb4_unicode_ci" : null
}

resource "random_password" "db" {
  for_each = var.databases

  length  = 32
  special = false
}

resource "google_sql_user" "this" {
  for_each = var.databases

  project  = var.project_id
  name     = each.key
  instance = local.instance_by[each.value.engine]
  password = random_password.db[each.key].result
  host     = each.value.engine == "mysql" ? "%" : null
}
