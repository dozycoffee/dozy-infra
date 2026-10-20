# 가비아에서 옮겨 온 기존 기록. 네임서버가 GCP로 넘어가면 이 존이 응답하므로 빠진 기록은 끊긴다.
locals {
  records = {
    # 홈페이지(Vercel). 가비아에 있던 값과 TTL 그대로
    www = {
      type    = "CNAME"
      ttl     = 600
      rrdatas = ["44151e191865025d.vercel-dns-017.com."]
    }
  }
}
