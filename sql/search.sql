-- pg_kiwi end-to-end search tests
--
-- Tests from a developer/user perspective: "I have Korean documents
-- in PostgreSQL. Can I search them properly with pg_kiwi?"
--
-- Covers: GIN index, boolean operators, ranking, mixed content,
-- edge cases, and real-world search patterns.

DROP EXTENSION IF EXISTS pg_kiwi CASCADE;
CREATE EXTENSION pg_kiwi;
SET pg_kiwi.pos_filter = true;

-- ============================================================
-- Setup: realistic document collection
-- ============================================================

DROP TABLE IF EXISTS articles;
CREATE TABLE articles (
    id serial PRIMARY KEY,
    title text NOT NULL,
    content text NOT NULL
);

INSERT INTO articles (title, content) VALUES
    ('경주 불국사 여행기',
     '경주의 불국사는 신라 시대에 건축된 사찰이다. 석가탑과 다보탑이 유명하다.'),
    ('서울 맛집 탐방',
     '서울 강남에 새로 생긴 한식당에서 불고기와 비빔밥을 먹었다. 맛있었다.'),
    ('PostgreSQL 성능 튜닝',
     'PostgreSQL의 shared_buffers와 work_mem 설정은 성능에 큰 영향을 미친다.'),
    ('한국어 자연어 처리',
     '한국어는 교착어로 형태소 분석이 중요하다. Kiwi는 한국어 형태소 분석기이다.'),
    ('부산 해운대 여행',
     '부산 해운대 해수욕장에서 수영을 했다. 광안리 대교의 야경도 아름다웠다.'),
    ('기계학습 입문',
     '기계학습은 데이터에서 패턴을 학습한다. 딥러닝은 기계학습의 한 분야이다.'),
    ('경주 석굴암 방문',
     '석굴암은 경주 토함산에 위치한 석굴 사원이다. 불국사에서 버스로 이동할 수 있다.'),
    ('한국어 검색 엔진',
     '한국어 검색을 위해서는 형태소 분석이 필수적이다. BM25 알고리즘과 결합하면 좋은 결과를 얻는다.');

CREATE INDEX idx_articles_content ON articles
    USING GIN (to_tsvector('korean', content));

CREATE INDEX idx_articles_title ON articles
    USING GIN (to_tsvector('korean', title));

-- ============================================================
-- TEST 1: 단일 키워드 검색 (Single keyword search)
-- ============================================================

-- 1a. Exact noun search
SELECT 'T1a: single keyword' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '불국사')
ORDER BY id;

-- 1b. Verb search (lemmatized - "먹었다" in doc, "먹" in query)
SELECT 'T1b: verb search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '먹')
ORDER BY id;

-- ============================================================
-- TEST 2: 복합 검색 (Boolean operators)
-- ============================================================

-- 2a. AND: 경주 AND 불국사
SELECT 'T2a: AND search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '경주 & 불국사')
ORDER BY id;

-- 2b. OR: 서울 OR 부산
SELECT 'T2b: OR search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '서울 | 부산')
ORDER BY id;

-- 2c. NOT: 여행 NOT 서울 (title search)
SELECT 'T2c: NOT search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', title) @@ to_tsquery('korean', '여행 & !서울')
ORDER BY id;

-- ============================================================
-- TEST 3: 랭킹 (Ranking with ts_rank)
-- ============================================================

-- 3a. Documents about "경주" ranked by relevance
SELECT 'T3a: ranking' AS test, id, title,
       ts_rank(to_tsvector('korean', content), to_tsquery('korean', '경주')) AS rank
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '경주')
ORDER BY rank DESC;

-- 3b. Combined title + content ranking
SELECT 'T3b: title+content ranking' AS test, id, title,
       ts_rank(to_tsvector('korean', title), q) * 2.0
       + ts_rank(to_tsvector('korean', content), q) AS score
FROM articles, to_tsquery('korean', '한국어') AS q
WHERE to_tsvector('korean', title) @@ q
   OR to_tsvector('korean', content) @@ q
ORDER BY score DESC;

-- ============================================================
-- TEST 4: 교착어 검색 시나리오 (Agglutination in real search)
--
-- The document has "경주의", "건축된", "먹었다" etc.
-- Queries should match without the particles/endings.
-- ============================================================

-- 4a. "건축" should match "건축된" in document
SELECT 'T4a: agglutinated verb match' AS test,
       count(*) AS matches
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '건축');

-- 4b. "아름답" should match "아름다웠다" in document
SELECT 'T4b: irregular adj match' AS test,
       count(*) AS matches
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '아름답');

-- ============================================================
-- TEST 5: 한영 혼합 검색 (Mixed Korean + English)
-- ============================================================

-- 5a. English term in Korean document
SELECT 'T5a: english term search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', 'PostgreSQL')
ORDER BY id;

-- 5b. Technical term mixed search
SELECT 'T5b: mixed term search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', 'BM25')
ORDER BY id;

-- 5c. Korean + English combined
SELECT 'T5c: korean+english AND' AS test, id, title
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', 'PostgreSQL & 성능')
ORDER BY id;

-- ============================================================
-- TEST 6: 제목 + 본문 통합 검색 (Title + content search)
-- ============================================================

SELECT 'T6: title+content search' AS test, id, title
FROM articles
WHERE to_tsvector('korean', title || ' ' || content) @@ to_tsquery('korean', '맛집')
ORDER BY id;

-- ============================================================
-- TEST 7: 엣지 케이스 (Edge cases)
-- ============================================================

-- 7a. Empty string
SELECT 'T7a: empty string' AS test,
       to_tsvector('korean', '') AS result;

-- 7b. Whitespace only
SELECT 'T7b: whitespace only' AS test,
       to_tsvector('korean', '   ') AS result;

-- 7c. Numbers only
SELECT 'T7c: numbers only' AS test,
       to_tsvector('korean', '12345') AS result;

-- 7d. Single character
SELECT 'T7d: single char' AS test,
       to_tsvector('korean', '나') AS result;

-- 7e. Punctuation heavy text
SELECT 'T7e: punctuation heavy' AS test,
       to_tsvector('korean', '안녕하세요!!! 반갑습니다??? 좋아요~~~') AS result;

-- 7f. Very long repeated text (stress test - ensure no crash)
SELECT 'T7f: long text no crash' AS test,
       length(to_tsvector('korean',
           repeat('한국어 형태소 분석기를 이용한 전문 검색 테스트입니다. ', 100)
       )::text) > 0 AS has_result;

-- ============================================================
-- TEST 8: 인덱스 활용 확인 (GIN index usage)
-- ============================================================

-- 8a. Verify GIN index exists
SELECT 'T8a: index exists' AS test,
       count(*) AS index_count
FROM pg_indexes
WHERE tablename = 'articles'
  AND indexdef LIKE '%gin%';

-- 8b. Index scan (verify plan uses index)
EXPLAIN (COSTS OFF)
SELECT id FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '불국사');

-- ============================================================
-- TEST 9: UPDATE/DELETE 후 검색 정합성 (Data consistency)
-- ============================================================

-- 9a. Insert new doc and immediately search
INSERT INTO articles (title, content) VALUES
    ('제주도 여행', '제주도에서 한라산을 등반했다. 오름도 방문했다.');

SELECT 'T9a: search after insert' AS test,
       count(*) AS matches
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '한라산');

-- 9b. Update content and search reflects change
UPDATE articles SET content = '제주도에서 성산일출봉을 방문했다.'
WHERE title = '제주도 여행';

SELECT 'T9b: search after update' AS test,
       to_tsvector('korean', content) @@ to_tsquery('korean', '한라산') AS old_term,
       to_tsvector('korean', content) @@ to_tsquery('korean', '성산일출봉') AS new_term
FROM articles
WHERE title = '제주도 여행';

-- 9c. Delete and verify removal
DELETE FROM articles WHERE title = '제주도 여행';

SELECT 'T9c: search after delete' AS test,
       count(*) AS matches
FROM articles
WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '성산일출봉');

-- ============================================================
-- TEST 10: 실제 RAG 패턴 시뮬레이션
--
-- RAG retrieval: query → top-K documents → pass to LLM
-- ============================================================

-- 10a. Top-3 retrieval for a natural language query
SELECT 'T10a: top-3 retrieval' AS test, id, title,
       ts_rank(to_tsvector('korean', content), q) AS score
FROM articles, to_tsquery('korean', '경주 & 사찰') AS q
WHERE to_tsvector('korean', content) @@ q
ORDER BY score DESC
LIMIT 3;

-- 10b. Multi-field weighted retrieval
SELECT 'T10b: weighted retrieval' AS test, id, title,
       ts_rank(to_tsvector('korean', title), q) * 4.0
       + ts_rank(to_tsvector('korean', content), q) AS score
FROM articles, to_tsquery('korean', '형태소 | 검색') AS q
WHERE to_tsvector('korean', title || ' ' || content) @@ q
ORDER BY score DESC
LIMIT 3;

-- ============================================================
-- ASSERTIONS
-- ============================================================

DO $$
DECLARE
    cnt int;
BEGIN
    SET pg_kiwi.pos_filter = true;

    -- Assert: "불국사" finds exactly 2 documents (id=1, id=7)
    SELECT count(*) INTO cnt FROM articles
    WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '불국사');
    ASSERT cnt = 2,
        format('불국사 should match 2 docs, got %s', cnt);

    -- Assert: "경주" finds at least 2 documents
    SELECT count(*) INTO cnt FROM articles
    WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '경주');
    ASSERT cnt >= 2,
        format('경주 should match >= 2 docs, got %s', cnt);

    -- Assert: AND narrows results (경주 & 불국사 < 경주 alone)
    SELECT count(*) INTO cnt FROM articles
    WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '경주 & 불국사');
    ASSERT cnt >= 1 AND cnt <= 2,
        format('경주 & 불국사 should match 1-2 docs, got %s', cnt);

    -- Assert: agglutinated form matches base query
    -- "건축된" in doc should match "건축" query
    SELECT count(*) INTO cnt FROM articles
    WHERE to_tsvector('korean', content) @@ to_tsquery('korean', '건축');
    ASSERT cnt >= 1,
        format('건축 should match via agglutination, got %s', cnt);

    -- Assert: English terms searchable
    SELECT count(*) INTO cnt FROM articles
    WHERE to_tsvector('korean', content) @@ to_tsquery('korean', 'PostgreSQL');
    ASSERT cnt >= 1,
        format('PostgreSQL should be searchable, got %s', cnt);

    -- Assert: empty string produces empty tsvector (no crash)
    ASSERT to_tsvector('korean', '') = ''::tsvector,
        'Empty string must produce empty tsvector';

    RAISE NOTICE 'ALL SEARCH ASSERTIONS PASSED';
END;
$$;

-- Cleanup
DROP TABLE IF EXISTS articles;
DROP EXTENSION pg_kiwi;
