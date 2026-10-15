# 상태 버킷은 코드에 두지 않고 init 때 주입한다.
#   terraform init -backend-config="bucket=<내 버킷>" -backend-config="prefix=dns"
terraform {
  backend "gcs" {}
}
