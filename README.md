# GL Server - Tileserver-GL dengan Drone Imagery & Grid Layer

🗺️ Automated tile server untuk mengelola drone imagery (JPG tiles) dan grid layer (vector tiles) dengan integrasi PostgreSQL dan cloud storage.

## 📋 Daftar Isi

- [Overview](#overview)
- [Flow](#flow)
- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## 🎯 Overview

GL Server adalah sistem otomasi untuk:
- **Merge incremental** drone imagery files (MBTiles format)
- **Generate** config.json untuk tileserver-gl
- **Optimize** grid layer dengan vector tiles
- **Convert** ke PMTiles (cloud-optimized format)
- **Upload** ke MinIO S3 storage
- **Integrate** dengan PostgreSQL database

### Komponen Utama

```
┌─────────────────────────────────────────────────────────────┐
│                     Drone MBTiles Files                     │
│              (Individual JPG tiles, zoom 16-22)             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│            generate-config-incremental.sh                   │
│                                                             │
│  1. Scan new files                                          │
│  2. Merge incrementally → glmap.mbtiles                     │
│  3. Generate config.json                                    │
│  4. Restart tileserver-gl                                   │
│  5. Convert to PMTiles                                      │
│  6. Upload to MinIO S3                                      │
│  7. Update PostgreSQL                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  glmap.mbtiles  │    │ grid_layer.mbtiles│
│  (Raster Drone) │    │  (Vector Grid)   │
│  Zoom 16-22     │    │  Zoom 0-14       │
│  999MB          │    │  73MB            │
└────────┬────────┘    └────────┬─────────┘
         │                      │
         ▼                      ▼
┌─────────────────────────────────────────┐
│       Tileserver-GL Container           │
│  http://server:8080/data/glmap/{z}/{x}/{y}.jpg   │
│  http://server:8080/data/grid_layer/{z}/{x}/{y}.pbf │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│         PMTiles (Cloud-Optimized)       │
│  https://api-minio.ptnaghayasha.com/    │
│  idpm/layers/glmap.pmtiles              │
└─────────────────────────────────────────┘
```

### 🚀 Automated Processing
- **Incremental merge** - Hanya merge file baru, skip yang sudah diproses
- **Auto-detection** - Scan otomatis file baru di direktori data
- **Progress tracking** - Log file untuk tracking merge history
- **Force rebuild** - Option untuk rebuild complete dari awal

### 📦 Multi-Format Support
- **MBTiles** - Raster (JPG) + Vector (PBF) tiles
- **PMTiles** - Cloud-optimized format untuk web mapping
- **Config.json** - Auto-generate untuk tileserver-gl

### ☁️ Cloud Integration
- **MinIO S3** - Auto-upload PMTiles dengan public access
- **Auto-installation** - Download dan install tools otomatis (pmtiles, mc)
- **Cross-platform** - Linux (Ubuntu) dan macOS support

### 🗄️ Database Integration
- **PostgreSQL** - Update coordinate metadata
- **Connection pooling** - Efficient database operations

### 🎨 Optimizations
- **Grid optimization** - 2.7GB → 73MB (97% reduction)
- **Zoom level separation** - Grid (0-14) + Drone (16-22)
- **Format separation** - Vector dan raster di file terpisah

## Flow
- IDPM Upload MBTiles
- Trigger minio (created new file .mbtiles) -> hit endpoint IDPM API minio-webhook
- minio-webhook.sh running /home/docker/tileserver-gl/scripts/generate-config.sh
- Download .mbtiles from minio to /home/docker/tileserver-gl/data
- Merge new .mbtiles from minio to glmap.minio
- Update postgres drone row, to update latitude, longitude, zoom, and (xyz)

### File Structure

```
gl-server/
├── data/                           # MBTiles files
│   ├── glmap.mbtiles              # Merged drone imagery (999MB)
│   ├── glmap.pmtiles              # Cloud-optimized (764MB)
│   ├── grid_layer.mbtiles         # Vector grid (73MB)
│   ├── .merged_files.log          # Tracking merged files
│   └── *.mbtiles                  # Individual drone files
├── styles/                         # Tileserver styles
│   └── default/
│       └── style.json
├── config.json                     # Tileserver configuration
├── generate-config-incremental.sh  # Main automation script
├── README.md                       # This file
├── QUICKSTART-UBUNTU.md           # Ubuntu installation guide
├── ARCHITECTURE.md                 # Architecture documentation
├── FRONTEND-INTEGRATION.md         # Leaflet integration guide
├── LEAFLET-VECTORGRID-GUIDE.md    # Vector tile rendering guide
└── README-incremental.sh          # Script feature documentation
```

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Tile Server** | tileserver-gl | Serve XYZ tiles |
| **Container** | Docker | Isolated environment |
| **Database** | PostgreSQL | Metadata storage |
| **Storage** | MinIO S3 | Cloud-optimized serving |
| **Tile Format** | MBTiles, PMTiles | Tile packaging |
| **Vector Tiles** | Tippecanoe | Grid optimization |
| **Shell** | POSIX sh | Cross-platform scripts |

### Prerequisites

- Ubuntu 24.04 or macOS
- Docker installed
- 4GB RAM minimum
- 50GB disk space

### Installation

**Ubuntu:**
```bash
# Clone repository
git clone git@github.com:suryahadiningrat/gl-server.git
cd gl-server

# Run installation
./install-tippecanoe.sh

# Setup data directory
mkdir -p data

# Run script (auto-installs pmtiles & mc)
./generate-config-incremental.sh
```

**Detailed guide:** [QUICKSTART-UBUNTU.md](QUICKSTART-UBUNTU.md)

### Basic Usage

```bash
# First time: merge all files
FORCE_REBUILD=true ./generate-config-incremental.sh

# Upload new drone file
cp new-drone.mbtiles data/

# Incremental merge
./generate-config-incremental.sh

# Check status
docker logs tileserver-zurich
```

## 📖 Usage

### Environment Variables

```bash
# Data directory (default: ./data)
export DATA_DIR=/app/data

# MinIO S3 configuration
export S3_HOST=http://52.76.171.132:9005
export S3_BUCKET=idpm
export S3_PATH=layers
export S3_ACCESS_KEY=your-access-key
export S3_SECRET_KEY=your-secret-key

# PostgreSQL configuration
export DB_HOST=172.26.11.153
export DB_PORT=5432
export DB_NAME=postgres
export DB_USER=postgres
export DB_PASSWORD=your-password

# Skip database update
export SKIP_DB_UPDATE=true

# Force complete rebuild
export FORCE_REBUILD=true
```

### Script Options

```bash
# Normal incremental merge
./generate-config-incremental.sh

# Force rebuild (merge all)
FORCE_REBUILD=true ./generate-config-incremental.sh

# Custom data directory
DATA_DIR=/custom/path ./generate-config-incremental.sh

# Skip database update
SKIP_DB_UPDATE=true ./generate-config-incremental.sh
```

### Access Tiles

**Grid Layer (Vector):**
```
http://your-server:8080/data/grid_layer/{z}/{x}/{y}.pbf
```

**Drone Layer (Raster):**
```
http://your-server:8080/data/glmap/{z}/{x}/{y}.jpg
```

**PMTiles (Cloud):**
```
https://api-minio.ptnaghayasha.com/idpm/layers/glmap.pmtiles
```

### Leaflet Integration

```javascript
// Grid layer (requires leaflet.vectorgrid)
L.vectorGrid.protobuf(
    'https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf',
    {
        vectorTileLayerStyles: {
            'grid_layer': {
                fillColor: '#90EE90',
                fillOpacity: 0.5,
                color: '#228B22',
                weight: 1
            }
        },
        minZoom: 0,
        maxZoom: 14
    }
).addTo(map);

// Drone layer
L.tileLayer(
    'https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg',
    {
        minZoom: 16,
        maxZoom: 22
    }
).addTo(map);
```

**Complete guide:** [FRONTEND-INTEGRATION.md](FRONTEND-INTEGRATION.md)

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | This file - project overview |
| [QUICKSTART-UBUNTU.md](QUICKSTART-UBUNTU.md) | Ubuntu installation guide |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture details |
| [FRONTEND-INTEGRATION.md](FRONTEND-INTEGRATION.md) | Leaflet integration guide |
| [LEAFLET-VECTORGRID-GUIDE.md](LEAFLET-VECTORGRID-GUIDE.md) | Vector tile rendering |
| [README-incremental.sh](README-incremental.sh) | Script features documentation |
| [CONVERSION-RESULT.md](CONVERSION-RESULT.md) | Format conversion results |
| [README-GRID-MERGE.md](README-GRID-MERGE.md) | Grid merge strategies |

## 🔧 Troubleshooting

### Container Restarting

```bash
# Check logs
docker logs tileserver-zurich

# Validate config
cat config.json | jq .

# Check file integrity
sqlite3 data/glmap.mbtiles "PRAGMA integrity_check;"
```

### PMTiles Upload Failed

```bash
# Test connection
mc alias set test $S3_HOST $S3_ACCESS_KEY $S3_SECRET_KEY --insecure
mc ls test/$S3_BUCKET/

# Manual upload
mc cp data/glmap.pmtiles test/$S3_BUCKET/$S3_PATH/
```

### Grid Not Showing in Leaflet

**Problem:** Grid layer tidak muncul di peta

**Solution:** Install `leaflet.vectorgrid` plugin:
```bash
npm install leaflet.vectorgrid
```

See: [LEAFLET-VECTORGRID-GUIDE.md](LEAFLET-VECTORGRID-GUIDE.md)

### Disk Space Issues

```bash
# Check disk usage
df -h
du -sh data/*.mbtiles

# Clean old files
rm data/*_trails.mbtiles  # Remove test files
```

### Permission Denied

```bash
# Fix ownership
sudo chown -R $USER:$USER data/
chmod -R 755 data/

# Fix script
chmod +x *.sh
```

## 🛠️ Development

### Prerequisites

```bash
# Install development tools
sudo apt-get install -y \
    sqlite3 \
    jq \
    curl \
    wget

# Install tippecanoe (for grid generation)
./install-tippecanoe.sh
```

### Testing

```bash
# Test script syntax
sh -n generate-config-incremental.sh

# Test with sample data
DATA_DIR=./test-data ./generate-config-incremental.sh

# Validate MBTiles
sqlite3 data/glmap.mbtiles "SELECT COUNT(*) FROM tiles;"

# Validate PMTiles
pmtiles show data/glmap.pmtiles
```

### Scripts

| Script | Purpose |
|--------|---------|
| `generate-config-incremental.sh` | Main automation script |
| `install-tippecanoe.sh` | Install tippecanoe for grid generation |
| `clean-glmap.sh` | Remove grid tiles from glmap |
| `check-mbtiles.sh` | Validate MBTiles integrity |
| `fix-config.sh` | Fix corrupted config.json |
| `test-db-update.sh` | Test PostgreSQL connection |

## 📊 Performance

### File Sizes

| File | Format | Size | Tiles | Zoom |
|------|--------|------|-------|------|
| glmap.mbtiles | Raster (JPG) | 999MB | 217,035 | 16-22 |
| glmap.pmtiles | PMTiles | 764MB | 217,035 | 16-22 |
| grid_layer.mbtiles | Vector (PBF) | 73MB | 68,731 | 0-14 |

### Optimization Results

- **Grid optimization:** 2.7GB → 73MB (97% reduction)
- **PMTiles compression:** 999MB → 764MB (23% reduction)
- **Incremental merge:** ~5s per file (vs 5min full rebuild)

## 🔐 Security

### Credentials Management

**⚠️ DO NOT commit credentials to git!**

Use environment variables:
```bash
# .env file (add to .gitignore)
export S3_ACCESS_KEY=your-key
export S3_SECRET_KEY=your-secret
export DB_PASSWORD=your-password

# Load before running
source .env
./generate-config-incremental.sh
```

### MinIO Access Control

```bash
# Set public read access
mc anonymous set download minio/idpm/layers/

# Revoke access
mc anonymous set none minio/idpm/layers/
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

### Code Style

- Use POSIX sh (not bash-specific syntax)
- Comment complex logic
- Test on Ubuntu 24.04 before submitting
- Update documentation

## 📝 License

This project is proprietary and confidential.

## 👥 Authors

- **Surya Hadiningrat** - Initial work

## 🙏 Acknowledgments

- [Tileserver-GL](https://github.com/maptiler/tileserver-gl) - Tile server
- [Tippecanoe](https://github.com/felt/tippecanoe) - Vector tile generation
- [PMTiles](https://github.com/protomaps/go-pmtiles) - Cloud-optimized format
- [MinIO](https://min.io/) - S3-compatible storage

## 📞 Support

For issues and questions:
- Check [Troubleshooting](#troubleshooting) section
- Review [Documentation](#documentation)
- Open GitHub issue

## 🗺️ Roadmap

- [x] Incremental merge system
- [x] PMTiles generation
- [x] MinIO S3 upload
- [x] Auto-installation tools
- [x] Linux compatibility

---

**Last Updated:** January 2025  
**Version:** 1.0.0  
**Status:** Production Ready
