-- pg_kiwi regression tests

-- Install extension
DROP EXTENSION IF EXISTS pg_kiwi CASCADE;
CREATE EXTENSION pg_kiwi;

-- Verify GUC variables
SHOW pg_kiwi.model_path;
SHOW pg_kiwi.pos_filter;

-- Test lextype: list supported token types
SELECT * FROM ts_token_type('kiwi_parser');

-- Test basic parsing (HANDOFF verification case)
SELECT * FROM ts_parse('kiwi_parser', '경주 불국사는 신라 시대에 건축된 사찰이다');

-- Test to_tsvector (HANDOFF case: 등산로이다)
SELECT to_tsvector('korean', '등산로이다');

-- Test to_tsquery
SELECT to_tsquery('korean', '등산');

-- Test search matching: 불국사
SELECT to_tsvector('korean', '경주의 불국사는 신라 시대에 건축된 사찰이다')
    @@ to_tsquery('korean', '불국사');

-- Test search matching: 통일신라 (HANDOFF verification case)
SELECT to_tsvector('korean', '통일신라시대')
    @@ to_tsquery('korean', '통일신라');

-- Test POS filter off: should include particles and endings
SET pg_kiwi.pos_filter = false;
SELECT * FROM ts_parse('kiwi_parser', '나는 학생이다');

-- Test POS filter on: should exclude particles and endings
SET pg_kiwi.pos_filter = true;
SELECT * FROM ts_parse('kiwi_parser', '나는 학생이다');

-- Cleanup
DROP EXTENSION pg_kiwi;
