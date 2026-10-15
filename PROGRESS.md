# PROGRESS

## 현재 상태

- 저장소 뼈대만 있다(`infra-01` 완료). 테라폼과 차트는 아직 없다.
- 설계는 `docs/infra-repo-design.md`에 있고, 미결정 항목 17개가 남아 있다(특히 매니지드 Kafka 인증, 부하 테스트 토큰 방식, 토픽 값, ghcr 공개 여부).
- 결정됨: 서비스 배포는 공통 Helm 차트, 대상은 auth/inventory/wms/catalog(store는 이미지 준비 후), Kafka 토픽은 중앙 선언, 클라우드에서 `local` 프로필 금지.
- `helm`은 설치되어 있고 `terraform`은 없다. `.tf` 파일을 추가하기 전에 설치해야 `scripts/verify.sh`가 통과한다.

## 세션 로그

### 2026-10-15

- 저장소 뼈대 추가: `CLAUDE.md`, `README.md`, `feature_list.json`, `PROGRESS.md`, `.gitignore`, `scripts/verify.sh`.
- 설계 문서 두 개를 `docs/`로 옮기고 `dozy-architecture/`는 삭제했다. 이제 `docs/`가 유일한 위치다.
- catalog 저장소를 확인(2026-10-15 `main` `3a7934a`)해 설계에 반영: catalog 포함, Helm 공통 차트, 토픽 중앙 선언, 프로필 정책, 서비스 추가 방식.
- `system-architecture.md`에 catalog 반영: 서비스 행·의존, 3절 다이어그램, 4.6 노출 경로, 5절 replicas·probe, 6절 데이터 계층, 13절 미결정(15~17 추가), 14절 구축 순서. 1절의 환경 문구와 Helm 전환도 맞췄다.
- OMS 언급을 모두 제거했다(서비스는 필요할 때 추가).
- 이니셜 커밋.

## 다음 세션에서 할 일

1. 설계 문서의 결정 필요 항목을 차차 정한다(`docs/infra-repo-design.md` 10절). 먼저 Auth 프로필, 부하 테스트 토큰, 토픽 값.
2. `infra-02`: GCP 프로젝트, 예산 알림, 상태 버킷 절차를 README에 정리한다.
3. `terraform` 설치 확인.
4. `infra-03`: `network` 모듈 작성.
