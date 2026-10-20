variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "리전. 서브넷, 라우터, NAT이 이 리전에 만들어진다."
  type        = string
  default     = "asia-northeast3"
}

variable "name" {
  description = "자원 이름 접두사. VPC는 <name>-vpc가 된다."
  type        = string
  default     = "dozy"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,20}[a-z0-9])?$", var.name))
    error_message = "name은 소문자로 시작하는 소문자·숫자·하이픈이고 22자 이하여야 한다."
  }
}

variable "gke_nodes_cidr" {
  description = "GKE 노드 서브넷 대역"
  type        = string
  default     = "10.10.0.0/22"

  validation {
    condition     = can(cidrhost(var.gke_nodes_cidr, 0))
    error_message = "gke_nodes_cidr은 올바른 CIDR이어야 한다."
  }
}

variable "pods_cidr" {
  description = "GKE 파드 보조 대역"
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.pods_cidr, 0))
    error_message = "pods_cidr은 올바른 CIDR이어야 한다."
  }
}

variable "services_cidr" {
  description = "GKE 서비스 보조 대역"
  type        = string
  default     = "10.30.0.0/20"

  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "services_cidr은 올바른 CIDR이어야 한다."
  }
}

variable "ops_cidr" {
  description = "부하 발생기와 점검용 VM 서브넷 대역"
  type        = string
  default     = "10.10.8.0/24"

  validation {
    condition     = can(cidrhost(var.ops_cidr, 0))
    error_message = "ops_cidr은 올바른 CIDR이어야 한다."
  }
}

variable "psa_cidr" {
  description = "Private Service Access 예약 대역 (Cloud SQL이 쓴다)"
  type        = string
  default     = "10.40.0.0/20"

  validation {
    condition     = can(cidrhost(var.psa_cidr, 0))
    error_message = "psa_cidr은 올바른 CIDR이어야 한다."
  }
}

variable "nat_static_ip" {
  description = "Cloud NAT가 고정 외부 IP를 쓸지. false면 자동 할당한다."
  type        = bool
  default     = true
}

variable "lb_health_check_ports" {
  description = "로드밸런서 헬스 체크를 허용할 서비스 포트"
  type        = list(string)
  default     = ["8080", "8082"]

  validation {
    condition     = length(var.lb_health_check_ports) > 0
    error_message = "헬스 체크 포트가 하나 이상 있어야 한다."
  }
}

variable "ops_network_tag" {
  description = "IAP SSH 접속을 허용할 VM의 네트워크 태그"
  type        = string
  default     = "dozy-ops"
}
