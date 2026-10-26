# Secret Manager 비밀값. 직접 넣는 값(SMTP, 서명 키 등)은 껍데기만 만들고,
# 테라폼이 만든 값(DB 비밀번호)만 secret_versions로 넣는다.

locals {
  secret_ids = merge([
    for service, names in var.secrets : {
      for secret in names : "${service}/${secret}" => "${var.name}-${service}-${secret}"
    }
  ]...)
}

resource "google_secret_manager_secret" "this" {
  for_each = local.secret_ids

  project   = var.project_id
  secret_id = each.value
  labels    = { service = split("/", each.key)[0] }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "generated" {
  # 키는 비밀이 아니므로 sensitive 표시를 벗겨서 for_each에 쓴다
  for_each = nonsensitive(toset(keys(var.secret_versions)))

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = var.secret_versions[each.key]

  lifecycle {
    precondition {
      condition     = contains(keys(local.secret_ids), each.key)
      error_message = "${each.key}는 secrets에 선언되지 않은 비밀값이다. 서비스의 secrets 목록에 이름을 추가해야 한다."
    }
  }
}
