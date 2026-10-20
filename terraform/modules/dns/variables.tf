variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "domain" {
  description = "DNS 존으로 관리할 도메인. 끝에 점을 붙이지 않는다. 예: dozy.kr"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+$", var.domain))
    error_message = "domain은 소문자 도메인 이름이어야 하고 끝에 점을 붙이면 안 된다. 예: dozy.kr"
  }

  validation {
    condition     = length(var.domain) <= 50
    error_message = "domain은 50자 이하여야 한다. 존과 인증서 이름이 도메인에서 만들어지고 이름 길이 제한(63자)이 있다."
  }
}

variable "records" {
  description = "존에 만들 기록. 키는 도메인 아래의 이름이고 루트는 \"@\"를 쓴다. 예: { www = { type = \"CNAME\", rrdatas = [\"example.vercel-dns.com.\"] } }"
  type = map(object({
    type    = string
    ttl     = optional(number, 300)
    rrdatas = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, r in var.records : length(r.rrdatas) > 0])
    error_message = "records의 모든 항목에 rrdatas가 하나 이상 있어야 한다."
  }
}
