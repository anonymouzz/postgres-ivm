#!/bin/sh

set -e

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"

# Create the 'template_postgis' template db if it doesn't exist
psql << 'EOSQL'
SELECT 'CREATE DATABASE template_postgis IS_TEMPLATE true' 
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'template_postgis')\gexec
EOSQL

# Load PostGIS into both 'template_postgis' and the default database
for db in template_postgis "${POSTGRES_DB:-postgres}"; do
	echo "Loading PostGIS extensions into $db"
	psql --dbname="$db" << 'EOSQL'
		CREATE EXTENSION IF NOT EXISTS postgis;
		CREATE EXTENSION IF NOT EXISTS postgis_topology;
		CREATE EXTENSION IF NOT EXISTS postgis_raster;
		CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
		CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
EOSQL
done
