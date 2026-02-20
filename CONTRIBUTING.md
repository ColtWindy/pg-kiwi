# 기여 가이드

pg_kiwi에 기여해주셔서 감사합니다.

## 개발 환경

Docker만 있으면 됩니다. Kiwi 소스 빌드와 모델 다운로드가 Dockerfile에 포함되어 있습니다.

```bash
# 빌드 및 실행
docker compose up --build

# 접속
psql -h localhost -p 6543 -U postgres -d test
```

## 빌드 및 테스트

```bash
# 회귀 테스트 실행
docker compose exec postgres sh -c "cd /tmp/pg_kiwi && make installcheck"

# 테스트 실패 시 diff 확인
docker compose exec postgres cat /tmp/pg_kiwi/regression.diffs
```

테스트를 추가하거나 출력이 변경된 경우:
```bash
# 새 expected 파일 생성
cp results/<test_name>.out expected/<test_name>.out
```

## 코드 구조

```
pg_kiwi.c            # 확장 전체 구현 (단일 파일)
pg_kiwi.control      # 확장 메타데이터
pg_kiwi--1.0.sql     # SQL 오브젝트 정의
Makefile              # PGXS 빌드
sql/                  # 회귀 테스트 SQL
expected/             # 테스트 예상 출력
Dockerfile            # 멀티스테이지 빌드 (builder → runtime → test)
docker-compose.yml    # 개발/테스트 환경
```

## Pull Request 가이드

1. 테스트를 포함해주세요 — 새 기능이면 `sql/`에 테스트 추가, 버그 수정이면 재현 케이스 추가
2. `make installcheck`가 통과해야 합니다
3. [Conventional Commits](https://www.conventionalcommits.org/) 형식을 따라주세요
   - `feat:` 새 기능
   - `fix:` 버그 수정
   - `docs:` 문서
   - `test:` 테스트
   - `refactor:` 리팩토링
4. PR 설명에 변경 이유와 테스트 방법을 적어주세요

## 이슈 보고

버그를 보고할 때 다음 정보를 포함해주세요:

- PostgreSQL 버전 (`SELECT version();`)
- Kiwi 버전
- OS / Docker 이미지
- 재현 SQL
- 예상 결과 vs 실제 결과

## 라이선스

기여하신 코드는 [MIT License](LICENSE)로 배포됩니다.
