# PROGRESS

## 현재 상태

- 저장소 뼈대, GCP 준비 절차(README), DNS 스택(`stacks/dns`)까지 있다(`infra-01`, `infra-02`, `infra-02b`, `infra-02c` 완료). 나머지 테라폼 모듈과 차트는 아직 없다.
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
- TLS 인증서는 구글 관리형(Certificate Manager, DNS 인증, 와일드카드)으로 결정. 인증서는 `stacks/dns`에 둔다. Autopilot 외부 Ingress의 certificate map 지원과 비용은 확인 필요.

## 다음 세션에서 할 일

1. 설계 문서의 결정 필요 항목을 차차 정한다(`docs/infra-repo-design.md` 10절). 먼저 Auth 프로필, 부하 테스트 토큰, 토픽 값.
2. `terraform` 설치(README 0단계). 이후 `.tf` 파일을 추가하면 `scripts/verify.sh`가 terraform을 요구한다.
3. `infra-03`: `network` 모듈 작성.
