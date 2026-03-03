# Argument to choose the base OS (trixie or bullseye)
ARG BASE_OS=trixie
ARG REGISTRY=docker.io

# === Stage 1: Builder ===
FROM ${REGISTRY}/postgres:16-${BASE_OS} AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG BUILD_ID

# Install build dependencies with retries to mitigate network flakiness
RUN apt-get update && \
    # Install libc-bin may avoid SIGSEGV в QEMU
    apt-get install -y -o Acquire::Retries=3 --no-install-recommends libc-bin || \
    (echo "Retrying libc-bin installation due to QEMU flake..." && apt-get install -y --fix-broken) && \
    apt-get install -y -o Acquire::Retries=3 --no-install-recommends \
    ca-certificates curl git binutils && \
    apt-get install -y -o Acquire::Retries=3 --no-install-recommends \
    make build-essential gcc postgresql-server-dev-16 \
    rm -rf /var/lib/apt/lists/*

# Install nFPM (Modern Go-based replacement for FPM)
RUN NFPM_ARCH=$([ "$TARGETARCH" = "amd64" ] && echo "x86_64" || echo "arm64") && \
    curl -sfL "https://github.com/goreleaser/nfpm/releases/download/v2.45.0/nfpm_2.45.0_Linux_${NFPM_ARCH}.tar.gz" | \
    tar xz -C /usr/local/bin nfpm

WORKDIR /build
RUN git clone --depth 1 --branch v1.13 https://github.com/sraoss/pg_ivm.git .
COPY nfpm.yaml .

# Build extension and verify binary architecture
RUN make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config && \
    make DESTDIR=/build/tmp_install install && \
    #
    # >>> ARCHITECTURE GATEKEEPER <<<
    # Using the correct path verified by your 'ls' output
    EXPECTED_ELF=$([ "$TARGETARCH" = "amd64" ] && echo "X86-64" || echo "AArch64") && \
    echo "Verifying binary architecture... Expected: $EXPECTED_ELF" && \
    readelf -h /build/tmp_install/usr/lib/postgresql/16/lib/pg_ivm.so | grep -q "$EXPECTED_ELF" || \
    (echo "FATAL: Architecture mismatch detected!" && exit 1) && \
    #
    # Ensure the bitcode directory exists for nFPM packaging consistency
    mkdir -p /build/tmp_install/usr/lib/postgresql/16/lib/bitcode/ && \
    #
    # Export variables for nFPM and package into .deb format
    export BUILD_ID=${BUILD_ID} && \
    export TARGETARCH=${TARGETARCH} && \
    nfpm pkg --packager deb --target .

# === Stage 2: Artifact Exporter ===
FROM scratch AS exporter
COPY --from=builder /build/*.deb /

# === Stage 3: Final Image ===
FROM ${REGISTRY}/postgres:16-${BASE_OS}

ARG DEBIAN_FRONTEND=noninteractive

# Copy the locally built .deb package from the builder stage
COPY --from=builder /build/*.deb /tmp/

# Consolidate OS updates, PostGIS installation, and local .deb package deployment
RUN apt-get update && \
    # Install libc-bin may avoid SIGSEGV в QEMU
    apt-get install -y -o Acquire::Retries=3 --no-install-recommends libc-bin || \
    (echo "Retrying libc-bin installation due to QEMU flake..." && apt-get install -y --fix-broken) && \
    apt-get dist-upgrade -y && \
    apt-get install -y -o Acquire::Retries=3 --no-install-recommends \
    postgresql-16-postgis-3 \
    postgresql-16-postgis-3-scripts \
    wget gosu \
    /tmp/*.deb && \
    rm /tmp/*.deb && \
    rm -rf /var/lib/apt/lists/*

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

# Standard PostgreSQL Healthcheck
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD pg_isready -U postgres || exit 1
