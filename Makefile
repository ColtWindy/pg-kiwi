EXTENSION = pg_kiwi
MODULE_big = pg_kiwi
PGFILEDESC = "pg_kiwi - Korean full-text search using Kiwi"
DATA = pg_kiwi--1.0.sql
OBJS = pg_kiwi.o

REGRESS = basic pos_filter lemma search bm25

PG_CPPFLAGS = -I/usr/local/include
SHLIB_LINK = -L/usr/local/lib -lkiwi -Wl,-rpath,/usr/local/lib

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Disable LLVM JIT bitcode (clang not needed for pg_kiwi)
with_llvm = no
