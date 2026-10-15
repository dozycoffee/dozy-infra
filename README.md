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

## 준비물

- GCP 프로젝트와 결제 계정 (팀원마다 자기 것)
- `gcloud`, `terraform`, `kubectl`, `helm`

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
