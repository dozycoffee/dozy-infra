# dozy-infra

Dozy 서비스를 GCP(GKE Autopilot)에 올리는 인프라 저장소다. 테라폼으로 클라우드 자원을, 공통 Helm 차트로 서비스를 배포한다.

> 학습용 프로젝트이며 구축 중이다. 현재는 DNS 스택(`terraform/stacks/dns`)까지 있고, 나머지 테라폼 모듈과 Helm 차트는 아직 없다. 진행 상황은 [PROGRESS.md](PROGRESS.md), 작업 목록은 [feature_list.json](feature_list.json)에 있다.

## 문서

- [docs/infra-repo-design.md](docs/infra-repo-design.md): 저장소 구조, 팀원별 배포, Kafka 전환 방식
- [docs/system-architecture.md](docs/system-architecture.md): 네트워크, 데이터 계층, 관측, 비용 통제

## 대상 서비스

| 서비스 | 이미지 |
|---|---|
| dozy-auth | `ghcr.io/dozycoffee/dozy-auth-api` |
| dozy-inventory-api | `ghcr.io/dozycoffee/dozy-inventory-api` |
| dozy-wms-api | `ghcr.io/dozycoffee/dozy-wms-api` |
| dozy-catalog-api | `ghcr.io/dozycoffee/dozy-catalog-api` (릴리스 전이라 `sha-` 태그 고정) |
| dozy-store-api | 이미지 준비 후 추가 |

## 처음 한 번: GCP 준비

팀원마다 **자기 GCP 프로젝트**에 올린다. 아래는 각자 한 번만 하는 수동 절차이고, 이후 자원은 테라폼이 만든다. 명령의 `<...>`는 자기 값으로 바꾼다.

> `gcloud` 명령과 옵션 이름은 `gcloud <명령> --help`로 확인했지만, 실제 프로젝트에서 실행해 보지는 않았다. API 목록(초안, 테라폼 모듈을 만들면서 확정), `brew` 설치 명령, GKE 플러그인 설치 명령은 확인하지 않았다. 동작이 다르면 먼저 `--help`를 따른다.

### 0. 도구 설치

| 도구 | 설치 (macOS, Homebrew) |
|---|---|
| gcloud | `brew install --cask google-cloud-sdk` |
| GKE 인증 플러그인 | `gcloud components install gke-gcloud-auth-plugin` |
| kubectl | `brew install kubectl` |
| helm | `brew install helm` |
| terraform | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |

`brew install terraform`은 오래된 버전에 멈춰 있을 수 있어 HashiCorp tap을 쓴다. 테라폼 버전은 코드의 `required_version`으로 고정할 예정이다.

### 1. 로그인

```bash
gcloud auth login                        # gcloud 명령용
gcloud auth application-default login    # 테라폼이 쓰는 자격 증명
```

### 2. 프로젝트 만들기와 결제 연결

프로젝트 ID는 전 세계에서 유일해야 하고 바꿀 수 없다. 예: `dozy-<이름>`.

```bash
export PROJECT_ID=<project-id>

gcloud projects create "$PROJECT_ID" --name="dozy-<이름>"
gcloud billing accounts list                         # 결제 계정 ID 확인
gcloud billing projects link "$PROJECT_ID" --billing-account=<결제 계정 ID>
gcloud config set project "$PROJECT_ID"
```

### 3. 예산 알림 (가장 먼저)

**예산 알림은 알려 줄 뿐 자원을 자동으로 멈추지 않는다.** 임계치를 넘어도 비용은 계속 나가므로, 알림을 받으면 직접 `scripts/down.sh`로 내려야 한다. 쓰지 않을 때 내리는 습관이 가장 확실한 비용 통제다.

콘솔에서 만드는 것이 가장 단순하다.

1. 콘솔 → 결제 → 예산 및 알림 → 예산 만들기
2. 범위: 방금 만든 프로젝트만 선택
3. 금액: 각자 정한다(학습 한도 기준)
4. 알림 임계치: 50%, 90%, 100%
5. 알림 수신 대상에 본인 이메일이 포함되는지 확인

명령으로 만들려면 `gcloud billing budgets create --help`의 옵션을 따른다.

### 4. API 켜기

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  secretmanager.googleapis.com \
  dns.googleapis.com \
  certificatemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iap.googleapis.com
```

매니지드 Kafka를 쓰는 단계(`kafka_mode=managed`)에서는 해당 API를 추가로 켠다.

### 5. 테라폼 상태 버킷

상태 파일은 각자의 버킷에 둔다. 공유하면 서로 덮어쓴다. 버킷 이름은 전역에서 유일해야 한다.

```bash
export STATE_BUCKET="${PROJECT_ID}-tfstate"

gcloud storage buckets create "gs://${STATE_BUCKET}" \
  --project="$PROJECT_ID" \
  --location=asia-northeast3 \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
```

- 버전 관리를 켜 두면 상태 파일이 잘못 덮어써져도 이전 버전으로 되돌릴 수 있다.
- 한 버킷에 스택마다 `prefix`로 상태를 나눈다. 스택(`terraform/stacks/`)이 생기면 아래처럼 초기화한다.

```bash
terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=<스택 이름: dns 또는 gcp>"
```

- 이 버킷은 테라폼이 만든 자원이 아니라서 `terraform destroy`로 지워지지 않는다. 프로젝트를 정리할 때 직접 지운다.

### 6. 확인

```bash
gcloud config get-value project                 # 내 프로젝트 ID
gcloud billing projects describe "$PROJECT_ID"  # billingEnabled: true
gcloud services list --enabled | grep -c googleapis   # 켠 API가 보이는지
gcloud storage buckets describe "gs://${STATE_BUCKET}" --format="value(versioning.enabled)"   # True
```

### 7. DNS 스택 올리기 (한 번)

`dozy.kr`의 DNS 존, 기존 기록, 와일드카드 인증서를 만든다. 오래 두는 스택이라 `down.sh`가 지우지 않고, **존을 지우고 다시 만들지 않는다**(네임서버가 바뀔 수 있다). 설계는 [설계 문서 4.4절](docs/infra-repo-design.md#44-도메인과-dns)에 있다.

> **먼저 확인:** 가비아 DNS 관리의 기존 기록이 모두 `terraform/stacks/dns/records.tf`에 있어야 한다. 네임서버를 바꾸면 `dozy.kr` 전체가 GCP로 넘어가므로, 빠진 기록은 끊긴다. 현재 기록은 `www` → Vercel 하나다.

```bash
cd terraform/stacks/dns
cp terraform.tfvars.example terraform.tfvars   # project_id, domain(dozy.kr)을 채운다

terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=dns"
terraform plan
terraform apply
terraform output name_servers
```

1. `apply`가 끝나면 `www` 같은 기록이 새 존에 있는지 확인한다. 새 네임서버가 응답해야 한다.

```bash
dig +norecurse A www.dozy.kr @<output의 네임서버 하나>   # CNAME이 보여야 한다
```

2. 가비아의 **네임서버 설정**(도메인 전체)에 `terraform output name_servers`의 값 4개를 넣는다. 기존 값은 지우고 교체한다. 가비아의 **DNS 레코드 추가** 메뉴가 아니다. 이 단계는 존이 준비된 **뒤에** 해야 한다. 존이 없는 채로 바꾸면 홈페이지가 끊긴다.
3. `.kr` 레지스트리에 반영되었는지 확인한다. 반영에 시간이 걸릴 수 있다(이번에는 가비아 저장 뒤 몇 분에서 수십 분). 공개 리졸버는 캐시 때문에 늦게 바뀐다.

```bash
dig +norecurse NS dozy.kr @g.dns.kr    # 새 네임서버 4개가 보여야 한다
curl -sS -o /dev/null -w "%{http_code}\n" https://www.dozy.kr   # 200
```

인증서는 이 반영이 끝난 뒤 구글이 소유 확인을 하면서 `PROVISIONING`에서 `ACTIVE`로 바뀐다(2026-10-20 실제로 `ACTIVE`가 되었다). 콘솔의 Certificate Manager 또는 아래 명령으로 확인한다.

```bash
gcloud certificate-manager certificates describe dozy-kr-wildcard --location=global --format="value(managed.state)"
```

`terraform apply`는 실제 자원(DNS 존, 인증서)을 만든다. 존은 소액이지만 상시 과금이므로 쓰지 않을 때도 유지하는 자원임을 알고 시작한다.

### 이후 순서

`scripts/up.sh`로 올린다(구축 중).

## 사용법

올리고 내리는 절차는 구축 중이다. 완성되면 아래 순서가 된다. 자세한 내용은 설계 문서의 5절을 본다.

```
scripts/up.sh      # terraform apply → 클러스터 접속 → 설정 생성 → 배포
scripts/down.sh    # 쿠버네티스 리소스 삭제 → 남은 자원 확인 → terraform destroy
```

**비용 주의:** 쓰지 않을 때는 반드시 내린다. 예산 알림을 먼저 설정한다.

## 검증

```bash
scripts/verify.sh
```
