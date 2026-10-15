# 실제 GCP를 부르지 않고 mock provider로 리소스 구성을 검증한다.

mock_provider "google" {
  mock_resource "google_certificate_manager_dns_authorization" {
    defaults = {
      id = "projects/test-project/locations/global/dnsAuthorizations/jinwoo-dozy-kr-dns-auth"
      dns_resource_record = [
        {
          name = "_acme-challenge_abc.jinwoo.dozy.kr."
          type = "CNAME"
          data = "abc.1.authorize.certificatemanager.goog."
        }
      ]
    }
  }

  mock_resource "google_certificate_manager_certificate" {
    defaults = {
      id = "projects/test-project/locations/global/certificates/jinwoo-dozy-kr-wildcard"
    }
  }

  mock_resource "google_dns_managed_zone" {
    defaults = {
      name_servers = ["ns-cloud-a1.googledomains.com.", "ns-cloud-a2.googledomains.com."]
    }
  }
}

variables {
  project_id = "test-project"
  domain     = "jinwoo.dozy.kr"
}

run "zone_name_and_dns_name" {
  command = apply

  assert {
    condition     = google_dns_managed_zone.this.name == "jinwoo-dozy-kr"
    error_message = "존 이름은 도메인의 점을 하이픈으로 바꾼 값이어야 한다."
  }

  assert {
    condition     = google_dns_managed_zone.this.dns_name == "jinwoo.dozy.kr."
    error_message = "dns_name은 끝에 점이 있는 FQDN이어야 한다."
  }

  assert {
    condition     = google_dns_managed_zone.this.visibility == "public"
    error_message = "존은 public이어야 한다."
  }
}

run "wildcard_certificate_covers_domain_and_subdomains" {
  command = apply

  assert {
    condition     = contains(google_certificate_manager_certificate.wildcard.managed[0].domains, "jinwoo.dozy.kr")
    error_message = "인증서에 서브도메인 자체가 포함되어야 한다."
  }

  assert {
    condition     = contains(google_certificate_manager_certificate.wildcard.managed[0].domains, "*.jinwoo.dozy.kr")
    error_message = "인증서에 와일드카드 도메인이 포함되어야 한다."
  }

  assert {
    condition     = length(google_certificate_manager_certificate.wildcard.managed[0].dns_authorizations) == 1
    error_message = "DNS 인증을 하나 연결해야 한다."
  }
}

run "authorization_record_is_created_in_the_zone" {
  command = apply

  assert {
    condition     = google_dns_record_set.certificate_authorization.type == "CNAME"
    error_message = "인증 레코드는 CNAME이어야 한다."
  }

  assert {
    condition     = google_dns_record_set.certificate_authorization.name == "_acme-challenge_abc.jinwoo.dozy.kr."
    error_message = "인증 레코드 이름은 Certificate Manager가 요구한 값이어야 한다."
  }

  assert {
    condition     = google_dns_record_set.certificate_authorization.managed_zone == "jinwoo-dozy-kr"
    error_message = "인증 레코드는 이 모듈의 존에 만들어져야 한다."
  }

  assert {
    condition     = google_dns_record_set.certificate_authorization.rrdatas == tolist(["abc.1.authorize.certificatemanager.goog."])
    error_message = "인증 레코드 값은 Certificate Manager가 요구한 값이어야 한다."
  }
}

run "certificate_map_matches_wildcard_host" {
  command = apply

  assert {
    condition     = google_certificate_manager_certificate_map_entry.wildcard.hostname == "*.jinwoo.dozy.kr"
    error_message = "certificate map 항목은 와일드카드 호스트에 매칭되어야 한다."
  }

  assert {
    condition     = output.certificate_map_name == "jinwoo-dozy-kr-certmap"
    error_message = "certificate map 이름 출력이 맞지 않다."
  }

  assert {
    condition     = length(output.name_servers) == 2
    error_message = "존의 네임서버를 출력해야 한다."
  }
}

run "trailing_dot_is_rejected" {
  command = plan

  variables {
    domain = "jinwoo.dozy.kr."
  }

  expect_failures = [var.domain]
}

run "uppercase_is_rejected" {
  command = plan

  variables {
    domain = "Jinwoo.dozy.kr"
  }

  expect_failures = [var.domain]
}

run "too_long_domain_is_rejected" {
  command = plan

  variables {
    domain = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.dozy.kr"
  }

  expect_failures = [var.domain]
}
