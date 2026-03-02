# Argument to choose the base OS (trixie or bullseye)
ARG BASE_OS=trixie
ARG REGISTRY=docker.io

FROM ${REGISTRY}/postgres:16-${BASE_OS} AS builder

ARG DEBIAN_FRONTEND=noninteractive

ARG TARGETARCH
ARG BUILD_ID

# Install build dependencies (binutils is required for readelf diagnostics).
RUN apt-get update && apt-get install -y --no-install-recommends \
    git make build-essential gcc postgresql-server-dev-16 \
    ca-certificates curl binutils && \
    rm -rf /var/lib/apt/lists/*

# Install nFPM (Modern Go-based replacement for FPM)
RUN NFPM_ARCH=$([ "$TARGETARCH" = "amd64" ] && echo "x86_64" || echo "arm64") && \
    curl -sfL "https://github.com/goreleaser/nfpm/releases/download/v2.45.0/nfpm_2.45.0_Linux_${NFPM_ARCH}.tar.gz" | \
    tar xz -C /usr/local/bin nfpm

WORKDIR /build
RUN git clone --depth 1 --branch v1.13 https://github.com/sraoss/pg_ivm.git .

# Copy the nFPM configuration file
COPY nfpm.yaml .

# --- Build and Architecture Fail-Fast Check ---
# We verify the resulting .so file before packaging to avoid "ghost" files on arm64.
RUN make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config && \
    make DESTDIR=/build/tmp_install install && \
    #
    # >>> ARCHITECTURE GATEKEEPER <<<
    EXPECTED_ELF=$([ "$TARGETARCH" = "amd64" ] && echo "X86-64" || echo "AArch64") && \
    echo "Verifying binary architecture... Expected: $EXPECTED_ELF" && \
    readelf -h /build/tmp_install/usr/lib/postgresql/16/lib/pg_ivm.so | grep -q "$EXPECTED_ELF" || \
    (echo "FATAL: Architecture mismatch detected! Binary is NOT $EXPECTED_ELF" && exit 1) && \
    #
    mkdir -p /build/tmp_install/usr/lib/postgresql/16/lib/bitcode/ && \
    # Export variables explicitly for nfpm
    export BUILD_ID=${BUILD_ID} && \
    export TARGETARCH=${TARGETARCH} && \
    nfpm pkg --packager deb --target .

# === Stage 2: Artifact Exporter ===
FROM scratch AS exporter
COPY --from=builder /build/*.deb /

# === Stage 3: Final Image ===
FROM ${REGISTRY}/postgres:16-${BASE_OS}

# Install PostGIS and related dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends \
    postgresql-16-postgis-3 \
    postgresql-16-postgis-3-scripts \
    wget gosu \
    && rm -rf /var/lib/apt/lists/*

# Install pg_ivm from the locally built .deb package
COPY --from=builder /build/*.deb /tmp/
RUN apt-get update && apt-get install -y /tmp/*.deb \
    && rm /tmp/*.deb \
    && rm -rf /var/lib/apt/lists/*

# Add automation/initialization scripts
COPY ./initdb-postgis.sh /docker-entrypoint-initdb.d/10_postgis.sh
COPY ./update-postgis.sh /usr/local/bin
RUN chmod +x /docker-entrypoint-initdb.d/10_postgis.sh /usr/local/bin/update-postgis.sh

# Registry Metadata
LABEL org.opencontainers.image.source="https://github.com/anonymouzz/postgresql-ivm-docker" \
      org.opencontainers.image.title="PostgreSQL 16 with pg_ivm" \
      org.opencontainers.image.description="PostgreSQL 16 with PostGIS and Incremental View Maintenance (pg_ivm)" \
      org.opencontainers.image.url="https://hub.docker.com/r/anonymouz/postgresql-ivm" \
      org.opencontainers.image.vendor="anonymouz" \
      org.opencontainers.image.licenses="PostgreSQL" \
      version.pg_ivm="1.13" \
      version.postgresql="16"

# Standard PostgreSQL Healthcheck.
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U postgres || exit 1
