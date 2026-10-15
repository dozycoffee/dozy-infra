# dozy-infra

Dozy 서비스를 GCP(GKE Autopilot)에 올리는 인프라 저장소다. 테라폼으로 클라우드 자원을, 공통 Helm 차트로 서비스를 배포한다. 학습용이며 실사용자는 없다.

전역 규칙(응답 언어, 커밋 규칙, 테스트, 비밀값)은 `~/.claude/CLAUDE.md`를 따른다. 여기에는 이 저장소에만 해당하는 내용을 적는다.

## 작업 전에 읽을 것

`CLAUDE.md` → `docs/` → `feature_list.json` → `PROGRESS.md` 순서로 읽는다.

- `docs/infra-repo-design.md`: 이 저장소의 구조와 결정. 설계가 바뀌면 이 문서를 같이 고친다.
- `docs/system-architecture.md`: 네트워크, 데이터, 관측 등 전체 아키텍처.

## 구조

```
terraform/modules/   network, gke, cloudsql, iam, secrets, kafka-managed
terraform/stacks/gcp 모듈을 호출하는 루트 모듈 (services 맵으로 DB·비밀값 선언)
charts/dozy-service  Spring Boot 서비스용 공통 Helm 차트
charts/kafka-self    단일 브로커 StatefulSet과 토픽 생성 Job
releases/            서비스별 values, 배포 순서(index.yaml), 공통 값(common.yaml)
topics/topics.yaml   Kafka 토픽 선언 (단일 원본)
third-party/         외부 Helm 차트 values
loadtest/            서비스 저장소 부하 도구를 클라우드에서 돌리는 래퍼
scripts/             verify.sh, up.sh, down.sh, deploy.sh, render-config.sh
```

## 규칙

- **공개 저장소다.** 비밀값, `*.tfvars`, 상태 파일, `generated/`는 절대 커밋하지 않는다. 비밀값은 Secret Manager에 두고 매니페스트에는 참조만 둔다.
- 서비스 코드는 이 저장소에 두지 않는다. 이미지는 `ghcr.io/dozycoffee/<서비스>:<X.Y.Z>`를 참조만 하고, `latest`는 쓰지 않는다.
- 팀원마다 자기 GCP 프로젝트를 쓴다. 사람마다 달라지는 값은 `terraform.tfvars`(커밋 안 함)로만 주입하고 코드에 박지 않는다. `terraform.tfvars.example`은 항상 최신으로 유지한다.
- Kafka는 `kafka_mode = self | managed` 변수로 전환한다. 서비스 values에 Kafka 주소나 보안 설정을 직접 박지 않고 `releases/generated/values.yaml`(terraform output 기반)로만 준다.
- Kafka 토픽은 `topics/topics.yaml`에 선언하고 서비스는 만들지 않는다. 브로커 자동 생성은 끈다. 값은 서비스의 이벤트 계약 문서를 기준으로 하고, 문서에 없는 값은 지어내지 않는다.
- 새 서비스는 `services` 맵, `releases/<서비스>.yaml`, `releases/index.yaml`(, `topics.yaml`) 추가로 끝나야 한다. 서비스 때문에 공통 차트나 모듈을 고쳐야 하면 설계를 먼저 의심한다.
- 클라우드에서는 `local` 프로필을 쓰지 않는다. 릴리스 전 서비스는 `sha-` 태그로 고정하고 `latest`, `main` 태그는 쓰지 않는다.
- 내릴 때는 `down.sh` 순서(쿠버네티스 리소스 삭제 → 남은 LB·디스크 확인 → `terraform destroy`)를 지킨다. 순서를 건너뛰면 비용이 계속 나간다.
- 새 클라우드 자원을 추가할 때는 상시 과금 여부를 PR 설명에 적는다.
- 확인하지 않은 사실(매니지드 Kafka 인증 방식 등)은 단정하지 않고 `docs/infra-repo-design.md`의 미결정 항목에 기록한다.

## 검증

```bash
scripts/verify.sh
```

셸 문법, `feature_list.json` 형식, `terraform fmt/validate`, `helm lint/template`(local 프로필 사용 차단 포함)를 검사한다. 검사 대상이 있는데 도구가 없으면 실패하고, 대상이 없어 건너뛴 항목은 출력에 남는다. 통과하지 못한 상태로 작업 완료를 선언하지 않는다.

## 작업 흐름

`feature_list.json`에서 `pending` 작업을 고르고(의존 작업이 `completed`인지 확인), `in_progress`로 바꿔 작업한 뒤, 검증을 통과하면 `completed`로 바꾸고 `PROGRESS.md`에 기록한다.
