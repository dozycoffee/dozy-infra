output "secret_ids" {
  description = "비밀값 ID(키: <서비스>/<이름>). 값이 아니라 이름이므로 비밀이 아니다."
  value       = local.secret_ids
}
