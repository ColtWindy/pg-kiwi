FROM postgres:18-alpine AS builder

RUN apk add --no-cache \
    build-base \
    cmake \
    git \
    wget \
    postgresql-dev

# Build Kiwi v0.22.2 from source (Alpine/musl requires source build)
RUN git clone --recursive --shallow-submodules --branch v0.22.2 --depth 1 \
        https://github.com/bab2min/Kiwi.git /tmp/kiwi && \
    cd /tmp/kiwi && mkdir build && cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DBUILD_SHARED_LIBS=ON \
        -DKIWI_BUILD_TEST=OFF && \
    make -j1 && \
    make install

# Download Kiwi model (~75MB)
RUN mkdir -p /usr/local/share/kiwi_model && \
    wget -qO- https://github.com/bab2min/Kiwi/releases/download/v0.22.2/kiwi_model_v0.22.2_base.tgz | \
    tar xzf - -C /usr/local/share/kiwi_model

# Disable LLVM JIT bitcode (clang not available in Alpine build)
RUN sed -i 's/with_llvm.*=.*yes/with_llvm = no/' \
        /usr/local/lib/postgresql/pgxs/src/Makefile.global

# Build pg_textsearch (BM25 index support)
RUN git clone --branch v0.6.1 --depth 1 https://github.com/timescale/pg_textsearch /tmp/pg_textsearch && \
    cd /tmp/pg_textsearch && \
    make && make install

# Build pg_kiwi extension
COPY pg_kiwi.c pg_kiwi.control pg_kiwi--1.0.sql Makefile /tmp/pg_kiwi/
COPY sql/ /tmp/pg_kiwi/sql/
COPY expected/ /tmp/pg_kiwi/expected/
RUN cd /tmp/pg_kiwi && make && make install

# --- Runtime image ---
FROM postgres:18-alpine AS runtime

RUN apk add --no-cache libstdc++ libgcc

# pg_textsearch v0.6+ requires shared_preload_libraries
RUN echo "shared_preload_libraries = 'pg_textsearch'" >> /usr/local/share/postgresql/postgresql.conf.sample

# Kiwi shared library
COPY --from=builder /usr/local/lib/libkiwi* /usr/local/lib/

# Kiwi model
COPY --from=builder /usr/local/share/kiwi_model /usr/local/share/kiwi_model

# pg_kiwi extension files
COPY --from=builder /usr/local/lib/postgresql/pg_kiwi.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/pg_kiwi.control /usr/local/share/postgresql/extension/
COPY --from=builder /usr/local/share/postgresql/extension/pg_kiwi--1.0.sql /usr/local/share/postgresql/extension/

# pg_textsearch extension files
COPY --from=builder /usr/local/lib/postgresql/pg_textsearch.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/pg_textsearch* /usr/local/share/postgresql/extension/

# --- Test image ---
FROM runtime AS test

RUN apk add --no-cache make gcc musl-dev perl diffutils

COPY --from=builder /tmp/pg_kiwi /tmp/pg_kiwi
COPY --from=builder /usr/local/lib/postgresql/pgxs /usr/local/lib/postgresql/pgxs
COPY --from=builder /usr/local/bin/pg_config /usr/local/bin/pg_config
RUN chown -R postgres:postgres /tmp/pg_kiwi
