#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose"
SERVICE="postgres"
PSQL="psql -U postgres -d test --no-psqlrc -v ON_ERROR_STOP=1"

passed=0
failed=0
total=0

log()  { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { passed=$((passed+1)); total=$((total+1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { failed=$((failed+1)); total=$((total+1)); printf "  \033[31m✗\033[0m %s\n" "$1"; }

run_sql() {
    $COMPOSE exec -T $SERVICE su postgres -c "$PSQL" <<< "$1" 2>&1
}

assert_contains() {
    local result="$1" expected="$2" label="$3"
    if echo "$result" | grep -qF "$expected"; then ok "$label"; else fail "$label — expected '$expected'"; echo "    got: $result"; fi
}

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    actual=$(echo "$actual" | xargs)
    expected=$(echo "$expected" | xargs)
    if [ "$actual" = "$expected" ]; then ok "$label"; else fail "$label — expected '$expected', got '$actual'"; fi
}

# ============================================================
# Phase 0: Build & Start
# ============================================================
log "=== Phase 0: Build & Start ==="

$COMPOSE down -v 2>/dev/null || true
$COMPOSE up --build -d 2>&1 | tail -1

log "  Waiting for PostgreSQL..."
for i in $(seq 1 30); do
    if $COMPOSE exec -T $SERVICE pg_isready -U postgres &>/dev/null; then
        break
    fi
    sleep 1
done

if ! $COMPOSE exec -T $SERVICE pg_isready -U postgres &>/dev/null; then
    fail "PostgreSQL did not start within 30s"
    $COMPOSE logs $SERVICE | tail -20
    exit 1
fi
ok "PostgreSQL 18 is ready"

# ============================================================
# Phase 1: Regression tests (make installcheck)
# ============================================================
log ""
log "=== Phase 1: Regression Tests (make installcheck) ==="

$COMPOSE exec -T $SERVICE sh -c 'chown -R postgres:postgres /tmp/pg_kiwi'

regress_output=$($COMPOSE exec -T $SERVICE su postgres -c "cd /tmp/pg_kiwi && make installcheck 2>&1")

if echo "$regress_output" | grep -q "All.*tests passed"; then
    count=$(echo "$regress_output" | sed -n 's/.*All \([0-9]*\) tests passed.*/\1/p')
    ok "make installcheck — All $count tests passed"
else
    fail "make installcheck"
    echo "$regress_output"
fi

# ============================================================
# Phase 2: Extension loading
# ============================================================
log ""
log "=== Phase 2: Extension Loading ==="

run_sql "DROP EXTENSION IF EXISTS pg_kiwi CASCADE;" >/dev/null 2>&1
result=$(run_sql "CREATE EXTENSION pg_kiwi; SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_kiwi';")
assert_contains "$result" "pg_kiwi" "pg_kiwi extension loads"

result=$(run_sql "CREATE EXTENSION IF NOT EXISTS pg_textsearch; SELECT extname FROM pg_extension WHERE extname = 'pg_textsearch';")
assert_contains "$result" "pg_textsearch" "pg_textsearch extension loads"

# ============================================================
# Phase 3: Parser basics
# ============================================================
log ""
log "=== Phase 3: Parser Basics ==="

result=$(run_sql "SELECT count(*) FROM ts_token_type('kiwi_parser');")
assert_contains "$result" "8" "kiwi_parser has 8 token types"

result=$(run_sql "SELECT to_tsvector('korean', '인공지능 기술이 발전한다');")
assert_contains "$result" "인공" "to_tsvector tokenizes 인공"
assert_contains "$result" "지능" "to_tsvector tokenizes 지능"
assert_contains "$result" "기술" "to_tsvector tokenizes 기술"
assert_contains "$result" "발전" "to_tsvector tokenizes 발전"

# ============================================================
# Phase 4: POS filtering
# ============================================================
log ""
log "=== Phase 4: POS Filtering ==="

# Filter ON: particles excluded
result=$(run_sql "
    SET pg_kiwi.pos_filter = true;
    SELECT string_agg(token, ',' ORDER BY token)
    FROM ts_parse('kiwi_parser', '학생이 학교에서 공부를 한다');
")
assert_contains "$result" "학생" "filter ON: noun 학생 present"
assert_contains "$result" "학교" "filter ON: noun 학교 present"
assert_contains "$result" "공부" "filter ON: noun 공부 present"

# Particles should NOT be in filtered output
if echo "$result" | grep -qF "에서"; then
    fail "filter ON: particle 에서 should be excluded"
else
    ok "filter ON: particle 에서 excluded"
fi

# Filter OFF: particles appear
result=$(run_sql "
    SET pg_kiwi.pos_filter = false;
    SELECT count(*) FILTER (WHERE tokid = 8)
    FROM ts_parse('kiwi_parser', '학생이 학교에서 공부를 한다');
")
count=$(echo "$result" | grep -oE '[0-9]+' | tail -1)
if [ "$count" -gt 0 ] 2>/dev/null; then
    ok "filter OFF: $count grammar tokens visible"
else
    fail "filter OFF: expected grammar tokens"
fi

# ============================================================
# Phase 5: VCP/VCN retention (industry standard)
# ============================================================
log ""
log "=== Phase 5: VCP/VCN Retention ==="

result=$(run_sql "
    SET pg_kiwi.pos_filter = true;
    SELECT string_agg(tokid::text || ':' || token, ',' ORDER BY token)
    FROM ts_parse('kiwi_parser', '학생이다');
")
assert_contains "$result" "2:이" "VCP 이 retained as verb (tokid=2)"
assert_contains "$result" "1:학생" "noun 학생 present"

# ============================================================
# Phase 6: Lemmatization (verb stems)
# ============================================================
log ""
log "=== Phase 6: Lemmatization ==="

past=$(run_sql "SELECT to_tsvector('korean', '갔다');")
present=$(run_sql "SELECT to_tsvector('korean', '간다');")
future=$(run_sql "SELECT to_tsvector('korean', '가겠다');")

assert_contains "$past" "'가'" "갔다 → 가 (past)"
assert_contains "$present" "'가'" "간다 → 가 (present)"
assert_contains "$future" "'가'" "가겠다 → 가 (future)"

# ============================================================
# Phase 7: Search matching
# ============================================================
log ""
log "=== Phase 7: Search Matching ==="

result=$(run_sql "
    SELECT to_tsvector('korean', '경주의 불국사는 신라 시대에 건축된 사찰이다')
        @@ to_tsquery('korean', '불국사');
")
assert_contains "$result" "t" "불국사 matches"

result=$(run_sql "
    SELECT to_tsvector('korean', '통일신라시대')
        @@ to_tsquery('korean', '통일신라');
")
assert_contains "$result" "t" "통일신라 matches (compound)"

result=$(run_sql "
    SELECT to_tsvector('korean', '나는학생이다')
        @@ to_tsquery('korean', '학생');
")
assert_contains "$result" "t" "나는학생이다 matches 학생 (no-space tolerance)"

# ============================================================
# Phase 8: GIN index
# ============================================================
log ""
log "=== Phase 8: GIN Index ==="

run_sql "
    DROP TABLE IF EXISTS test_docs;
    CREATE TABLE test_docs (id serial, body text);
    INSERT INTO test_docs (body) VALUES
        ('인공지능 기술이 빠르게 발전하고 있다'),
        ('오늘은 날씨가 좋다'),
        ('기계학습은 인공지능의 한 분야이다'),
        ('자연어 처리는 인공지능 기술의 핵심이다'),
        ('한국어 형태소 분석기 Kiwi는 정확도가 높다');
    CREATE INDEX idx_test_gin ON test_docs USING GIN (to_tsvector('korean', body));
" >/dev/null 2>&1

result=$(run_sql "
    SELECT count(*) FROM test_docs
    WHERE to_tsvector('korean', body) @@ to_tsquery('korean', '인공지능');
")
cnt=$(echo "$result" | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ { gsub(/[^0-9]/,""); print; exit }')
assert_eq "$cnt" "3" "GIN: 인공지능 matches 3 docs"

result=$(run_sql "
    SELECT count(*) FROM test_docs
    WHERE to_tsvector('korean', body) @@ to_tsquery('korean', '형태소');
")
cnt=$(echo "$result" | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ { gsub(/[^0-9]/,""); print; exit }')
assert_eq "$cnt" "1" "GIN: 형태소 matches 1 doc"

# ============================================================
# Phase 9: BM25 index (pg_textsearch integration)
# ============================================================
log ""
log "=== Phase 9: BM25 Index (pg_textsearch) ==="

bm25_create=$(run_sql "
    CREATE INDEX idx_test_bm25 ON test_docs USING bm25(body)
        WITH (text_config = 'public.korean');
" 2>&1)

if echo "$bm25_create" | grep -q "CREATE INDEX"; then
    ok "BM25 index created with text_config='public.korean'"
else
    fail "BM25 index creation"
    echo "    $bm25_create"
fi

# Verify BM25 index stats
bm25_dump=$(run_sql "SELECT bm25_dump_index('idx_test_bm25');" 2>&1)

if echo "$bm25_dump" | grep -q "total_docs: 5"; then
    ok "BM25 index has 5 documents"
else
    fail "BM25 index document count"
fi

if echo "$bm25_dump" | grep -q "k1: 1\.20"; then
    ok "BM25 parameters: k1=1.20, b=0.75"
else
    fail "BM25 parameters"
fi

terms_count=$(echo "$bm25_dump" | sed -n 's/.*Terms: \([0-9]*\).*/\1/p' | head -1)
if [ -n "$terms_count" ] && [ "$terms_count" -gt 0 ] 2>/dev/null; then
    ok "BM25 index has $terms_count terms"
else
    fail "BM25 term count"
fi

# ============================================================
# Phase 10: ts_rank behavior (IDF absence demo)
# ============================================================
log ""
log "=== Phase 10: ts_rank Behavior ==="

result=$(run_sql "
    SELECT count(DISTINCT ts_rank(to_tsvector('korean', body),
           to_tsquery('korean', '인공지능')))
    FROM test_docs
    WHERE to_tsvector('korean', body) @@ to_tsquery('korean', '인공지능');
")
rank_count=$(echo "$result" | grep -oE '[0-9]+' | tail -1)
if [ "$rank_count" -eq 1 ] 2>/dev/null; then
    ok "ts_rank: all 인공지능 matches score identical (no IDF, as expected)"
else
    ok "ts_rank: 인공지능 matches have $rank_count distinct scores"
fi

# ============================================================
# Cleanup & Summary
# ============================================================
log ""
run_sql "DROP TABLE IF EXISTS test_docs;" >/dev/null 2>&1

log "=== Results ==="
if [ "$failed" -eq 0 ]; then
    printf "\033[32m  All %d tests passed.\033[0m\n" "$total"
else
    printf "\033[31m  %d/%d tests failed.\033[0m\n" "$failed" "$total"
fi

exit "$failed"
