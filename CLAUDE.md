# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**GL Server** is an automated tile server pipeline for drone imagery. It merges MBTiles files uploaded to MinIO S3, generates a Tileserver-GL config, and updates PostgreSQL metadata — all triggered by a MinIO webhook. This is part of the Naghayasha / IDPM (Indonesian geospatial mapping) platform.

Two layers are served:
- `grid_layer.mbtiles` — vector grid (PBF, zoom 0–14), never merged, kept separate
- `glmap.mbtiles` — merged raster drone imagery (JPG, zoom 16–22)

## Running & Development

**Start the API container:**
```bash
docker-compose -f docker-api/docker-compose.yml up -d
```

**Trigger a manual tile merge/rebuild:**
```bash
./generate-config-incremental.sh                     # incremental (default)
FORCE_REBUILD=true ./generate-config-incremental.sh  # full rebuild
SKIP_DB_UPDATE=true ./generate-config-incremental.sh # skip postgres
```

**Validate a script without running:**
```bash
sh -n generate-config-incremental.sh
```

**Test MBTiles integrity:**
```bash
sqlite3 data/glmap.mbtiles "PRAGMA integrity_check;"
pmtiles show data/glmap.pmtiles
```

**Test webhook endpoint:**
```bash
curl -X GET http://localhost:3001/api/minio-webhook
curl -X POST http://localhost:3001/api/minio-webhook \
  -H "Content-Type: application/json" \
  -d '{"Records":[{"s3":{"bucket":{"name":"idpm"},"object":{"key":"file.mbtiles"}}}]}'
```

## Architecture

### Event-Driven Pipeline

```
MinIO (file upload)
  → MinIO webhook POST → /api/minio-webhook (Node.js h3 handler)
  → downloads .mbtiles via AWS SDK v3 → saves to DATA_DIR
  → exec generate-config.sh
  → merges files into glmap.mbtiles (mb-util)
  → writes config.json
  → docker restart tileserver-zurich
  → converts to PMTiles → uploads to MinIO
  → updates geoportal.pmn_drone_imagery in PostgreSQL
```

### Key Files

| File | Role |
|------|------|
| [generate-config-incremental.sh](generate-config-incremental.sh) | Main automation (814 lines) — merge, config, restart, upload, DB update |
| [docker-api/minio-webhook](docker-api/minio-webhook) | TypeScript h3 event handler — downloads file, calls config script |
| [config.json](config.json) | Tileserver-GL runtime config — regenerated on each merge |
| [styles/default/style.json](styles/default/style.json) | Mapbox GL v8 style — references both grid and glmap sources |
| [data/.merged_files.log](data/.merged_files.log) | Tracks merged files to prevent re-processing (idempotency key) |

### Incremental Merge Logic

`generate-config-incremental.sh` reads `.merged_files.log` to skip already-processed files. If no new files are detected, it exits silently. `FORCE_REBUILD=true` bypasses this check and remerges everything.

### Webhook Handler (`docker-api/minio-webhook`)

- Written as an h3 event handler (TypeScript, no `.ts` extension on the file)
- Uses AWS SDK v3 (`@aws-sdk/client-s3`) for MinIO compatibility (`forcePathStyle: true` when endpoint is non-AWS)
- Only processes `.mbtiles` files — ignores all others
- Env vars: `DATA_DIR`, `CONFIG_SCRIPT`, `S3_HOST`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`

## Environment Configuration

Copy `.env.example` to `.env` in both the root and `docker-api/` directories.

Key variables:
- `DATA_DIR` — where MBTiles are stored locally (default: `/app/data/tileserver`)
- `CONFIG_SCRIPT` — path to the shell script the webhook calls (default: `generate-config.sh`)
- `DOCKER_CONTAINER_NAME` — name of the tileserver container to restart (default: `tileserver-zurich`)
- `DB_TABLE` — PostgreSQL target table (default: `geoportal.pmn_drone_imagery`)
- `S3_HOST` / `S3_BUCKET` / `S3_HOSTNAME` — MinIO endpoint and bucket settings

## Important Constraints

- `grid_layer.mbtiles` must **never** be merged into `glmap.mbtiles`. It is a separate vector layer served independently.
- Docker socket is mounted so scripts can call `docker restart` from inside the container — requires `privileged: true` and `pid: host`.
- The tileserver container name (`DOCKER_CONTAINER_NAME`) must match exactly for restart to work.
- PostgreSQL is updated via direct `psql` calls in shell scripts — no ORM or connection pool.
