#!/bin/sh

# ==============================================================================
# Multi-Arch Matrix Test Script (BusyBox / LibreELEC compatible)
#
# Purpose: Deep functional testing of PostgreSQL + pg_ivm images
# across different OS versions and architectures.
#
# Usage:
#   ./run_matrix.sh
#   REGISTRIES="my.priv.reg" ./run_matrix.sh
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Detect script directory to find Dockerfile reliably
SCRIPT_DIR=$(dirname "$0")

# --- Configuration (Can be overridden via environment variables) ---
REGISTRIES="${REGISTRIES:-"docker.io"}"
CUSTOM_IMAGE_PREFIX="${CUSTOM_IMAGE_PREFIX:-"anonymouz"}"
# Format: base_os:pg_version:postgis_version
OS_VERSIONS="${OS_VERSIONS:-"bullseye:16:3.5 trixie:16:3.6"}"

# Testing parameters
NET_NAME="pg-test-net"
COUNT_MAX=60
SUMMARY=""

# Timing variables
START_TOTAL=$(date +%s)
START_HUMAN_TOTAL=$(date '+%Y-%m-%d %H:%M:%S')

# --- Helper Functions ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    log "🧹 Cleaning up resources..."
    docker rm -f pg-db-test >/dev/null 2>&1 || true
    docker network rm "$NET_NAME" >/dev/null 2>&1 || true
}

# Ensure cleanup on script exit or manual interruption (Ctrl+C)
trap cleanup EXIT

# --- Main Execution ---

log "============================================================"
log "🚀 Starting Matrix Test on $(uname -m) (BusyBox mode)"
log "Script directory: $SCRIPT_DIR"

# 1. Build the Universal Tester image (contains pg_regress)
# Using the local Dockerfile located in the same directory as this script
log "Building universal tester image..."
docker build -t pg-universal-tester -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

for REG in $REGISTRIES; do
    for OS_ENTRY in $OS_VERSIONS; do
        START_ITER=$(date +%s)

        # Parse OS_ENTRY (e.g., bullseye:16:3.5) using 'cut'
        BASE_OS=$(echo "$OS_ENTRY" | cut -d: -f1)
        PG_VER=$(echo "$OS_ENTRY" | cut -d: -f2)
        GIS_VER=$(echo "$OS_ENTRY" | cut -d: -f3)
        TAG="${PG_VER}-${GIS_VER}-${BASE_OS}"

        # Determine full image name for testing
        if [ "$REG" = "docker.io" ]; then
            TEST_IMAGE="postgresql-ivm:${TAG}"
            # If the tag doesn't exist locally, assume it's under the custom prefix
            if [ -z "$(docker images -q "$TEST_IMAGE" 2>/dev/null)" ]; then
                TEST_IMAGE="${CUSTOM_IMAGE_PREFIX}/postgresql-ivm:${TAG}"
            fi
        else
            TEST_IMAGE="${REG}/postgresql-ivm:${TAG}"
        fi

        log "------------------------------------------------------------"
        log "TESTING IMAGE: $TEST_IMAGE"

        # Prepare network environment
        cleanup > /dev/null 2>&1 || true
        docker network create "$NET_NAME" >/dev/null

        # 2. Check for image presence (Local Cache vs Registry Pull)
        if ! docker image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
            log "Image not found locally. Attempting to pull..."
            if ! docker pull "$TEST_IMAGE"; then
                END_ITER=$(date +%s)
                log "❌ Pull failed for $TEST_IMAGE"
                SUMMARY="${SUMMARY}${TEST_IMAGE} | SKIP_PULL | $((END_ITER - START_ITER))s\n"
                continue
            fi
        fi

        # 3. Start Database Container
        docker run -d --name pg-db-test \
            --network "$NET_NAME" \
            -e POSTGRES_PASSWORD=postgres \
            "$TEST_IMAGE"

        # 4. Wait for Initialization (SRE-style log polling)
        log "Waiting for DB to be ready for connections..."
        COUNT=1
        READY=0
        while [ "$COUNT" -le "$COUNT_MAX" ]; do
            LOGS=$(docker logs pg-db-test 2>&1)
            # Both init process and the main daemon must be ready
            if echo "$LOGS" | grep -q "PostgreSQL init process complete" && \
               echo "$LOGS" | tail -n 10 | grep -q "database system is ready to accept connections"; then
                log "✅ Database is ready!"
                READY=1
                break
            fi

            [ $((COUNT % 10)) -eq 0 ] && log "Progress: $COUNT/$COUNT_MAX seconds..."
            sleep 1
            COUNT=$((COUNT + 1))
        done

        if [ "$READY" -eq 0 ]; then
            END_ITER=$(date +%s)
            log "❌ FAIL: Database startup timeout"
            SUMMARY="${SUMMARY}${TEST_IMAGE} | TIMEOUT | $((END_ITER - START_ITER))s\n"
            continue
        fi

        # 5. Run SQL Regression Tests
        log "Launching pg_universal_tester..."
        # Temporarily disable 'exit on error' to handle test failures gracefully
        set +e
        docker run --rm --name pg-tester-run --network "$NET_NAME" \
            -e PGHOST=pg-db-test \
            -e PGUSER=postgres \
            -e PGPASSWORD=postgres \
            pg-universal-tester
        RESULT=$?
        set -e

        # 6. Capture Results and Timing
        END_ITER=$(date +%s)
        DIFF_ITER=$((END_ITER - START_ITER))

        if [ "$RESULT" -eq 0 ]; then
            log "✅ PASS: Regression tests successful"
            SUMMARY="${SUMMARY}${TEST_IMAGE} | PASS | ${DIFF_ITER}s\n"
        else
            log "❌ FAIL: Regression tests failed"
            SUMMARY="${SUMMARY}${TEST_IMAGE} | FAIL | ${DIFF_ITER}s\n"
        fi

        cleanup > /dev/null 2>&1 || true
    done
done

# --- Final Summary Report ---
END_TOTAL=$(date +%s)
DIFF_TOTAL=$((END_TOTAL - START_TOTAL))

echo ""
echo "================================================================================"
log "📊 FINAL MATRIX SUMMARY ($(uname -m))"
log "Started:  $START_HUMAN_TOTAL"
log "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
echo "--------------------------------------------------------------------------------"
# Using printf for alignment as 'column' utility is missing on LibreELEC/BusyBox
printf "%-45s | %-10s | %-10s\n" "IMAGE" "RESULT" "TIME"
echo "--------------------------------------------------------------------------------"
printf "$SUMMARY" | while read -r line; do
    [ -z "$line" ] && continue
    IMG=$(echo "$line" | cut -d'|' -f1)
    RES=$(echo "$line" | cut -d'|' -f2)
    DUR=$(echo "$line" | cut -d'|' -f3)
    printf "%-45s | %-10s | %-10s\n" "$IMG" "$RES" "$DUR"
done
echo "--------------------------------------------------------------------------------"
log "TOTAL DURATION: ${DIFF_TOTAL}s"
echo "================================================================================"
