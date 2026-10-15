variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "domain" {
  description = "팀원 서브도메인. 끝에 점을 붙이지 않는다. 예: jinwoo.dozy.kr"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+$", var.domain))
    error_message = "domain은 소문자 도메인 이름이어야 하고 끝에 점을 붙이면 안 된다. 예: jinwoo.dozy.kr"
  }

  validation {
    condition     = length(var.domain) <= 50
    error_message = "domain은 50자 이하여야 한다. 존과 인증서 이름이 도메인에서 만들어지고 이름 길이 제한(63자)이 있다."
  }
}
