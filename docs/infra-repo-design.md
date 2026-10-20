# dozy-infra 저장소 설계 (초안)

> 상태: 초안. 구현 전 설계 정리다.
> 작성일: 2026-10-15 (같은 날 개정: catalog 포함, Helm 공통 차트, 토픽 중앙 선언, 프로필 정책)
> 상위 문서: [system-architecture.md](system-architecture.md) (네트워크, 데이터 계층, 관측, 비용 통제 등 인프라 전체 설계)
> 이 문서의 범위: **인프라 저장소의 구조, 배포 흐름, 서비스 추가 방식, Kafka 전환과 토픽 관리, 팀원별 배포 방식.** 상위 문서와 겹치는 내용은 반복하지 않고 링크한다.

## 1. 목적

- 서비스 저장소와 분리된 **인프라 전용 저장소**(`dozy-infra`)에 테라폼과 Helm 배포 정의를 둔다.
- 팀원 각자가 **자기 GCP 프로젝트**에 같은 코드를 `apply`해서 올리고, 부하 테스트를 하고, `destroy`로 내릴 수 있어야 한다.
- Kafka는 **직접 띄운 단일 브로커로 시작**하고, 부하 테스트로 기준선을 잡은 뒤 **매니지드로 교체해 같은 테스트를 반복**한다.
- **서비스를 쉽게 추가할 수 있어야 한다.** 지금 대상은 auth, inventory, wms, catalog이고, Store 등은 나중에 붙는다. 새 서비스는 설정 파일 몇 개를 추가하는 것으로 끝나야 하고 차트나 모듈을 새로 짜지 않는다([5절](#5-서비스-추가-방식)).

## 2. 상위 문서와 다른 점 (결정 사항)

| 항목 | 상위 문서 | 이 문서 | 이유 |
|---|---|---|---|
| 저장소 이름 | `dozy-deploy` | `dozy-infra` | 테라폼(클라우드 자원)과 배포 정의를 함께 담으므로 범위가 넓다 |
| 환경 | 하나(`dozy`) | **팀원 1명 = GCP 프로젝트 1개**. 코드는 같고 값만 다르다 | 팀원별 배포 요구 |
| 서비스 배포 도구 | Kustomize | **공통 Helm 차트(`dozy-service`) 하나 + 서비스별 values** | 서비스가 늘어도 values 파일 하나만 추가하면 된다. 프로브, 보안, JVM 설정 같은 공통 규칙을 한곳에서 바꾼다 (결정됨) |
| Kafka 브로커 | Strimzi, 단일 브로커 | **StatefulSet 직접 작성**으로 시작. Strimzi는 보류 | compose의 설정을 그대로 옮길 수 있고 Autopilot 제약을 덜 탄다(상위 문서 미결정 #11) |
| Kafka 전환 | 언급 없음 | 직접 띄운 것 → 매니지드, 변수 하나로 전환 | 같은 조건의 비교 실험 |
| Kafka 토픽 | 언급 없음 | **중앙 선언**. 서비스는 토픽을 만들지 않는다 ([7절](#7-kafka-토픽-관리)) | 운영의 일반적인 방식 |
| 대상 서비스 | auth, inventory, wms | **catalog 추가**(현재 기준). Store는 자리만 | catalog는 코드가 있고 이미지가 올라가 있다. Store는 이미지가 없다 |
| 이미지 태그 | `X.Y.Z` | `X.Y.Z`, 릴리스 전 서비스는 **`sha-<7자리>` 고정** | catalog는 v0.2.0 릴리스 전이라 `sha-` 태그만 있다. `latest`와 `main` 태그는 쓰지 않는다 |
| 클라우드 프로필 | 언급 없음 | `local` 프로필은 클라우드에서 쓰지 않는다 ([8절](#8-실행-프로필과-부하-테스트)) | 로컬 프로필은 인증을 우회한다 |

## 3. 저장소 구조

```
dozy-infra/
├─ CLAUDE.md                  프로젝트 규칙
├─ README.md                  처음 올리는 사람을 위한 순서
├─ feature_list.json          작업 목록
├─ PROGRESS.md                진행 기록
├─ docs/                      설계 문서, adr/
├─ terraform/
│  ├─ modules/
│  │  ├─ network/             VPC, 서브넷(+보조 대역), Cloud Router, Cloud NAT, 방화벽, PSA
│  │  ├─ gke/                 Autopilot 클러스터
│  │  ├─ cloudsql/            MySQL, PostgreSQL 인스턴스. services 맵을 읽어 DB와 계정 생성
│  │  ├─ iam/                 서비스 계정, Workload Identity
│  │  ├─ secrets/             Secret Manager 항목. services 맵을 읽어 껍데기 생성(값은 넣지 않음)
│  │  ├─ dns/                 도메인(dozy.kr)의 Cloud DNS 존, 기존 기록, 와일드카드 인증서
│  │  └─ kafka-managed/       매니지드 Kafka. topics.yaml을 읽어 토픽 생성 (kafka_mode=managed일 때만)
│  └─ stacks/
│     ├─ dns/                 DNS 존만 만드는 루트 모듈 (오래 두는 스택, 4.4절)
│     └─ gcp/                 나머지 자원을 만드는 루트 모듈 (올리고 내리는 스택)
│        ├─ main.tf, variables.tf, outputs.tf
│        ├─ backend.tf        버킷 이름은 비워 두고 init 때 주입
│        └─ terraform.tfvars.example   services 맵 예시 포함
├─ charts/
│  ├─ dozy-service/           Spring Boot 서비스용 공통 차트
│  └─ kafka-self/             단일 브로커 StatefulSet, 헤드리스 Service, 토픽 생성 Job
├─ releases/
│  ├─ index.yaml              배포할 서비스 목록과 순서(wave)
│  ├─ common.yaml             모든 서비스 공통 값
│  ├─ auth.yaml
│  ├─ inventory.yaml
│  ├─ wms.yaml
│  └─ catalog.yaml            서비스별 values (store.yaml 등은 나중에 추가)
├─ topics/
│  └─ topics.yaml             Kafka 토픽 선언 (단일 원본)
├─ third-party/               외부 Helm 차트 values (kube-prometheus-stack, Loki, Tempo, ESO)
├─ loadtest/                  서비스 저장소의 부하 도구를 클라우드에서 돌리는 얇은 래퍼
└─ scripts/
   ├─ verify.sh               셸 문법, feature_list, terraform fmt/validate, helm lint/template
   ├─ render-config.sh        terraform output → 배포에 넣을 값 파일 생성
   ├─ deploy.sh               releases/index.yaml 순서대로 helm upgrade --install
   ├─ up.sh / down.sh         올리기와 내리기 절차를 순서대로 실행
   └─ kafka-compare.md        Kafka 비교 실험 기록 양식
```

- 서비스 코드는 이 저장소에 두지 않는다. 이미지는 `ghcr.io/dozycoffee/<서비스>:<태그>`를 참조만 한다.
- `terraform.tfvars`, `generated/`, 상태 파일, 비밀값은 `.gitignore`에 넣는다. 이 저장소는 공개이므로 특히 주의한다.
- Kafka 브로커(`kafka-self`)도 Helm 차트로 두어 배포 도구를 하나로 통일한다. 외부 차트(관측 스택 등)는 `third-party/`의 values로 설치한다.

### 3.1 공통 차트 `dozy-service`가 맡는 것

서비스마다 반복되는 아래를 차트가 만들고, 서비스는 values로 값만 준다.

| 리소스 | 서비스별로 주는 값 |
|---|---|
| Deployment | 이미지(저장소, 태그), replicas, 리소스, 포트, 환경변수 |
| Service | 업무 포트 |
| ConfigMap | 일반 설정 (주소, CORS origin 등) |
| ExternalSecret | 참조할 Secret Manager 항목 이름 목록 |
| probe | 경로와 포트 (기본값은 Spring Actuator) |
| ServiceAccount | Workload Identity 사용 여부 |
| HPA, PDB | 켜기 여부와 상한 |
| NetworkPolicy | 허용할 상대 (DB, Kafka, 다른 서비스) |
| Ingress 규칙 | 외부에 노출할 경로. 기본은 노출하지 않음 |

공통 규칙(비루트 실행 UID 10001, JVM 힙 비율, graceful 종료, `/actuator/*` 비노출)은 차트의 기본값으로 둔다. 서비스가 다르게 해야 할 때만 values로 덮어쓴다.

## 4. 팀원별 배포 방식

한 사람이 하나의 GCP 프로젝트를 쓰고, **코드는 공유하고 값만 다르게** 한다.

### 4.1 사람마다 달라지는 값

| 값 | 위치 | 비고 |
|---|---|---|
| GCP 프로젝트 ID, 리전 | `terraform.tfvars` | 기본 리전은 `asia-northeast3` |
| 자원 이름 접두사 | `terraform.tfvars` | 이름 충돌 방지 |
| `kafka_mode` | `terraform.tfvars` | `self` 또는 `managed`. 기본 `self` |
| 접근 허용 IP (컨트롤 플레인) | `terraform.tfvars` | 본인 IP |
| 도메인 | `terraform.tfvars` (`domain = "dozy.kr"`) | 도메인은 한 사람이 쓴다. 다른 팀원은 도메인 없이(IP로) 올린다. [4.4절](#44-도메인과-dns) |
| 비밀값 | Secret Manager | 값은 각자 `gcloud`로 넣는다. 파일이나 저장소에 두지 않는다 |

### 4.2 상태(state) 분리

- 상태 파일은 **각자의 GCS 버킷**에 둔다. 공유하면 서로 덮어쓴다.
- 버킷 이름은 코드에 넣지 않고 `terraform init -backend-config="bucket=<내 버킷>"`로 준다. 한 버킷에서 스택(`dns`, `gcp`)마다 `prefix`로 상태를 나눈다.
- 버킷 생성은 README의 "처음 한 번: GCP 준비"(수동 `gcloud` 명령)에 있다.

### 4.3 테라폼 → Helm 값 전달

Cloud SQL의 프라이빗 IP, 매니지드 Kafka 주소 같은 값은 테라폼이 만든 뒤에야 안다. `render-config.sh`가 `terraform output`을 읽어 `releases/generated/values.yaml`을 만들고, `deploy.sh`가 이 파일을 `-f`로 마지막에 겹쳐 준다(우선순위: `common.yaml` < `<서비스>.yaml` < `generated/values.yaml`). 생성 파일은 커밋하지 않는다.

### 4.4 도메인과 DNS

`dozy.kr`은 가비아에서 샀다. 도메인은 한 사람이 쓰므로 **도메인 전체의 DNS를 GCP Cloud DNS로 옮겨 관리한다.** 가비아는 도메인 등록만 맡고, 가비아의 네임서버 설정이 Cloud DNS를 가리킨다. 팀원별 서브도메인 위임 방식은 쓰지 않는다(2026-10-20 요구사항 변경으로 폐기). 도메인을 쓰지 않는 팀원은 도메인 없이(IP로) 올린다.

```
dozy.kr  (가비아에 등록, 네임서버 = Cloud DNS)
└─ Cloud DNS 존 dozy-kr   (stacks/dns, 오래 둠)
   ├─ www.dozy.kr                CNAME → Vercel   (기존 홈페이지. records.tf)
   ├─ _acme-challenge.dozy.kr    CNAME → 인증서 소유 확인 (모듈이 만듦)
   └─ auth.dozy.kr, catalog.dozy.kr ...   A → 로드밸런서 (stacks/gcp가 만듦)
```

**이름 규칙:** `<서비스>.dozy.kr` (예: `auth.dozy.kr`, `admin.dozy.kr`). 콘솔과 auth가 같은 사이트(`dozy.kr`) 아래라서 refresh 쿠키 조건을 지킨다.

**기존 기록은 코드로 관리한다.** 가비아에서 옮겨 온 기록은 `terraform/stacks/dns/records.tf`의 `records`에 둔다. 현재는 `www` → Vercel 하나뿐이다(2026-10-20 가비아 DNS 확인, 다른 기록 없음).

| 스택 | 만드는 것 | 수명 |
|---|---|---|
| `stacks/dns` | Cloud DNS 존(`dozy.kr`), 기존 기록, 인증서 소유 확인용 DNS 인증 레코드, 와일드카드 인증서, certificate map | 오래 둠. `down.sh`가 건드리지 않는다 |
| `stacks/gcp` | 나머지 자원과 **서비스 레코드**(A). Ingress가 `stacks/dns`의 certificate map을 붙인다 | 올리고 내림. destroy 때 레코드도 지워진다 |

**네임서버 이전 (한 번, 2026-10-20 완료):**

```
1. stacks/dns apply            → output: 이 존의 네임서버 4개 (이번에는 ns-cloud-b1~b4)
2. 가비아 "네임서버 설정"의 값을 이 4개로 교체
3. dig +norecurse NS dozy.kr @g.dns.kr 로 .kr 레지스트리에 반영됐는지 확인
```

가비아에는 비슷한 두 메뉴가 있고 **쓰는 곳이 다르다.** 네임서버 설정은 도메인 전체의 DNS 관리를 넘기는 곳(이번에 쓰는 곳)이고, DNS 레코드 추가는 가비아 DNS 안에 기록을 만드는 곳이다.

**사고와 교훈 (2026-10-20):**

- 서브도메인 위임을 하려고 했는데 값 4개를 가비아의 도메인 **네임서버 설정**에 넣어서, GCP에 `dozy.kr` 존이 없는 채로 도메인 전체가 GCP로 넘어갔다. `www.dozy.kr`이 `SERVFAIL`이 되어 홈페이지가 끊겼다. `dozy.kr` 존과 `www` 기록을 GCP에 만들고 네임서버를 새 존의 값으로 맞춰 복구했다.
- 네임서버를 바꾸기 **전에** 가비아 DNS의 기존 기록을 모두 `records.tf`에 옮겼는지 확인한다. 빠지면 그 기록의 서비스가 끊긴다.
- Cloud DNS는 존마다 네임서버 세트(`a`, `b`, `c`…)를 자동 배정하고 고를 수 없다. 존을 지우고 다시 만들면 세트가 바뀔 수 있다(이번에 `c` → `b`). 그러면 가비아 네임서버 설정을 다시 바꿔야 한다. 그래서 존을 별도 스택으로 오래 둔다.
- `.kr` 레지스트리는 가비아의 변경을 즉시 반영하지 않는다. 확인할 때는 공개 리졸버가 아니라 `g.dns.kr` 같은 `.kr` 서버에 직접 묻는다.

**TLS 인증서: 구글 관리형(Certificate Manager)으로 결정.** 도메인 소유 확인은 DNS 인증(CNAME 레코드 하나)으로 하므로 **로드밸런서가 없어도 미리 발급**할 수 있다. 와일드카드 인증서(`dozy.kr`, `*.dozy.kr`) 한 장을 `stacks/dns`에 두고, 올릴 때마다 Ingress가 certificate map으로 가져다 붙인다. 이렇게 하면 올리고 내릴 때 재발급 대기가 없다. cert-manager는 인증서 자동화를 학습하는 별도 실습으로 나중에 얹는다. `www.dozy.kr`은 Vercel이 자체 인증서로 서비스하므로 이 인증서와 무관하다.

- 확인됨: certificate map 항목의 와일드카드 호스트(`*.dozy.kr`)를 GCP가 받아들인다(apply 성공). 네임서버 이전 뒤 인증서가 `ACTIVE`가 되었고 `dozy.kr`, `*.dozy.kr` 모두 `AUTHORIZED`다(2026-10-20).
- **확인하지 않은 가정**([10절](#10-미결정확인-필요-항목) #19): GKE Autopilot의 외부 Ingress에서 certificate map을 붙일 수 있는지(안 되면 Gateway API), Certificate Manager의 비용(가격표로 확인)

## 5. 서비스 추가 방식

새 서비스(예: Store)를 붙일 때 하는 일은 아래가 전부다. 차트와 테라폼 모듈은 건드리지 않는다.

| # | 하는 일 | 파일 |
|---|---|---|
| 1 | DB와 비밀값 선언 | `terraform.tfvars`의 `services` 맵에 항목 추가 |
| 2 | 배포 값 작성 | `releases/<서비스>.yaml` 추가 |
| 3 | 배포 순서 등록 | `releases/index.yaml`에 항목 추가 |
| 4 | 토픽이 있으면 선언 | `topics/topics.yaml`에 추가 |
| 5 | Auth에 클라이언트 등록 | 수동 부트스트랩 ([10절 미결정](#10-미결정확인-필요-항목)) |

`services` 맵 예시:

```hcl
services = {
  auth      = { db = { engine = "postgres", name = "auth" },          secrets = ["db-password", "smtp", "signing-keys"] }
  catalog   = { db = { engine = "postgres", name = "dozy_catalog" },  secrets = ["db-password", "auth-client-secret"] }
  inventory = { db = { engine = "mysql",    name = "dozy_inventory" }, secrets = ["db-password", "auth-client-secret"] }
  wms       = { db = { engine = "mysql",    name = "dozy_wms" },       secrets = ["db-password", "auth-client-secret"] }
}
```

- 엔진별로 Cloud SQL 인스턴스는 하나씩이고, `services` 맵의 항목마다 그 인스턴스에 DB와 계정을 만든다.
- 이 맵의 형태는 초안이다. 실제 구현 때 서비스별 필수 환경변수를 확인해 다듬는다.

### 5.1 현재 대상 서비스

| 서비스 | 저장소 | 포트 | 프로필 | 이미지 태그 | 비고 |
|---|---|---|---|---|---|
| auth | PostgreSQL | 8080 | `prod` 또는 `dev` (8절) | `sha-`/`X.Y.Z` | replicas 1 고정, 서명 키 볼륨 |
| inventory | MySQL | 8082 | `prod` | `X.Y.Z` (0.1.1) | 다중 인스턴스 안전 |
| wms | MySQL | 8080 | (구분 없음) | `X.Y.Z` (0.1.1) | 프로브용 actuator 상태 확인 필요 |
| catalog | PostgreSQL | 8080 | `prod` | **`sha-` 고정** (릴리스 전) | Kafka 발행, Store 호출(`STORE_BASE_URL`), `/actuator/prometheus`가 업무 포트에서 열림 |
| store | PostgreSQL | 8080 | `prod` | 이미지 없음 | **자리만.** Dockerfile과 이미지 워크플로가 생긴 뒤 추가 |

catalog 관련 주의:

- prod에서 `DB_*`, `KAFKA_BOOTSTRAP_SERVERS`, `DOZY_AUTH_ISSUER_BASE_URI`, `STORE_BASE_URL`, `DOZY_AUTH_CLIENT_SECRET`, `CATALOG_CORS_ALLOWED_ORIGINS`가 하나라도 없으면 기동하지 않는다.
- Store가 없으면 판매 범위 변경이 `503 STORE_SERVICE_UNAVAILABLE`로 거부된다(기동에는 영향 없음). Store가 올라오기 전에는 정상 동작이다.
- 분리 작업(Store로 매장 기능 이전)이 진행 중이라 4단계(v0.3.0)에서 `store`·`exposure` 모듈과 테이블이 제거된다. 배포 설정이 바뀔 수 있어 catalog 값은 릴리스 노트를 확인하며 맞춘다.

## 6. 올리기와 내리기

### 6.1 올리기 (`up.sh`가 순서대로 실행)

```
1. terraform init -backend-config=...  →  terraform apply
2. gcloud container clusters get-credentials ...
3. render-config.sh                    (terraform output → releases/generated/values.yaml)
4. 비밀값 확인                          (Secret Manager에 필요한 항목이 있는지 검사만 한다)
5. 외부 차트 설치                       (ESO, 관측 스택)
6. kafka-self 설치                     (kafka_mode=self일 때. 브로커 → 토픽 생성 Job)
7. deploy.sh                           (releases/index.yaml 순서: auth → 나머지 서비스)
8. 헬스 확인                            (파드 Ready, 서비스별 헬스 엔드포인트)
```

- 서비스 기동 순서: **Kafka와 DB 준비 → auth → inventory, wms, catalog.** auth가 없으면 JWKS 조회가 실패하고, wms는 기동 시 Kafka 연결이 필요하다.
- 4번은 값을 넣어 주지 않고 **없으면 중단**한다. 비밀값을 스크립트가 만지지 않는다.

### 6.2 내리기 (`down.sh`)

`terraform destroy`만 하면 쿠버네티스가 만든 외부 자원(로드밸런서, 영구 디스크)이 남아 비용이 계속 나간다. 순서를 지킨다.

```
1. helm uninstall (역순)                 (Ingress와 LB, PVC 포함 삭제)
2. 남은 로드밸런서·디스크 없는지 확인        (gcloud compute forwarding-rules list, disks list)
3. terraform destroy
```

- `down.sh`는 `stacks/gcp`만 내린다. DNS 존(`stacks/dns`)은 남긴다([4.4절](#44-도메인과-dns)).
- Cloud SQL은 `deletion_protection=false`로 만든다(학습 환경). 데이터는 사라진다.
- 부하 테스트 직후 비용을 줄이려면 `down.sh --pause`(파드 0개, Cloud SQL 중지)를 둔다.

## 7. Kafka 토픽 관리

### 7.1 방식: 중앙 선언

토픽은 **`topics/topics.yaml`에 선언하고 파이프라인이 만든다.** 서비스는 발행과 구독만 한다. 브로커의 자동 생성(`auto.create.topics.enable`)은 끈다.

| | 이유 |
|---|---|
| 파티션 수 | 줄일 수 없고 키별 순서 보장이 파티션 수에 묶여 있어 처음에 리뷰로 정한다 |
| 보존, 압축, 복제 계수 | 구독자에게 영향을 준다. 예: catalog는 보존을 "Store가 구독을 시작하기까지의 지연보다 길게" 두라고 문서에 적었다 |
| 권한 | 서비스에 토픽 생성 권한이 필요 없어진다 |

- 토픽 정의의 소유자는 **발행 서비스**다. 발행 서비스 쪽이 `topics.yaml`에 PR로 추가한다.
- 파티션 수 같은 값의 기준은 **각 서비스의 이벤트 계약 문서**다(예: catalog의 `docs/events/product.md`). `topics.yaml`은 그 값을 옮긴 것이고, 문서에 없는 값은 지어내지 않고 계약 확인 후 채운다.

### 7.2 선언 형식 (초안)

값은 서비스 저장소의 코드와 문서에서 확인한 것만 적고, 확인하지 못한 값은 `TBD`로 둔다(2026-10-15 기준 각 저장소 `main`).

```yaml
topics:
  # catalog (발행). 토픽 생성 코드 없음. catalog 이행 계획 문서는 "운영 브로커가 자동 생성을 끄면 미리 만든다"고 한다
  - name: dozy.catalog.product
    owner: catalog
    partitions: TBD        # 처음 정하면 늘리지 않는다 (키와 파티션 대응이 바뀌면 순서가 깨진다)
    retention: TBD         # Store가 구독을 시작하기까지의 지연보다 길게

  # inventory (발행). 토픽 생성 코드 없음. 발행기가 {topic-prefix}.{집계 유형 소문자}로 보낸다(ADR-0025)
  - { name: dozy.inventory.inventory,   owner: inventory, partitions: TBD }
  - { name: dozy.inventory.reservation, owner: inventory, partitions: TBD }   # wms가 구독
  - { name: dozy.inventory.lot,         owner: inventory, partitions: TBD }   # wms가 구독
  - { name: dozy.inventory.adjustment,  owner: inventory, partitions: TBD }
  - name: dozy.inventory.product                       # wms가 구독
    owner: inventory
    partitions: TBD
    cleanupPolicy: compact   # 필요(7.5절 #1): wms는 새 환경에서 처음부터 읽어 상품 사본을 채운다

  # wms (발행). wms가 NewTopic으로 직접 만든다: partitions 3, replicas 1, cleanup.policy=compact
  - { name: dozy.wms.warehouse-access, owner: wms, partitions: 3, replicationFactor: 1, cleanupPolicy: compact }   # inventory가 구독

  # 실패한 메시지를 보내는 DLT. 소비 서비스의 오류 처리기가 `{원 토픽}.dlt`(소문자)로 보낸다. 파티션은 지정하지 않는다
  - { name: dozy.wms.warehouse-access.dlt,  owner: inventory, partitions: TBD }
  - { name: dozy.inventory.product.dlt,     owner: wms,       partitions: TBD }
  - { name: dozy.inventory.reservation.dlt, owner: wms,       partitions: TBD }
  - { name: dozy.inventory.lot.dlt,         owner: wms,       partitions: TBD }
```

모든 토픽의 복제 계수는 단일 브로커라 1이다(생략 시 기본값으로 1을 쓴다).

### 7.3 적용

| `kafka_mode` | 생성 주체 |
|---|---|
| `self` | `kafka-self` 차트의 Job이 브로커가 뜬 뒤 `kafka-topics.sh --create --if-not-exists`를 실행한다. 이미 있으면 건너뛴다 |
| `managed` | 테라폼 `kafka-managed` 모듈이 같은 파일을 읽어 토픽을 만든다(GCP provider의 토픽 리소스 지원 여부는 확인 필요) |

### 7.4 서비스 쪽 토픽 생성 코드 (현재 상태)

각 저장소 코드를 확인한 결과:

| 서비스 | 토픽 생성 코드 | 비고 |
|---|---|---|
| catalog | 없음 | 미리 만들어 두는 것을 전제로 한다 |
| inventory | **없음** | `dozy.inventory.{집계}` 5개 토픽으로 발행만 한다. 브로커의 자동 생성에 기대는 구조로 보인다 |
| wms | `WarehouseAccessTopicConfig`의 `NewTopic` 빈 하나 → **제거함**(wms ADR-0026, [dozy-wms-api PR #156](https://github.com/dozycoffee/dozy-wms-api/pull/156), 2026-10-16 머지) | 제거 전 설정은 `dozy.wms.warehouse-access`(파티션 3, 복제 1, 압축). 서비스가 토픽을 다시 만들지 못하게 하는 테스트(`NoTopicCreationTest`)를 추가했다 |

따라서 **inventory에는 지울 코드가 없다.** 브로커 자동 생성을 끄면(7.1절) inventory의 5개 토픽을 미리 만들어야 하고, 그래서 `topics.yaml`에 선언한다. wms의 `NewTopic`은 이 방식과 맞지 않아 제거했고, 결정과 이유는 wms ADR-0026에 있다. 파티션 3, 복제 1, 압축은 `topics.yaml`이 그대로 이어받는다.

### 7.5 확인된 불일치

1. **`dozy.inventory.product` 압축:** wms ADR-0021은 "inventory가 토픽을 압축으로 만든다"고 했지만 inventory에는 그 코드가 없었다. wms는 새 환경에서 이 토픽을 처음부터 읽어 상품 사본을 채우므로 압축(또는 무기한 보존)이 필요하다. 상품 이벤트는 변경 후 **전체 스냅샷**이고 키가 상품 ID라서 압축으로 최신 상태만 남겨도 사본을 복원할 수 있다. **결정:** 토픽을 인프라가 `compact`로 선언하고(`topics.yaml`), wms ADR-0020·0021을 그에 맞게 고쳤다. **inventory 코드 수정은 필요 없다.** 다만 inventory의 이벤트 문서(`docs/events.md`)에 이 토픽의 압축 요구를 적어 두는 것을 권한다(서비스 저장소 문서 작업).
2. **DLT 토픽:** inventory와 wms의 오류 처리기는 실패한 메시지를 `{원 토픽}.dlt`로 보낸다. 자동 생성을 끄면 이 토픽이 없어서 메시지를 보관하지 못할 수 있으므로 `topics.yaml`에 선언한다. 없을 때 서비스가 정확히 어떻게 동작하는지는 확인하지 않았다.

## 8. 실행 프로필과 부하 테스트

### 8.1 프로필 정책

클라우드에서는 **`local` 프로필을 쓰지 않는다.** inventory의 `local`은 토큰 없이 모든 role을 가진 개발 사용자로 동작한다.

| 서비스 | 클라우드 프로필 | 근거 |
|---|---|---|
| inventory | `prod` | `prod`는 필수 환경변수가 없으면 기동에 실패한다. `local`과 `prod`를 같이 켜면 기동이 막힌다 |
| catalog, store | `prod` | 프로필 미지정이 로컬 동작이다. `prod`에서 로컬 기본값이 없어진다 |
| wms | (프로필 구분 없음) | 환경변수로만 주입한다. `DB_PASSWORD`에 기본값이 없다 |
| auth | `prod` 또는 `dev` | `prod`는 `AUTH_MAIL_SENDER=console`을 거부해 실제 SMTP가 필요하다. 메일 제공자를 정하기 전까지 `dev`로 둘지 결정한다 |

`SPRING_PROFILES_ACTIVE`는 차트의 필수 값으로 두고, `local`이면 `helm lint`/`template` 단계에서 실패하게 한다.

### 8.2 부하 테스트 토큰

서비스 저장소의 부하 테스트는 로컬 기준이다. 예를 들어 catalog는 토큰을 dozy-auth의 `POST /dev/tokens`(local·dev 프로필 전용)로 받는다. 클라우드에서는 아래 중 하나로 한다.

| | 방식 | 평가 |
|---|---|---|
| (b) **권장** | 부하 테스트용 system client를 Auth에 등록해 정상 경로로 토큰 발급 | 운영과 같은 경로. `/dev/tokens`가 필요 없다. Auth가 제공하는 발급 엔드포인트와 방식은 **확인 필요** |
| (a) 대안 | Auth를 `dev` 프로필로 띄워 `/dev/tokens` 사용 | 간단하다. 이 엔드포인트가 외부에 열리면 안 된다. Ingress에서 막고 NetworkPolicy로 `dozy-ops`에서만 접근하게 한다 |

### 8.3 그 외

- 도구는 서비스 저장소의 것을 쓴다(catalog는 `loadtest/`에 k6, 시드, Grafana 대시보드가 있고 개편 중: catalog #142). 이 저장소의 `loadtest/`는 **복제하지 않고** 대상 주소와 토큰을 주입해 실행하는 래퍼만 둔다.
- 기준 사양 참고: catalog 부하 도구는 Catalog 2개(각 2 vCPU, 2GiB)와 PostgreSQL(2 vCPU, 8GiB)을 기준으로 한다. 클라우드 리소스 산정의 출발점으로 쓴다.
- 시드 데이터는 `dozy-ops` VM에서 Cloud SQL 프라이빗 IP로 넣는다. 부하 후 초기화 절차는 상위 문서 10절을 따른다.
- 부하 전에 Kafka 지표(consumer lag, 요청 지연)와 서비스 지표를 볼 대시보드가 먼저 있어야 한다(상위 문서 8절).
- 서비스 저장소의 스크립트가 대상 주소와 토큰을 파라미터로 받는지는 **확인 필요**하다. 안 받으면 서비스 저장소 수정이 필요하다.

## 9. Kafka 구성

### 9.1 1단계: 직접 띄운 단일 브로커 (`kafka_mode=self`)

로컬 compose의 KRaft 단일 노드 설정을 옮긴다. 서비스 코드는 수정하지 않는다.

| 항목 | 값 |
|---|---|
| 네임스페이스 | `kafka` |
| 리소스 | StatefulSet 1개, 헤드리스 Service 1개, PVC 1개, 토픽 생성 Job |
| 이미지 | `apache/kafka`. 버전은 compose와 같은 3.8~3.9 계열 |
| 내부 주소 | `kafka-0.kafka-headless.kafka.svc.cluster.local:9092` |
| `advertised.listeners` | 위 내부 주소와 **반드시 같게** (`localhost`면 연결 후 통신이 실패한다) |
| 복제 계수 | 오프셋, 트랜잭션 로그 모두 1 |
| 토픽 자동 생성 | 끔 ([7절](#7-kafka-토픽-관리)) |
| 보안 | PLAINTEXT. 클러스터 안에서만 접근하고 NetworkPolicy로 `app` 네임스페이스에서만 허용 |
| 메모리 | 힙 1GB, 컨테이너 limit 2GB에서 시작 (부하 테스트로 조정) |
| 디스크 | PVC는 기본 StorageClass. 크기는 보존 기간과 함께 정한다 |

- 서비스 쪽은 `KAFKA_BOOTSTRAP_SERVERS`를 위 주소로 준다. 이 값은 `releases/generated/values.yaml`이 정한다.
- inventory, wms, catalog는 **같은 브로커**를 쓴다. 로컬 compose처럼 각자 브로커를 띄우지 않는다.

### 9.2 2단계: 매니지드 (`kafka_mode=managed`)

- `terraform/modules/kafka-managed`가 클러스터와 토픽을 만들고, 부트스트랩 주소와 인증 정보를 output으로 낸다.
- `kafka_mode=self`일 때는 이 모듈과 `kafka-self` 설치를 하지 않는다. 반대도 마찬가지다.
- 서비스에는 **주소와 보안 설정**(TLS, SASL)을 환경변수로 준다. 매니지드는 인증이 필요할 가능성이 크고, 서비스가 이를 환경변수만으로 받을 수 있는지가 관건이다([미결정 #2](#10-미결정확인-필요-항목)).

### 9.3 비교 실험 규칙

- 같은 부하 시나리오, 같은 서비스 이미지 태그, 같은 서비스 리소스와 replicas, 같은 DB. 바꾸는 것은 `kafka_mode`뿐이다.
- 기록: 서비스 응답 지연(p50/p95/p99), 오류율, consumer lag, outbox 대기 건수, Kafka 요청 지연, 시간당 비용.
- 기록 양식은 `scripts/kafka-compare.md`에 둔다.

## 10. 미결정·확인 필요 항목

| # | 항목 | 내용 |
|---|---|---|
| 1 | 문서 수락 | 2절의 결정 사항 전체 |
| 2 | 매니지드 Kafka 인증 | GCP 매니지드 Kafka가 요구하는 인증 방식(SASL 종류, TLS)과 서비스가 환경변수만으로 받을 수 있는지(`spring.kafka.properties.*` 바인딩). 안 되면 서비스 저장소 설정 수정 필요 |
| 3 | 토픽 값 | `dozy.catalog.product` 등의 파티션 수, 보존 기간. 각 서비스 이벤트 계약 확인 후 확정 |
| 4 | wms 토픽 생성 코드 제거 | **완료**(wms ADR-0026, dozy-wms-api PR #156, 2026-10-16 머지). inventory에는 지울 코드가 없다(7.4절). 이제 `dozy.wms.warehouse-access`는 인프라가 만들어야 한다(`topics.yaml`) |
| 5 | 매니지드 토픽 리소스 | GCP provider가 매니지드 Kafka 토픽 리소스를 지원하는지 |
| 6 | Auth 프로필 | Auth를 `prod`로 올릴지, SMTP 제공자 확정 전까지 `dev`로 둘지 |
| 7 | 부하 테스트 토큰 | Auth의 system client 토큰 발급 방식 확인. (b) 가능 여부, 안 되면 (a) |
| 8 | 부하 도구 파라미터화 | 서비스 저장소의 k6 스크립트가 대상 주소와 토큰을 외부에서 받는지 |
| 9 | Auth 클라이언트 부트스트랩 | catalog: audience `catalog`, 역할 `catalog:admin`, `catalog:store_agent`, system client `svc-catalog`(Store 쪽 `store:catalog_agent` 역할). 수동 절차를 README에 둘지 시드로 할지 |
| 10 | ghcr 패키지 공개 여부 | 클러스터가 인증 없이 pull할 수 있는지. private이면 `imagePullSecrets` 필요 |
| 11 | catalog 릴리스 | v0.2.0 릴리스 전까지 `sha-` 고정. 릴리스 후 `X.Y.Z`로 전환 |
| 12 | store 이미지 | store 저장소에 Dockerfile과 이미지 푸시 워크플로가 없다. 추가된 뒤에 배포 |
| 13 | catalog 관리 포트 | `/actuator/prometheus`가 업무 포트에서 토큰 없이 열려 있다. 상위 문서의 "관리 포트 분리 표준"(미결정 #4)과 어긋나므로 Ingress에서 `/actuator/*`를 막고, 장기적으로 포트를 분리할지 |
| 14 | Autopilot에서 StatefulSet과 PVC | 디스크 성능과 리소스 요청 제약. 올려 보고 확인 |
| 15 | JWKS 조회 경로 | 상위 문서 미결정 #5와 같다. `AUTH_ISSUER_BASE_URI`를 어떤 주소로 줄지 결정이 선행된다 |
| 16 | 비밀값 주입 방식 | External Secrets Operator와 CSI 드라이버 중 선택 (상위 문서 7절) |
| 17 | 공통 차트 범위 | auth는 서명 키 볼륨과 replicas 1 고정이 있어 공통 차트로 충분한지, 예외가 되는지 |
| 18 | 도메인 네임서버 이전 | **완료**(2026-10-20). 서브도메인 위임 대신 `dozy.kr` 전체를 Cloud DNS로 이전했다. 존을 다시 만들면 네임서버 세트가 바뀔 수 있다(4.4절) |
| 19 | TLS 인증서 연동 확인 | **구글 관리형(Certificate Manager, DNS 인증, 와일드카드)으로 결정, 인증서 `ACTIVE` 확인(2026-10-20).** 남은 확인: Autopilot 외부 Ingress에서 certificate map 사용 가능 여부(안 되면 Gateway API), Certificate Manager 비용 |
| 20 | inventory 이벤트 문서의 압축 요구 | 결정: 인프라가 `compact`로 선언(7.5절). inventory `docs/events.md`에 이 요구를 적을지(서비스 저장소 문서 작업) |
| 21 | DLT 토픽 | `{원 토픽}.dlt`가 없을 때 서비스 동작 확인. 우선 `topics.yaml`에 선언 |

## 11. 구축 순서

1. `dozy-infra` 저장소 뼈대 (완료)
2. GCP 프로젝트, **예산 알림**, 상태 버킷(수동), `stacks/dns`로 `dozy.kr` 존 생성과 가비아 네임서버 변경(한 번)
3. `network`, `cloudsql`, `gke`, `iam`, `secrets` 모듈과 `stacks/gcp` (`services` 맵 포함)
4. `kafka-self` 차트와 토픽 생성 Job, `topics.yaml` 초안
5. 공통 차트 `dozy-service` 뼈대와 `releases/` 구조, `deploy.sh`
6. **auth 하나**를 끝까지 올려 파이프라인(이미지 pull, DB 접속, 헬스, 외부 접근) 검증
7. inventory, wms, catalog 추가 (서비스 추가 방식 5절을 그대로 따라 문서와 어긋나는 점을 고친다)
8. 관측 스택, Kafka 지표
9. 부하 테스트 기준선 측정 (`kafka_mode=self`)
10. `kafka-managed` 모듈 추가, 같은 테스트 반복, 결과 비교
11. store 추가 (이미지 준비 후)

서비스 쪽 선행 작업(wms actuator, 관리 포트 분리, 메트릭 노출)은 서비스 저장소에서 진행하며, 상위 문서 13절의 항목 2~4를 따른다.

각 단계가 끝나면 `feature_list.json`의 상태와 `PROGRESS.md`를 갱신한다.
