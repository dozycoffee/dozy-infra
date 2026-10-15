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
  description = "팀원 서브도메인. 끝에 점을 붙이지 않는다. 예: jinwoo.dozy.kr"
  type        = string
}
