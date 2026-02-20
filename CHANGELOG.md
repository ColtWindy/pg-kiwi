# Changelog

## [1.0] - 2026-02-20

### 추가
- Kiwi v0.22.2 기반 PostgreSQL 파서 (`kiwi_parser`)
- 한국어 텍스트 검색 설정 (`korean`)
- 8개 토큰 타입 매핑 (명사, 동사, 형용사, 부사, 관형사, 숫자, 외국어, 미분류)
- POS 필터링 — 조사·어미·접사·부호 자동 제외 (설정 가능)
- 원형 복원 (lemmatization) — 활용형을 어간으로 변환
- GUC 파라미터: `pg_kiwi.model_path`, `pg_kiwi.pos_filter`
- Docker 빌드 환경 (PostgreSQL 18 + Alpine, 멀티스테이지)
- 회귀 테스트 5종: `basic`, `pos_filter`, `lemma`, `search`, `bm25`
- GitHub Actions CI (Docker 기반)
