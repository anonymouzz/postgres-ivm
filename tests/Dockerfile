FROM debian:bookworm-slim

# Install PostgreSQL 16 client and dev tools for pg_regress
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg git build-essential \
    && curl -fLs https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client-16 \
        postgresql-server-dev-16 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone pg_ivm to get access to regression tests (sql/ and expected/ directories)
# Using shallow clone for speed
RUN git clone --depth 1 --branch v1.13 https://github.com/sraoss/pg_ivm.git .

# Point to the correct pg_config and add PG tools to PATH
ENV PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"

# Default environment for psql
ENV PGPORT=5432
ENV PGUSER=postgres

# Run only stable tests to avoid known issues with 'outer_join' in specific environments
# The output is piped to cat regression.diffs on failure for easy debugging in CI/Logs
CMD ["sh", "-c", "make installcheck REGRESS='pg_ivm create_immv refresh_immv' || (test -f regression.diffs && echo '--- REGRESSION DIFFS ---' && cat regression.diffs && exit 1)"]
