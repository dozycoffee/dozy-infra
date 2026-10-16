# PROGRESS

## 현재 상태

- 저장소 뼈대와 GCP 준비 절차(README)까지 있다(`infra-01`, `infra-02`, `infra-02b` 완료). 테라폼과 차트는 아직 없다.
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
- TLS 인증서는 구글 관리형(Certificate Manager, DNS 인증, 와일드카드)으로 결정. 인증서는 `stacks/dns`에 둔다. Autopilot 외부 Ingress의 certificate map 지원과 비용은 확인 필요.

## 다음 세션에서 할 일

1. 설계 문서의 결정 필요 항목을 차차 정한다(`docs/infra-repo-design.md` 10절). 먼저 Auth 프로필, 부하 테스트 토큰, 토픽 값.
2. `terraform` 설치(README 0단계). 이후 `.tf` 파일을 추가하면 `scripts/verify.sh`가 terraform을 요구한다.
3. `infra-02c`(수동): 각자 `stacks/dns`를 apply하고 가비아에 NS를 등록한다. 먼저 가비아에서 NS 레코드 추가가 되는지 확인한다.
4. `infra-03`: `network` 모듈 작성.
