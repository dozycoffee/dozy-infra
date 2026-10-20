variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "기본 리전"
  type        = string
  default     = "asia-northeast3"
}

variable "domain" {
  description = "DNS 존으로 관리할 도메인. 끝에 점을 붙이지 않는다. 예: dozy.kr"
  type        = string
}
