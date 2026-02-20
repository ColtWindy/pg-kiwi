# pg_kiwi

> Korean full-text search extension for PostgreSQL using Kiwi morphological analyzer

PostgreSQL에서 한국어 BM25 검색을 위한 C 확장입니다.

[Kiwi](https://github.com/bab2min/Kiwi) 형태소 분석기를 PostgreSQL에 직접 통합하여 `tsvector`/`tsquery` + GIN으로 한국어 전문 검색을 구현합니다.

[Docker Hub](https://hub.docker.com/r/coltwindyf/pg-kiwi)

## 사용법

```sql
CREATE EXTENSION pg_kiwi;
```

### 1. 테이블 생성

tsvector를 저장하지 않으면 검색할 때마다 Kiwi가 매 행마다 재호출됩니다.

```sql
CREATE TABLE documents (
    id serial PRIMARY KEY,
    content text,
    content_vec tsvector GENERATED ALWAYS AS (to_tsvector('korean', content)) STORED
);

CREATE INDEX idx_content ON documents USING GIN (content_vec);
```

### 2. 데이터 삽입

```sql
INSERT INTO documents (content) VALUES
    ('경주의 불국사는 신라 시대에 건축된 사찰이다'),
    ('인공지능 기술이 빠르게 발전하고 있다'),
    ('한국어 형태소 분석기 Kiwi는 정확도가 높다');
```

### 3. 검색

```sql
-- 단일 검색어
SELECT * FROM documents
WHERE content_vec @@ to_tsquery('korean', '불국사');

-- AND / OR
SELECT * FROM documents
WHERE content_vec @@ to_tsquery('korean', '인공지능 & 기술');

-- 관련도 랭킹
SELECT id, content, ts_rank(content_vec, q) AS rank
FROM documents, to_tsquery('korean', '기술') q
WHERE content_vec @@ q
ORDER BY rank DESC;
```

### 4. BM25 랭킹 (선택)

Docker 이미지에 [pg_textsearch](https://github.com/timescale/pg_textsearch) v0.5.1 (프리릴리스)이 포함되어 있습니다.

```sql
CREATE EXTENSION pg_textsearch;

CREATE INDEX idx_content_bm25 ON documents USING bm25(content)
WITH (text_config = 'public.korean');

SELECT id, content
FROM documents
ORDER BY content <@> '불국사'
LIMIT 10;
```

> pg_textsearch는 PostgreSQL 17/18만 지원하며 v1.0 미출시 상태입니다. 제약사항은 [pg_textsearch repo](https://github.com/timescale/pg_textsearch)를 참고하세요.

## 설정

| 파라미터             | 기본값                                         | 설명                            |
| -------------------- | ---------------------------------------------- | ------------------------------- |
| `pg_kiwi.model_path` | `/usr/local/share/kiwi_model/models/cong/base` | Kiwi 모델 경로 (SIGHUP)         |
| `pg_kiwi.pos_filter` | `on`                                           | 조사·어미·부호 필터링 (Session) |

## 실행

```bash
docker run -d --name pg-kiwi -p 6543:5432 -e POSTGRES_PASSWORD=postgres coltwindyf/pg-kiwi
psql -h localhost -p 6543 -U postgres
```

## 소스 빌드

PostgreSQL 18 개발 헤더와 Kiwi v0.22.2가 필요합니다.

```bash
make && make install
```

## 테스트

```bash
docker compose exec postgres sh -c "cd /tmp/pg_kiwi && make installcheck"
```

## 기여하기

[CONTRIBUTING.md](CONTRIBUTING.md)를 참고해주세요.

## 라이선스

[MIT](LICENSE). Kiwi는 [LGPL-2.1](https://github.com/bab2min/Kiwi/blob/main/LICENSE)로 동적 링크합니다.
