variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "name" {
  description = "비밀값 ID 접두사. ID는 <name>-<서비스>-<비밀값 이름>이 된다."
  type        = string
  default     = "dozy"
}

variable "secrets" {
  description = "서비스별로 만들 비밀값 이름 목록. 값은 넣지 않고 껍데기만 만든다."
  type        = map(list(string))
  default     = {}
}

variable "secret_versions" {
  description = "테라폼이 값을 직접 넣을 비밀값(예: DB 비밀번호). 키는 \"<서비스>/<비밀값 이름>\"이다. 값은 상태 파일에 남는다."
  type        = map(string)
  default     = {}
  sensitive   = true
}
