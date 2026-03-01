# PostgreSQL + pg_ivm + PostGIS

[![Docker Image CI](https://github.com/anonymouzz/postgres-ivm/actions/workflows/docker-ci.yml/badge.svg)](https://github.com/anonymouzz/postgres-ivm/actions)
![Docker Pulls](https://img.shields.io/docker/pulls/anonymouz/postgresql-ivm)
![Platforms](https://img.shields.io/badge/platforms-linux/amd64%20|%20linux/arm64-blue)

Custom PostgreSQL 16 Docker image with **Incremental View Maintenance (pg_ivm)** and **PostGIS** extensions pre-installed. 

This image is designed for high-performance applications requiring real-time materialized view updates and geospatial capabilities.

## Features

* **Incremental View Maintenance:** Powered by [pg_ivm](https://github.com/sraoss/pg_ivm), allowing materialized views to be updated instantly when base tables change.
* **Geospatial Support:** Includes [PostGIS](https://postgis.net/) (3.5/3.6).
* **Multi-Arch Support:** Fully compatible with `linux/amd64` and `linux/arm64` (including Raspberry Pi 4).
* **Production Ready:** Built on Debian (Bullseye/Trixie) with rigorous testing via QEMU and native ARM64 hardware.

## Supported Tags

| PostgreSQL | PostGIS | Base OS | Docker Tag |
| :--- | :--- | :--- | :--- |
| 16 | 3.6 | Debian Trixie | `16-3.6-trixie`, `latest` |
| 16 | 3.5 | Debian Bullseye | `16-3.5-bullseye` |

## Quick Start

```bash
docker run --name pg-ivm -e POSTGRES_PASSWORD=mysecretpassword -d anonymouz/postgresql-ivm:latest

```

Once started, enable the extensions:

```sql
CREATE EXTENSION pg_ivm;
CREATE EXTENSION postgis;

```

## Development & Build

The project includes a robust `Makefile` for local development and CI/CD integration.

### Build and test locally (native architecture):

```bash
make build-load
make test

```

### Export .deb packages:

```bash
make export-deb TARGET_PLATFORM=linux/arm64

```

## Testing Strategy

We take stability seriously. Every image is verified through:

1. **Functional Tests:** SQL-level validation of extension loading and IVM logic.
2. **Architecture Validation:** Native tests on Raspberry Pi 4 (ARM64) and emulated environments via QEMU.
3. **Matrix Testing:** Regression and isolation tests across different OS versions.

---

Built with ☕ and automation by [anonymouz](https://github.com/anonymouzz).
