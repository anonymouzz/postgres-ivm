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

# Detect architecture for local builds
ARCH := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: all build-load export-deb test clean mirror

all: mirror build-load export-deb test

# Mirror the base image to the local registry
mirror:
	@echo "🪞 Mirroring base image: postgres:$(PG_VER)-$(BASE_OS)..."
	@if ! docker buildx inspect multi-builder > /dev/null 2>&1; then \
		docker buildx create --name multi-builder --driver docker-container --use; \
	fi
	@echo "FROM postgres:$(PG_VER)-$(BASE_OS)" | docker buildx build --builder multi-builder \
		--platform linux/amd64,linux/arm64 \
		-t $(REGISTRY_IMAGE_PREFIX)/postgres:$(PG_VER)-$(BASE_OS) \
		--push -

export-deb:
	@echo "📤 Extracting .deb packages for $(BASE_OS) to ./dist..."
	@mkdir -p $(CURDIR)/dist
	# We target the 'exporter' stage and tell buildx to output to a local directory
	docker buildx build --platform linux/$(ARCH) \
		--target exporter \
		--build-arg BASE_OS=$(BASE_OS) \
		--build-arg BUILD_ID=$(BUILD_ID) \
		--output type=local,dest=$(CURDIR)/dist \
		.
	@echo "✅ Artifacts exported to $(CURDIR)/dist/:"
	@ls -lh $(CURDIR)/dist/*.deb || echo "❌ No files found in $(CURDIR)/dist/"

build-load:
	@echo "📦 Building $(IMAGE_NAME):$(IMAGE_TAG) for architecture $(ARCH)..."
	docker buildx build --platform linux/$(ARCH) --load \
		--build-arg BASE_OS=$(BASE_OS) \
		$(BUILD_ARGS) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) .

test:
	@echo "🧪 Running deep functional tests for $(IMAGE_NAME):$(IMAGE_TAG)..."
	@docker rm -f pg-test-run > /dev/null 2>&1 || true
	@docker run -d --name pg-test-run -e POSTGRES_PASSWORD=test $(IMAGE_NAME):$(IMAGE_TAG)
	@echo "⏳ Waiting for PostgreSQL to be fully ready..."
	@i=0; while [ $$i -lt 30 ]; do \
		READY_LOGS=$$(docker logs pg-test-run 2>&1 | grep -c "database system is ready to accept connections"); \
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
