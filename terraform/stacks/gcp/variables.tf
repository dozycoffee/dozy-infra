variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "기본 리전"
  type        = string
  default     = "asia-northeast3"
}

variable "master_authorized_cidrs" {
  description = "GKE 컨트롤 플레인(kubectl)에 접근할 수 있는 대역. 내 공인 IP를 /32로 넣는다. IP가 바뀌면 갱신한다."
  type        = list(string)
}

variable "services" {
  description = "서비스 선언. DB와 필요한 비밀값을 서비스마다 한 줄로 추가한다. 키는 서비스 이름이고 DB 사용자 이름과 비밀값 ID에 쓰인다."
  type = map(object({
    db = optional(object({
      engine = string
      name   = string
    }))
    secrets = optional(list(string), [])
  }))

  default = {
    auth = {
      db      = { engine = "postgres", name = "auth" }
      secrets = ["db-password", "smtp", "signing-keys"]
    }
    catalog = {
      db      = { engine = "postgres", name = "dozy_catalog" }
      secrets = ["db-password", "auth-client-secret"]
    }
    inventory = {
      db      = { engine = "mysql", name = "dozy_inventory" }
      secrets = ["db-password", "auth-client-secret"]
    }
    wms = {
      db      = { engine = "mysql", name = "dozy_wms" }
      secrets = ["db-password", "auth-client-secret"]
    }
  }
}
