# PROGRESS

## 현재 상태

- 저장소 뼈대, GCP 준비 절차(README), DNS 스택(`stacks/dns`)까지 있다(`infra-01`~`infra-04` 완료, `infra-04b`가 남음). `modules/network`(+`stacks/gcp`)까지 있고, 나머지 테라폼 모듈과 차트는 아직 없다. 지금 GCP에는 DNS 스택 자원만 있고 네트워크는 내려가 있다(올릴 때 `stacks/gcp`를 apply).
- GCP 프로젝트 `dozy-jinwoo`, 상태 버킷 `dozy-jinwoo-tfstate`, `dozy.kr` DNS 존(`dozy-kr`)이 실제로 만들어져 있다. `dozy.kr`의 네임서버는 Cloud DNS(`ns-cloud-b1~b4`)다.
- 인증서 `dozy-kr-wildcard`는 `ACTIVE`이고 `dozy.kr`, `*.dozy.kr` 모두 `AUTHORIZED`다.
- 설계는 `docs/infra-repo-design.md`에 있고, 미결정·확인 필요 항목 19개가 남아 있다(특히 매니지드 Kafka 인증, 부하 테스트 토큰 방식, 토픽 값, ghcr 공개 여부).
- 결정됨: 서비스 배포는 공통 Helm 차트, 대상은 auth/inventory/wms/catalog(store는 이미지 준비 후), Kafka 토픽은 중앙 선언, 클라우드에서 `local` 프로필 금지.
- `terraform` v1.16.6과 `helm`이 설치되어 있다. google provider는 `~> 8.0`(잠금 파일은 4개 플랫폼).

## 세션 로그

### 2026-10-15

- 저장소 뼈대 추가: `CLAUDE.md`, `README.md`, `feature_list.json`, `PROGRESS.md`, `.gitignore`, `scripts/verify.sh`.
- 설계 문서 두 개를 `docs/`로 옮기고 `dozy-architecture/`는 삭제했다. 이제 `docs/`가 유일한 위치다.
- catalog 저장소를 확인(2026-10-15 `main` `3a7934a`)해 설계에 반영: catalog 포함, Helm 공통 차트, 토픽 중앙 선언, 프로필 정책, 서비스 추가 방식.
- `system-architecture.md`에 catalog 반영: 서비스 행·의존, 3절 다이어그램, 4.6 노출 경로, 5절 replicas·probe, 6절 데이터 계층, 13절 미결정(15~17 추가), 14절 구축 순서. 1절의 환경 문구와 Helm 전환도 맞췄다.
- OMS 언급을 모두 제거했다(서비스는 필요할 때 추가).
- 이니셜 커밋과 푸시(`3a04505`).
- 도메인 설계 추가: `dozy.kr`(가비아) 아래 팀원별 서브도메인을 Cloud DNS로 NS 위임, DNS 존은 오래 두는 별도 스택(`stacks/dns`). 가비아 NS 지원은 가정이다.
- `infra-02` 완료: README에 "처음 한 번: GCP 준비"(도구 설치, 로그인, 프로젝트·결제, 예산 알림, API, 상태 버킷, 확인) 추가. gcloud 옵션은 `--help`로 확인했고 실제 실행은 하지 않았다. 설계 문서 4.2절에 스택별 `prefix`로 상태를 나누는 규칙 추가.
- `infra-02b` 완료: `terraform/modules/dns`(Cloud DNS 존, Certificate Manager DNS 인증 CNAME, 와일드카드 인증서, certificate map)와 `terraform/stacks/dns`. mock provider 테스트 7개(검증 오류 3개 포함), `verify.sh`에 `terraform test` 단계 추가. 잘못된 설정에서 테스트가 실패하는 것도 확인했다. 실제 GCP에 apply하지는 않았다.
- 토픽 코드 조사: inventory에는 토픽 생성 코드가 없고(5개 토픽을 자동 생성에 의존), wms에만 `NewTopic` 하나가 있었다. DLT(`{토픽}.dlt`)는 토픽별로 따로 있다. 설계 문서 7절을 사실대로 고쳤다.
- wms 저장소: 브랜치 `chore/remove-warehouse-access-topic-creation`에서 `NewTopic` 설정 제거, ADR-0026 추가, ADR-0020·0021 갱신, `NoTopicCreationTest` 추가(복원하면 실패하는 것도 확인). `./gradlew build` 통과. 이슈 dozycoffee/dozy-wms-api#155, PR #156은 2026-10-16에 머지되었다(`main` `4769752`). 이후 `dozy.wms.warehouse-access` 토픽은 인프라(`topics.yaml`)가 만들어야 한다.
### 2026-10-20 (DNS)

- `jinwoo.dozy.kr` 위임을 시도하다 값 4개를 가비아의 도메인 **네임서버 설정**에 넣어서 `dozy.kr` 전체가 GCP로 넘어갔고, GCP에 `dozy.kr` 존이 없어 `www.dozy.kr`이 `SERVFAIL`이 되었다(홈페이지 장애). 원인은 가비아의 비슷한 두 메뉴(네임서버 설정, DNS 레코드 추가)를 구분하지 못한 것이다.
- 요구사항이 바뀌어(도메인은 한 사람이 쓴다) 서브도메인 위임을 폐기하고 `dozy.kr` 전체를 Cloud DNS로 이전했다. 모듈에 `records` 입력을 추가하고(`www` → Vercel), 테스트를 11개로 늘렸다(변조하면 실패하는 것도 확인).
- 새 존의 네임서버 세트가 이전 존(`c`)과 달라(`b`) 가비아 네임서버 설정을 한 번 더 바꿨다. 반영 뒤 `.kr` 레지스트리가 `b1~b4`, `www.dozy.kr` 응답, HTTPS 200을 확인했다.
- 인증서가 `ACTIVE`가 된 것까지 확인해 `infra-02c`를 완료했다.
- 설계 문서 4.4절, README 7절, `CLAUDE.md` 규칙(네임서버 변경 전 기록 확인, 존 삭제 금지)을 이 내용으로 고쳤다.
- `infra-03` 완료: `modules/network`(VPC `dozy-vpc`, 서브넷 `dozy-gke`·`dozy-ops`와 보조 대역, Cloud Router·NAT(고정 IP), 방화벽 2개, PSA)와 `stacks/gcp`. mock 테스트 16개(대역 겹침·잘못된 CIDR 거부 포함)를 두고, 변조로 실패하는 것도 확인했다(겹침 검사 변조는 Terraform이 상수 조건을 거부해 다른 방식으로 재확인).
- 실제 `apply`(10개, 약 1분 44초)로 설계와 일치하는 것을 `gcloud`로 확인했고, `destroy`(10개, 약 1분 42초)가 PSA의 `ABANDON`으로 막히지 않고 끝나는 것도 확인했다. 남은 자원 없음, 상태 파일 비어 있음. 비용은 확인하지 못했다.
- 아직 확인하지 못한 것: 헬스 체크 방화벽의 `destination_ranges`가 실제로 통과시키는지, 파드 대역이 NAT를 거치는지(GKE와 Ingress가 필요, `infra-04` 이후).
- 프로젝트에 구글이 자동으로 만든 `default` VPC와 방화벽 4개(ssh, rdp가 0.0.0.0/0에 열림)를 삭제했다. 삭제 전에 VM, 로드밸런서, GKE, Cloud SQL, 라우터, 피어링이 없는 것을 확인했다. 설계 문서 10절 #22.
- TLS 인증서는 구글 관리형(Certificate Manager, DNS 인증, 와일드카드)으로 결정. 인증서는 `stacks/dns`에 둔다. Autopilot 외부 Ingress의 certificate map 지원과 비용은 확인 필요.

### 2026-10-26 (infra-04)

- `modules/iam`, `secrets`, `cloudsql`, `gke`와 `stacks/gcp` 연결(`services` 맵) 추가. mock 테스트 36개(iam 6, secrets 5, cloudsql 13, gke 12). 변조 검증은 secrets를 제외하고 확인했다.
- 첫 `apply`(49개 계획)에서 48개가 만들어지고 Workload Identity 바인딩 1개가 `Identity Pool does not exist`로 실패했다(소요 약 13분: Cloud SQL 10~12분, GKE 3분 45초). 풀은 GKE 클러스터가 만들어질 때 생기는데 바인딩이 클러스터를 기다리지 않은 순서 문제였다. `iam` 모듈에 `workload_pool` 입력을 추가하고 `gke`의 `workload_pool` 출력이 클러스터에 의존하게 고쳐 1개를 추가로 만들었다. 총 49개.
- `gcloud`로 확인한 것: Cloud SQL 둘(`POSTGRES_17`, `MYSQL_8_0`, `db-f1-micro`, ENTERPRISE, ZONAL, 프라이빗 IP만, 백업 켬, MySQL 플래그 적용), DB 4개와 사용자, GKE Autopilot(프라이빗 노드, 승인된 대역 1개, 노드 전용 서비스 계정, `dozy-jinwoo.svc.id.goog`), 노드 서비스 계정의 역할 5개, ESO 서비스 계정의 바인딩, Secret Manager 9개(DB 비밀번호 4개만 버전 있음). 이로써 PostgreSQL 17 지원, MySQL 플래그, `db-f1-micro`와 ENTERPRISE 조합, Autopilot의 `auto_provisioning_defaults` 가정이 모두 확인되었다.
- `gke-gcloud-auth-plugin`을 `gcloud components install`로 설치했다. 설치 위치가 `PATH`에 없어(Homebrew gcloud) 확인할 때만 `PATH`에 경로를 붙였고, README 0단계에 안내를 추가했다. 그 뒤 `kubectl get ns`로 내 IP에서 컨트롤 플레인 접속을 확인했다.
- `destroy`(49개, 약 8분)가 Cloud SQL과 PSA 피어링 때문에 막히지 않고 끝났다. 남은 자원 없음, 상태 파일 비어 있음, DNS 스택(존, 인증서 `ACTIVE`)은 그대로다.
- **문제:** 클러스터가 `RUNNING`인데 28분 동안 노드가 0개였고 시스템 파드가 `FailedScheduling`(`no nodes available`)이었다. 노드 VM과 인스턴스 그룹이 없고 오류 조건과 로그도 없었다. 할당량, GKE 서비스 에이전트 역할, 노드 서비스 계정 권한은 정상이다. 원인은 모른다(`infra-04b`, 설계 문서 10절 #26).
- 아직 확인하지 못한 것: 비용, PostgreSQL 사용자 권한(#25). 설계 문서 10절 #23~#26을 추가했다.
- `.gitignore`의 `secrets/` 규칙이 `modules/secrets`를 가려서 첫 커밋에서 빠졌다가 `f8c64ec`로 고쳤다(`/secrets/`로 한정). 푸시 전에 새로 클론해서 검증한다.

## 다음 세션에서 할 일

1. 설계 문서의 결정 필요 항목을 차차 정한다(`docs/infra-repo-design.md` 10절). 먼저 Auth 프로필, 부하 테스트 토큰, 토픽 값.
2. `terraform` 설치(README 0단계). 이후 `.tf` 파일을 추가하면 `scripts/verify.sh`가 terraform을 요구한다.
3. `infra-04b`: 네트워크, IAM, GKE만 `-target`으로 올려 노드가 만들어지지 않는 원인을 찾는다(가설 1: 노드 서비스 계정에 `roles/container.defaultNodeServiceAccount` 추가, 가설 2: 노드 서비스 계정 미지정으로 범위 좁히기). 지금 GCP에는 DNS 스택 자원만 있다.
4. `infra-05`(Kafka), `infra-05b`(공통 Helm 차트). `infra-04b`에 의존한다.
