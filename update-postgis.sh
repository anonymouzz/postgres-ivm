#!/bin/sh

set -e

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"

# Extract version (e.g. 3.5)
POSTGIS_VERSION=$(psql -At -c "SELECT default_version FROM pg_available_extensions WHERE name='postgis'")

# Update PostGIS in every database
for db in $(psql -At -c "SELECT datname FROM pg_database WHERE datistemplate = false;"); do
    echo "Updating PostGIS extensions in $db to $POSTGIS_VERSION"
    psql --dbname="$db" -c "
        -- Upgrade PostGIS (includes raster)
        ALTER EXTENSION postgis UPDATE TO '$POSTGIS_VERSION';
        ALTER EXTENSION postgis_raster UPDATE TO '$POSTGIS_VERSION';
        ALTER EXTENSION postgis_topology UPDATE TO '$POSTGIS_VERSION';
        ALTER EXTENSION postgis_tiger_geocoder UPDATE TO '$POSTGIS_VERSION';
    "
done
