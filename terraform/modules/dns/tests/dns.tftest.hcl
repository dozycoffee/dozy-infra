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

run "root_domain_zone_and_records" {
  command = apply

  variables {
    domain = "dozy.kr"
    records = {
      www = { type = "CNAME", ttl = 600, rrdatas = ["example.vercel-dns-017.com."] }
    }
  }

  assert {
    condition     = google_dns_managed_zone.this.name == "dozy-kr" && google_dns_managed_zone.this.dns_name == "dozy.kr."
    error_message = "루트 도메인도 존 이름과 dns_name이 맞아야 한다."
  }

  assert {
    condition     = google_dns_record_set.records["www"].name == "www.dozy.kr."
    error_message = "기록 이름은 도메인 아래의 FQDN이어야 한다."
  }

  assert {
    condition     = google_dns_record_set.records["www"].type == "CNAME" && google_dns_record_set.records["www"].ttl == 600
    error_message = "기록의 타입과 TTL이 입력대로여야 한다."
  }

  assert {
    condition     = google_dns_record_set.records["www"].rrdatas == tolist(["example.vercel-dns-017.com."])
    error_message = "기록 값이 입력대로여야 한다."
  }

  assert {
    condition     = google_dns_record_set.records["www"].managed_zone == "dozy-kr"
    error_message = "기록은 이 모듈의 존에 만들어져야 한다."
  }

  assert {
    condition     = contains(google_certificate_manager_certificate.wildcard.managed[0].domains, "*.dozy.kr")
    error_message = "루트 도메인의 와일드카드 인증서가 만들어져야 한다."
  }
}

run "apex_record_uses_domain_itself" {
  command = apply

  variables {
    domain = "dozy.kr"
    records = {
      "@" = { type = "A", rrdatas = ["203.0.113.10"] }
    }
  }

  assert {
    condition     = google_dns_record_set.records["@"].name == "dozy.kr."
    error_message = "키가 @이면 도메인 자체의 기록이어야 한다."
  }

  assert {
    condition     = google_dns_record_set.records["@"].ttl == 300
    error_message = "TTL을 생략하면 기본값 300이어야 한다."
  }
}

run "no_records_by_default" {
  command = apply

  assert {
    condition     = length(google_dns_record_set.records) == 0
    error_message = "records를 주지 않으면 추가 기록을 만들지 않아야 한다."
  }
}

run "empty_rrdatas_is_rejected" {
  command = plan

  variables {
    records = {
      www = { type = "CNAME", rrdatas = [] }
    }
  }

  expect_failures = [var.records]
}
