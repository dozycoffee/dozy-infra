# 실제 GCP를 부르지 않고 mock provider로 Secret Manager 구성을 검증한다.

mock_provider "google" {
  mock_resource "google_secret_manager_secret" {
    defaults = {
      id = "projects/test-project/secrets/mock"
    }
  }
}

variables {
  project_id = "test-project"
  secrets = {
    auth    = ["db-password", "smtp", "signing-keys"]
    catalog = ["db-password"]
  }
}

run "shells_are_created_for_every_declared_secret" {
  command = apply

  assert {
    condition     = length(google_secret_manager_secret.this) == 4
    error_message = "선언한 비밀값마다 껍데기를 만들어야 한다."
  }

  assert {
    condition     = google_secret_manager_secret.this["auth/db-password"].secret_id == "dozy-auth-db-password" && google_secret_manager_secret.this["catalog/db-password"].secret_id == "dozy-catalog-db-password"
    error_message = "ID는 <name>-<서비스>-<이름>이어야 한다."
  }

  assert {
    condition     = google_secret_manager_secret.this["auth/smtp"].labels["service"] == "auth"
    error_message = "서비스 라벨이 붙어야 한다."
  }

  assert {
    condition     = output.secret_ids["auth/signing-keys"] == "dozy-auth-signing-keys"
    error_message = "비밀값 ID를 출력해야 한다."
  }
}

run "no_values_are_stored_by_default" {
  command = apply

  assert {
    condition     = length(google_secret_manager_secret_version.generated) == 0
    error_message = "값을 주지 않으면 버전을 만들지 않아야 한다(직접 넣는 값은 껍데기만 둔다)."
  }
}

run "only_generated_values_get_versions" {
  command = apply

  variables {
    secret_versions = {
      "auth/db-password"    = "generated-password-1"
      "catalog/db-password" = "generated-password-2"
    }
  }

  assert {
    condition     = length(google_secret_manager_secret_version.generated) == 2
    error_message = "넣을 값을 준 비밀값에만 버전을 만들어야 한다."
  }

  assert {
    condition     = length(google_secret_manager_secret_version.generated) < length(google_secret_manager_secret.this)
    error_message = "SMTP, 서명 키 같은 나머지는 껍데기로 남아야 한다."
  }
}

run "version_for_undeclared_secret_is_rejected" {
  command = plan

  variables {
    secret_versions = {
      "auth/not-declared" = "value"
    }
  }

  expect_failures = [google_secret_manager_secret_version.generated]
}

run "name_prefix_changes_ids" {
  command = apply

  variables {
    name = "test"
  }

  assert {
    condition     = google_secret_manager_secret.this["auth/smtp"].secret_id == "test-auth-smtp"
    error_message = "이름 접두사가 ID에 적용되어야 한다."
  }
}
