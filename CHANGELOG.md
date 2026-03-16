# Changelog

## [1.1.0] - 2026-03-16

### 변경
- pg_textsearch v0.5.1 → v0.6.1 업데이트
- Docker 이미지에 `shared_preload_libraries = 'pg_textsearch'` 설정 추가 (v0.6+ 필수)

### 업그레이드 (1.0 → 1.1.0)

pg_kiwi 파서 자체는 변경 없음. BM25(pg_textsearch)를 사용하지 않는다면 이미지만 교체하면 됩니다.

BM25를 사용 중인 경우:

```bash
# 1. docker-compose.yml에 command 추가 (커스텀 command를 쓰는 경우만)
command: postgres -c shared_preload_libraries=pg_textsearch

# 2. 컨테이너 재시작
docker compose down && docker compose up -d

# 3. 기존 BM25 인덱스 재생성
psql -c "REINDEX INDEX idx_your_bm25;"
```

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
