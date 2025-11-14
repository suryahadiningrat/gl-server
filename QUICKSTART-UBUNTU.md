# Quick Start Guide - Ubuntu Server

Panduan setup untuk Ubuntu 24.04 server dengan tileserver-gl dan generate-config script.

## 🖥️ Prerequisites

Server Ubuntu 24.04 dengan:
- Docker installed
- Minimum 4GB RAM
- 50GB storage

## 📦 Installation Steps

### 1. Install Required Packages

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install essential tools
sudo apt-get install -y \
    curl \
    wget \
    sqlite3 \
    git \
    unzip \
    jq

# Install Docker (if not installed)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Python3 and PostgreSQL client
sudo apt-get install -y \
    python3 \
    python3-pip \
    postgresql-client
```

### 2. Install PMTiles (Auto-installed by script)

Script akan otomatis install pmtiles, atau manual:

```bash
# Download PMTiles
PMTILES_VERSION="1.28.2"
wget https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_linux_x86_64.tar.gz

# Extract and install
tar -xzf go-pmtiles_${PMTILES_VERSION}_linux_x86_64.tar.gz
sudo mv pmtiles /usr/local/bin/
sudo chmod +x /usr/local/bin/pmtiles

# Verify
pmtiles --version
```

### 3. Install MinIO Client (Auto-installed by script)

Script akan otomatis install mc, atau manual:

```bash
# Download MinIO Client
wget https://dl.min.io/client/mc/release/linux-amd64/mc

# Install
chmod +x mc
sudo mv mc /usr/local/bin/

# Verify
mc --version
```

### 4. Install Tippecanoe (untuk Grid Layer)

```bash
# Install dependencies
sudo apt-get install -y \
    build-essential \
    libsqlite3-dev \
    zlib1g-dev

# Clone and build
git clone https://github.com/felt/tippecanoe.git
cd tippecanoe
make -j
sudo make install

# Verify
tippecanoe --version
```

### 5. Setup Project Directory

```bash
# Create project directory
sudo mkdir -p /app/data
sudo mkdir -p /app/styles/default
sudo chown -R $USER:$USER /app

# Clone or upload your scripts
cd /app
# Upload generate-config-incremental.sh and other files
```

### 6. Setup Tileserver-GL Container

```bash
# Pull tileserver-gl image
docker pull maptiler/tileserver-gl:latest

# Create and start container
docker run -d \
  --name tileserver-zurich \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /app/data:/data \
  -v /app/config.json:/config.json \
  -v /app/styles:/styles \
  maptiler/tileserver-gl:latest \
  --config /config.json

# Check logs
docker logs tileserver-zurich
```

## 🚀 Running the Script

### First Time Setup

```bash
cd /app

# Make script executable
chmod +x generate-config-incremental.sh

# Set data directory
export DATA_DIR=/app/data

# Run script (will auto-install pmtiles and mc if needed)
./generate-config-incremental.sh
```

### Upload New Drone Files

```bash
# Copy new mbtiles to /app/data/
scp your-new-file.mbtiles server:/app/data/

# Run script (incremental merge)
./generate-config-incremental.sh
```

### Force Rebuild (Merge All)

```bash
FORCE_REBUILD=true ./generate-config-incremental.sh
```

## 🔧 Configuration

### Environment Variables

```bash
# Data directory
export DATA_DIR=/app/data

# S3/MinIO settings (for PMTiles upload)
export S3_HOST=http://52.76.171.132:9005
export S3_BUCKET=idpm
export S3_PATH=layers
export S3_ACCESS_KEY=eY7VQA55gjPQu1CGv540
export S3_SECRET_KEY=u6feeKC1s8ttqU1PLLILrfyqdv79UOvBkzpWhIIn
export S3_HOSTNAME=https://api-minio.ptnaghayasha.com

# Skip database update
export SKIP_DB_UPDATE=true
```

### Create Systemd Service (Optional)

```bash
# Create service file
sudo cat > /etc/systemd/system/glmap-update.service << 'EOF'
[Unit]
Description=GLMap Config Generator
After=network.target docker.service

[Service]
Type=oneshot
User=ubuntu
WorkingDirectory=/app
Environment="DATA_DIR=/app/data"
ExecStart=/app/generate-config-incremental.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable glmap-update.service

# Run manually
sudo systemctl start glmap-update.service

# Check status
sudo systemctl status glmap-update.service
```

## 📊 What the Script Does

1. **Scans for new drone files** - Only merge files not in `.merged_files.log`
2. **Merges incrementally** - Fast! Only processes new files
3. **Generates config.json** - Tileserver-gl configuration
4. **Creates PMTiles** - Cloud-optimized format (auto-installs pmtiles if missing)
5. **Uploads to MinIO** - S3-compatible storage (auto-installs mc if missing)
6. **Restarts container** - Apply new configuration

## 🎯 Output Files

```
/app/data/
├── glmap.mbtiles          # Merged drone imagery (JPG tiles)
├── glmap.pmtiles          # Cloud-optimized version
├── grid_layer.mbtiles     # Grid overview (vector tiles)
├── .merged_files.log      # Tracking merged files
└── *.mbtiles              # Individual drone files

/app/config.json           # Tileserver configuration
```

## 🌐 Access URLs

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

## 🔍 Troubleshooting

### Script fails with "pmtiles not found"

Script will auto-install, but if fails:
```bash
# Manual installation
wget https://github.com/protomaps/go-pmtiles/releases/download/v1.28.2/go-pmtiles_1.28.2_linux_x86_64.tar.gz
tar -xzf go-pmtiles_1.28.2_linux_x86_64.tar.gz
sudo mv pmtiles /usr/local/bin/
```

### Script fails with "mc not found"

Script will auto-install, but if fails:
```bash
# Manual installation
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
```

### Container keeps restarting

```bash
# Check logs
docker logs tileserver-zurich

# Check config
cat /app/config.json | jq .

# Verify mbtiles files
sqlite3 /app/data/glmap.mbtiles "SELECT COUNT(*) FROM tiles;"
```

### Permission denied

```bash
# Fix ownership
sudo chown -R $USER:$USER /app/data
sudo chmod -R 755 /app/data
```

### Upload to MinIO fails

```bash
# Test mc connection
mc alias set test http://52.76.171.132:9005 $S3_ACCESS_KEY $S3_SECRET_KEY --insecure
mc ls test/idpm/

# Manual upload
mc cp /app/data/glmap.pmtiles test/idpm/layers/
```

## 📝 Maintenance

### View Merged Files

```bash
cat /app/data/.merged_files.log
```

### Reset and Merge All

```bash
rm /app/data/.merged_files.log
rm /app/data/glmap.mbtiles
FORCE_REBUILD=true ./generate-config-incremental.sh
```

### Check Disk Space

```bash
df -h /app
du -sh /app/data/*.mbtiles
```

### Backup Important Files

```bash
# Backup merged files
tar -czf glmap-backup-$(date +%Y%m%d).tar.gz \
    /app/data/glmap.mbtiles \
    /app/data/grid_layer.mbtiles \
    /app/data/.merged_files.log \
    /app/config.json

# Upload to S3
mc cp glmap-backup-*.tar.gz minio/idpm/backups/
```

## 🎉 Success Indicators

Script berhasil jika:
- ✅ No error messages
- ✅ `config.json` generated
- ✅ `glmap.pmtiles` created
- ✅ Upload to MinIO successful
- ✅ Container restarted
- ✅ Tiles accessible via HTTP

Test dengan browser:
```
http://your-server:8080/
```

## 🆘 Support

Issues? Check:
1. Logs: `docker logs tileserver-zurich`
2. Config: `cat /app/config.json | jq .`
3. Files: `ls -lh /app/data/`
4. Script output for errors
5. Disk space: `df -h`
