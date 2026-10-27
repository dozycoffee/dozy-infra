variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "name" {
  description = "서비스 계정 이름 접두사"
  type        = string
  default     = "dozy"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,10}[a-z0-9])?$", var.name))
    error_message = "name은 소문자로 시작하는 소문자·숫자·하이픈이고 12자 이하여야 한다(서비스 계정 ID는 30자 제한)."
  }
}

variable "node_roles" {
  description = "GKE 노드 서비스 계정에 줄 역할. 로그와 지표를 쓰는 최소 권한이다. roles/container.defaultNodeServiceAccount는 GKE 문서가 사용자 지정 노드 서비스 계정에 요구하는 역할이다."
  type        = list(string)
  default = [
    "roles/container.defaultNodeServiceAccount",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
  ]
}

variable "workload_pool" {
  description = "Workload Identity 풀(<프로젝트>.svc.id.goog). 이 풀은 GKE 클러스터가 만들어질 때 생기므로, 클러스터 모듈의 출력을 넘겨 바인딩이 클러스터 뒤에 만들어지게 한다. 비우면 기본 이름을 쓴다."
  type        = string
  default     = null
}

variable "workload_identities" {
  description = "Workload Identity로 클라우드 API를 쓰는 워크로드. 키는 서비스 계정 이름 일부(예: eso)이고 ksa_name은 쿠버네티스 서비스 계정 이름이다."
  type = map(object({
    namespace = string
    ksa_name  = string
    roles     = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key, w in var.workload_identities : can(regex("^[a-z]([-a-z0-9]{0,10}[a-z0-9])?$", key))])
    error_message = "workload_identities의 키는 소문자로 시작하는 소문자·숫자·하이픈이고 12자 이하여야 한다."
  }
}
