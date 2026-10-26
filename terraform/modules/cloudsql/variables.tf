variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "리전"
  type        = string
  default     = "asia-northeast3"
}

variable "name" {
  description = "인스턴스 이름 접두사. 이름은 <name>-<엔진>-<무작위 4자>가 된다."
  type        = string
  default     = "dozy"
}

variable "network_self_link" {
  description = "프라이빗 IP로 붙일 VPC의 self link"
  type        = string
}

variable "psa_connection_id" {
  description = "Private Service Access 연결 ID. 이 연결이 만들어진 뒤에 인스턴스를 만들기 위해 받는다."
  type        = string
}

variable "databases" {
  description = "서비스별 DB. 키는 서비스 이름이고 DB 사용자 이름으로도 쓴다. 엔진별로 인스턴스를 하나씩 만든다."
  type = map(object({
    engine = string
    name   = string
  }))
  default = {}

  validation {
    condition     = alltrue([for service, d in var.databases : contains(["mysql", "postgres"], d.engine)])
    error_message = "engine은 mysql 또는 postgres여야 한다."
  }

  validation {
    condition     = alltrue([for service, d in var.databases : can(regex("^[a-z][a-z0-9_]{0,30}$", d.name))])
    error_message = "DB 이름은 소문자로 시작하는 소문자·숫자·밑줄이고 31자 이하여야 한다."
  }

  validation {
    condition     = alltrue([for service, d in var.databases : can(regex("^[a-z][a-z0-9_-]{0,30}$", service))])
    error_message = "서비스 이름(DB 사용자 이름)은 소문자로 시작하는 소문자·숫자·밑줄·하이픈이고 31자 이하여야 한다."
  }
}

variable "mysql_version" {
  description = "MySQL 버전"
  type        = string
  default     = "MYSQL_8_0"
}

variable "postgres_version" {
  description = "PostgreSQL 버전. 로컬 compose는 18이지만 Cloud SQL 지원 여부를 확인하지 못해 17로 시작한다."
  type        = string
  default     = "POSTGRES_17"
}

variable "mysql_tier" {
  description = "MySQL 머신 티어(학습용 최소)"
  type        = string
  default     = "db-f1-micro"
}

variable "postgres_tier" {
  description = "PostgreSQL 머신 티어(학습용 최소)"
  type        = string
  default     = "db-f1-micro"
}

variable "disk_size_gb" {
  description = "디스크 크기(GB). 자동으로 늘어난다."
  type        = number
  default     = 10
}

variable "backup_start_time" {
  description = "자동 백업 시작 시각(UTC, HH:MM). 기본 18:00은 한국 시간 새벽 3시다."
  type        = string
  default     = "18:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time은 HH:MM 형식이어야 한다."
  }
}

variable "deletion_protection" {
  description = "삭제 방지. 올리고 내리는 학습 환경이라 기본은 끈다."
  type        = bool
  default     = false
}
