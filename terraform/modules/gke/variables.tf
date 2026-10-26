variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "클러스터 리전 (Autopilot은 리전 클러스터다)"
  type        = string
  default     = "asia-northeast3"
}

variable "name" {
  description = "클러스터 이름"
  type        = string
  default     = "dozy"
}

variable "network_self_link" {
  description = "VPC self link"
  type        = string
}

variable "subnet_self_link" {
  description = "노드 서브넷 self link"
  type        = string
}

variable "pods_range_name" {
  description = "서브넷의 파드 보조 대역 이름"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "서브넷의 서비스 보조 대역 이름"
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr" {
  description = "컨트롤 플레인이 쓰는 /28 대역. 다른 대역과 겹치면 안 된다."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr, 0)) && endswith(var.master_ipv4_cidr, "/28")
    error_message = "master_ipv4_cidr은 /28 CIDR이어야 한다."
  }
}

variable "master_authorized_cidrs" {
  description = "컨트롤 플레인(kubectl)에 접근할 수 있는 대역. 내 공인 IP를 /32로 넣는다. 전체 개방(0.0.0.0/0)은 허용하지 않는다."
  type        = list(string)

  validation {
    condition     = length(var.master_authorized_cidrs) > 0
    error_message = "접근을 허용할 대역이 하나 이상 있어야 한다."
  }

  validation {
    condition     = alltrue([for c in var.master_authorized_cidrs : can(cidrhost(c, 0))])
    error_message = "master_authorized_cidrs의 모든 값이 올바른 CIDR이어야 한다."
  }

  validation {
    condition     = !contains(var.master_authorized_cidrs, "0.0.0.0/0")
    error_message = "컨트롤 플레인을 전체(0.0.0.0/0)에 열 수 없다."
  }
}

variable "node_service_account_email" {
  description = "노드가 쓸 서비스 계정 이메일. 기본 Compute 서비스 계정을 쓰지 않는다."
  type        = string
}

variable "release_channel" {
  description = "릴리스 채널"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel은 RAPID, REGULAR, STABLE 중 하나여야 한다."
  }
}

variable "deletion_protection" {
  description = "삭제 방지. 올리고 내리는 학습 환경이라 기본은 끈다."
  type        = bool
  default     = false
}
