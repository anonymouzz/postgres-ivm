BASE_OS ?= trixie
PG_VER := 16
BUILD_ID ?= 1

# Define PostGIS version based on the target OS
ifeq ($(BASE_OS),bullseye)
    POSTGIS_VER := 3.5
else
    POSTGIS_VER := 3.6
endif

IMAGE_NAME ?= postgresql-ivm
IMAGE_TAG := $(PG_VER)-$(POSTGIS_VER)-$(BASE_OS)
REGISTRY_IMAGE_PREFIX ?= anonymouz

# Architecture variable for GHA (e.g., linux/amd64)
# Defaults to local architecture if not provided
TARGET_PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: all build-load export-deb test clean mirror

all: build-load export-deb test

# Export .deb packages: honors TARGET_PLATFORM for multi-arch builds
export-deb:
	@echo "📤 Extracting .deb packages for $(BASE_OS) ($(TARGET_PLATFORM)) to ./dist..."
	@mkdir -p $(CURDIR)/dist
	docker buildx build --platform $(TARGET_PLATFORM) \
		--target exporter \
		--build-arg BASE_OS=$(BASE_OS) \
		--build-arg BUILD_ID=$(BUILD_ID) \
		--output type=local,dest=$(CURDIR)/dist \
		-f postgres/Dockerfile \
		postgres
	@echo "✅ Artifacts exported to $(CURDIR)/dist/"

# Build and load image to the local Docker daemon (host architecture only)
build-load:
	@echo "📦 Building $(IMAGE_NAME):$(IMAGE_TAG) for $(TARGET_PLATFORM) and loading to local docker..."
	docker buildx build --platform $(TARGET_PLATFORM) --load \
		--build-arg BASE_OS=$(BASE_OS) \
		$(BUILD_ARGS) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-f postgres/Dockerfile postgres

test:
	@echo "🧪 Running deep functional tests for $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker rm -f pg-test-run > /dev/null 2>&1 || true
	@docker run -d --name pg-test-run -e POSTGRES_PASSWORD=test $(IMAGE_NAME):$(IMAGE_TAG)
	@echo "⏳ Waiting for PostgreSQL to be fully ready..."
	@i=0; while [ $$i -lt 30 ]; do \
		READY_LOGS=$$(docker logs pg-test-run 2>&1 | grep -c "database system is ready to accept connections" || true); \
		if [ $$READY_LOGS -ge 2 ]; then \
			echo "✅ Server is up!"; \
			break; \
		fi; \
		echo "Waiting... ($$i)"; \
		i=$$((i + 1)); \
		sleep 2; \
	done; \
	if [ $$i -eq 30 ]; then echo "❌ Timeout waiting for Postgres"; docker logs pg-test-run; exit 1; fi
	@echo "🚀 Running Extension Tests..."
	@docker exec pg-test-run psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_ivm;"
	@docker exec pg-test-run psql -U postgres -c "CREATE TABLE test_u(id int primary key, n text); SELECT pgivm.create_immv('mv_test_u', 'SELECT * FROM test_u');"
	@docker exec pg-test-run psql -U postgres -c "INSERT INTO test_u VALUES (1, 'A');"
	@docker exec pg-test-run psql -U postgres -c "SELECT count(*) FROM mv_test_u;" | grep -q "1"
	@docker exec pg-test-run psql -U postgres -c "SELECT postgis_full_version();" | grep -q "POSTGIS"
	@echo "📊 Installed extension versions:"
	@docker exec pg-test-run psql -U postgres -c "SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis', 'pg_ivm');"
	@docker rm -f pg-test-run
	@echo "✅ All functional tests passed for $(IMAGE_TAG)!"

clean:
	rm -rf ./dist
