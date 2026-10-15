# 팀원 서브도메인의 DNS 존과 와일드카드 인증서.
# 오래 두는 스택(stacks/dns)에서만 쓴다. 존을 지우면 네임서버가 바뀌어 가비아의 NS 레코드를 다시 등록해야 한다.

locals {
  zone_name = replace(var.domain, ".", "-")

  # Certificate Manager가 도메인 소유 확인용으로 요구하는 CNAME 레코드
  authorization_record = google_certificate_manager_dns_authorization.this.dns_resource_record[0]
}

resource "google_dns_managed_zone" "this" {
  project     = var.project_id
  name        = local.zone_name
  dns_name    = "${var.domain}."
  description = "Dozy 서브도메인 존 (${var.domain})"
  visibility  = "public"
}

resource "google_certificate_manager_dns_authorization" "this" {
  project = var.project_id
  name    = "${local.zone_name}-dns-auth"
  domain  = var.domain
}

resource "google_dns_record_set" "certificate_authorization" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.this.name
  name         = local.authorization_record.name
  type         = local.authorization_record.type
  ttl          = 300
  rrdatas      = [local.authorization_record.data]
}

resource "google_certificate_manager_certificate" "wildcard" {
  project = var.project_id
  name    = "${local.zone_name}-wildcard"
  scope   = "DEFAULT"

  managed {
    domains            = [var.domain, "*.${var.domain}"]
    dns_authorizations = [google_certificate_manager_dns_authorization.this.id]
  }

  # 인증 레코드가 존에 만들어진 뒤에 발급을 시도한다
  depends_on = [google_dns_record_set.certificate_authorization]
}

resource "google_certificate_manager_certificate_map" "this" {
  project = var.project_id
  name    = "${local.zone_name}-certmap"
}

resource "google_certificate_manager_certificate_map_entry" "wildcard" {
  project      = var.project_id
  name         = "${local.zone_name}-wildcard"
  map          = google_certificate_manager_certificate_map.this.name
  certificates = [google_certificate_manager_certificate.wildcard.id]
  hostname     = "*.${var.domain}"
}
