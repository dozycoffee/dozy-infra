# dozy-infra

Dozy 서비스를 GCP(GKE Autopilot)에 올리는 인프라 저장소다. 테라폼으로 클라우드 자원을, 공통 Helm 차트로 서비스를 배포한다.

> 학습용 프로젝트이며 구축 중이다. 현재는 뼈대만 있고 테라폼과 매니페스트는 아직 없다. 진행 상황은 [PROGRESS.md](PROGRESS.md), 작업 목록은 [feature_list.json](feature_list.json)에 있다.

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

### 이후 순서

1. `terraform/stacks/dns`로 서브도메인 DNS 존을 만들고 가비아에 NS 레코드를 등록한다(한 번). 자세한 내용은 [설계 문서 4.4절](docs/infra-repo-design.md#44-도메인과-dns).
2. `scripts/up.sh`로 올린다(구축 중).

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
