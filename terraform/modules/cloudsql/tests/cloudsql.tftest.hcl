# 실제 GCP를 부르지 않고 mock provider로 Cloud SQL 구성을 검증한다.

mock_provider "google" {
  mock_resource "google_sql_database_instance" {
    defaults = {
      private_ip_address = "10.40.0.3"
    }
  }
}

mock_provider "random" {
  mock_resource "random_id" {
    defaults = {
      hex = "ab12"
    }
  }
}

variables {
  project_id        = "test-project"
  network_self_link = "https://www.googleapis.com/compute/v1/projects/test-project/global/networks/dozy-vpc"
  psa_connection_id = "projects/test-project/global/networks/dozy-vpc:servicenetworking.googleapis.com"
  databases = {
    auth      = { engine = "postgres", name = "auth" }
    catalog   = { engine = "postgres", name = "dozy_catalog" }
    inventory = { engine = "mysql", name = "dozy_inventory" }
    wms       = { engine = "mysql", name = "dozy_wms" }
  }
}

run "no_instances_without_databases" {
  command = apply

  variables {
    databases = {}
  }

  assert {
    condition     = length(google_sql_database_instance.mysql) == 0 && length(google_sql_database_instance.postgres) == 0
    error_message = "DB를 선언하지 않으면 인스턴스를 만들지 않아야 한다."
  }

  assert {
    condition     = length(output.database_connections) == 0 && length(output.instance_names) == 0
    error_message = "출력도 비어 있어야 한다."
  }
}

run "one_instance_per_engine_with_unique_suffix" {
  command = apply

  assert {
    condition     = length(google_sql_database_instance.mysql) == 1 && length(google_sql_database_instance.postgres) == 1
    error_message = "엔진별로 인스턴스가 하나씩이어야 한다."
  }

  assert {
    condition     = google_sql_database_instance.mysql[0].name == "dozy-mysql-ab12" && google_sql_database_instance.postgres[0].name == "dozy-postgres-ab12"
    error_message = "이름은 <name>-<엔진>-<접미사>여야 한다(삭제한 이름은 한동안 재사용할 수 없다)."
  }

  assert {
    condition     = google_sql_database_instance.mysql[0].database_version == "MYSQL_8_0" && google_sql_database_instance.postgres[0].database_version == "POSTGRES_17"
    error_message = "기본 버전이 맞아야 한다."
  }
}

run "instances_are_private_minimal_and_backed_up" {
  command = apply

  assert {
    condition = alltrue([
      for i in [google_sql_database_instance.mysql[0], google_sql_database_instance.postgres[0]] :
      i.settings[0].ip_configuration[0].ipv4_enabled == false &&
      i.settings[0].ip_configuration[0].private_network == var.network_self_link
    ])
    error_message = "공개 IP 없이 프라이빗 IP로만 붙어야 한다."
  }

  assert {
    condition = alltrue([
      for i in [google_sql_database_instance.mysql[0], google_sql_database_instance.postgres[0]] :
      i.settings[0].availability_type == "ZONAL" && i.settings[0].tier == "db-f1-micro" && i.settings[0].edition == "ENTERPRISE"
    ])
    error_message = "HA 없이 최소 티어의 Enterprise 에디션이어야 한다."
  }

  assert {
    condition = alltrue([
      for i in [google_sql_database_instance.mysql[0], google_sql_database_instance.postgres[0]] :
      i.settings[0].backup_configuration[0].enabled == true && i.settings[0].backup_configuration[0].start_time == "18:00"
    ])
    error_message = "자동 백업이 켜져 있어야 한다."
  }

  assert {
    condition     = google_sql_database_instance.mysql[0].deletion_protection == false && google_sql_database_instance.postgres[0].deletion_protection == false
    error_message = "올리고 내리는 환경이라 삭제 방지는 기본으로 꺼야 한다."
  }
}

run "mysql_uses_utf8mb4_and_seoul_time_zone" {
  command = apply

  assert {
    condition = (
      contains([for f in google_sql_database_instance.mysql[0].settings[0].database_flags : "${f.name}=${f.value}"], "character_set_server=utf8mb4") &&
      contains([for f in google_sql_database_instance.mysql[0].settings[0].database_flags : "${f.name}=${f.value}"], "default_time_zone=+09:00")
    )
    error_message = "MySQL은 utf8mb4와 한국 시간대(+09:00)여야 한다."
  }

  assert {
    condition     = length(google_sql_database_instance.postgres[0].settings[0].database_flags) == 0
    error_message = "PostgreSQL은 DB 시간대를 UTC로 두므로 플래그를 주지 않는다."
  }
}

run "databases_land_on_the_right_instance" {
  command = apply

  assert {
    condition = (
      google_sql_database.this["inventory"].instance == "dozy-mysql-ab12" &&
      google_sql_database.this["wms"].instance == "dozy-mysql-ab12" &&
      google_sql_database.this["auth"].instance == "dozy-postgres-ab12" &&
      google_sql_database.this["catalog"].instance == "dozy-postgres-ab12"
    )
    error_message = "inventory와 wms는 MySQL에, auth와 catalog는 PostgreSQL에 있어야 한다."
  }

  assert {
    condition     = google_sql_database.this["inventory"].name == "dozy_inventory" && google_sql_database.this["catalog"].name == "dozy_catalog"
    error_message = "DB 이름이 선언대로여야 한다."
  }

  assert {
    condition     = google_sql_database.this["wms"].charset == "utf8mb4" && google_sql_database.this["wms"].collation == "utf8mb4_unicode_ci"
    error_message = "MySQL DB는 utf8mb4 / utf8mb4_unicode_ci여야 한다."
  }
}

run "each_service_gets_its_own_user_and_password" {
  command = apply

  assert {
    condition     = google_sql_user.this["auth"].name == "auth" && google_sql_user.this["wms"].name == "wms"
    error_message = "DB 사용자 이름은 서비스 이름이어야 한다."
  }

  assert {
    condition     = google_sql_user.this["wms"].host == "%" && google_sql_user.this["inventory"].host == "%"
    error_message = "MySQL 사용자는 어느 호스트에서든 접속할 수 있게 host가 %여야 한다."
  }

  assert {
    condition     = alltrue([for k in keys(random_password.db) : random_password.db[k].length == 32 && random_password.db[k].special == false])
    error_message = "비밀번호는 URL에 넣어도 안전하도록 특수문자 없이 32자여야 한다."
  }

  assert {
    condition     = length(nonsensitive(keys(output.database_passwords))) == 4
    error_message = "서비스마다 비밀번호를 출력해야 한다."
  }
}

run "connection_output_has_host_port_name_and_user" {
  command = apply

  assert {
    condition = (
      output.database_connections["auth"].engine == "postgres" &&
      output.database_connections["auth"].host == "10.40.0.3" &&
      output.database_connections["auth"].port == 5432 &&
      output.database_connections["auth"].name == "auth" &&
      output.database_connections["auth"].user == "auth"
    )
    error_message = "PostgreSQL 서비스의 접속 정보가 맞아야 한다."
  }

  assert {
    condition     = output.database_connections["inventory"].port == 3306 && output.database_connections["inventory"].name == "dozy_inventory"
    error_message = "MySQL 서비스는 3306 포트여야 한다."
  }

  assert {
    condition     = output.instance_names["mysql"] == "dozy-mysql-ab12" && output.instance_names["postgres"] == "dozy-postgres-ab12"
    error_message = "엔진별 인스턴스 이름을 출력해야 한다."
  }
}

run "only_needed_engines_are_created" {
  command = apply

  variables {
    databases = {
      inventory = { engine = "mysql", name = "dozy_inventory" }
    }
  }

  assert {
    condition     = length(google_sql_database_instance.mysql) == 1 && length(google_sql_database_instance.postgres) == 0
    error_message = "쓰는 엔진의 인스턴스만 만들어야 한다."
  }

  assert {
    condition     = !contains(keys(output.instance_names), "postgres")
    error_message = "만들지 않은 엔진은 출력하지 않아야 한다."
  }
}

run "instance_waits_for_private_service_access" {
  command = apply

  assert {
    condition     = terraform_data.psa_ready.input == var.psa_connection_id
    error_message = "PSA 연결 ID를 받아 순서를 걸어야 한다."
  }
}

run "deletion_protection_is_configurable" {
  command = apply

  variables {
    deletion_protection = true
  }

  assert {
    condition     = google_sql_database_instance.mysql[0].deletion_protection == true
    error_message = "삭제 방지를 켤 수 있어야 한다."
  }
}

run "invalid_engine_is_rejected" {
  command = plan

  variables {
    databases = {
      auth = { engine = "oracle", name = "auth" }
    }
  }

  expect_failures = [var.databases]
}

run "invalid_database_name_is_rejected" {
  command = plan

  variables {
    databases = {
      auth = { engine = "postgres", name = "Auth-DB" }
    }
  }

  expect_failures = [var.databases]
}

run "invalid_backup_time_is_rejected" {
  command = plan

  variables {
    backup_start_time = "25:00"
  }

  expect_failures = [var.backup_start_time]
}
