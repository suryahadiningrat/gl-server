# Bulk Upload MBTiles Script

Script untuk upload batch file MBTiles ke MinIO S3 dan insert metadata ke PostgreSQL database secara otomatis.

## 📋 Features

- ✅ Bulk upload multiple MBTiles files ke MinIO
- ✅ Auto-insert metadata ke PostgreSQL (`geoportal.pmn_drone_imagery`)
- ✅ Generate unique ID untuk setiap file (`DRN-XXXXXXXX`)
- ✅ Auto-generate title dari nama file
- ✅ Validasi MBTiles file sebelum upload
- ✅ Check file size otomatis
- ✅ Dry-run mode untuk testing
- ✅ Progress logging dan error handling
- ✅ Replace file jika sudah ada di MinIO
- ✅ Skip duplicate ID di database (ON CONFLICT DO NOTHING)

## 🚀 Quick Start

### Prerequisites

```bash
# Install MinIO Client (mc)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Install PostgreSQL Client
sudo apt-get install postgresql-client

# Install SQLite3 (untuk validasi MBTiles)
sudo apt-get install sqlite3

# Install bc (untuk kalkulasi ukuran file)
sudo apt-get install bc
```

### Basic Usage

```bash
# Upload semua MBTiles di folder
./bulk-upload-mbtiles.sh /path/to/mbtiles

# Dengan status custom
./bulk-upload-mbtiles.sh /path/to/mbtiles --status "Aktif"

# Dengan metadata lengkap
./bulk-upload-mbtiles.sh /path/to/mbtiles \
  --status "Aktif" \
  --operator "Team Survey A" \
  --location "Kalimantan Timur" \
  --bpdas "BWS01"

# Dry run (test tanpa execute)
./bulk-upload-mbtiles.sh /path/to/mbtiles --dry-run
```

## 📖 Usage

```bash
./bulk-upload-mbtiles.sh <source_folder> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `source_folder` | Path ke folder yang berisi file .mbtiles |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--status <status>` | Status untuk semua upload | `"Dalam Proses"` |
| `--operator <name>` | Nama operator | - |
| `--location <location>` | Label lokasi | - |
| `--bpdas <code>` | Kode BPDAS (auto uppercase) | - |
| `--dry-run` | Test mode tanpa execute | `false` |
| `--help` | Show help message | - |

### Valid Status Values

- `"Aktif"`
- `"Perlu Review"`
- `"Arsip"`
- `"Dalam Proses"` (default)
- `"Butuh Perbaikan"`

## 🔧 Configuration

### Environment Variables

Script support environment variables untuk konfigurasi. Bisa di-set di `.env` atau export sebelum run script.

#### MinIO Configuration

```bash
export S3_HOST="http://52.76.171.132:9005"
export S3_BUCKET="idpm"
export S3_PATH="layers/drone/mbtiles"
export S3_ACCESS_KEY="your-access-key"
export S3_SECRET_KEY="your-secret-key"
export S3_HOSTNAME="https://api-minio.ptnaghayasha.com"
```

#### PostgreSQL Configuration

```bash
export DB_HOST="172.26.11.153"
export DB_PORT="5432"
export DB_NAME="postgres"
export DB_USER="postgres"
export DB_PASSWORD="your-password"
```

### Default Values

Jika environment variable tidak di-set, script akan menggunakan default values:

```bash
# MinIO
S3_HOST="http://52.76.171.132:9005"
S3_BUCKET="idpm"
S3_PATH="layers/drone/mbtiles"
S3_HOSTNAME="https://api-minio.ptnaghayasha.com"

# PostgreSQL
DB_HOST="172.26.11.153"
DB_PORT="5432"
DB_NAME="postgres"
DB_USER="postgres"
DB_TABLE="geoportal.pmn_drone_imagery"
```

## 📝 Examples

### Example 1: Basic Upload

```bash
./bulk-upload-mbtiles.sh /app/data/drone-images
```

Output:
```
═══════════════════════════════════════════════════════════════
  Bulk Upload MBTiles to MinIO & PostgreSQL
═══════════════════════════════════════════════════════════════

Configuration:
  Source Folder: /app/data/drone-images
  Status: Dalam Proses
  Operator: <not set>
  Location: <not set>
  BPDAS: <not set>

[INFO] Found 5 MBTiles file(s)

═══════════════════════════════════════════════════════════════
[INFO] Processing: drone_image_001.mbtiles
═══════════════════════════════════════════════════════════════
[INFO] ID: DRN-A1B2C3D4
[INFO] Title: drone image 001
[INFO] Size: 125.50 MB
[INFO] Uploading: drone_image_001.mbtiles (125.50 MB)
[SUCCESS] ✓ Uploaded: drone_image_001.mbtiles
[INFO] Inserting to database: DRN-A1B2C3D4
[SUCCESS] ✓ Inserted to database: DRN-A1B2C3D4
[SUCCESS] ✓ Completed: drone_image_001.mbtiles

...

═══════════════════════════════════════════════════════════════
  SUMMARY
═══════════════════════════════════════════════════════════════

Total files: 5
✓ Success: 5
✗ Failed: 0

[SUCCESS] ✓ All files processed successfully!
```

### Example 2: With Metadata

```bash
./bulk-upload-mbtiles.sh /app/data/survey-kalsel \
  --status "Aktif" \
  --operator "Tim Survey BPDAS Barito" \
  --location "Kalimantan Selatan" \
  --bpdas "BARITO"
```

### Example 3: Dry Run Test

```bash
./bulk-upload-mbtiles.sh /app/data/test --dry-run
```

Output akan menampilkan apa yang akan dilakukan tanpa actually executing:
```
[WARN] ⚠ DRY RUN: Would upload file1.mbtiles to MinIO
[WARN] ⚠ DRY RUN: Would insert record to database
  ID: DRN-12345678
  Title: file1
  ...

[WARN] ⚠ DRY RUN completed - no actual changes were made
[INFO] Run without --dry-run to perform actual upload and database insert
```

### Example 4: With Custom Environment

```bash
# Create .env file
cat > .env << 'EOF'
S3_ACCESS_KEY=your-custom-key
S3_SECRET_KEY=your-custom-secret
DB_PASSWORD=your-db-password
EOF

# Load and run
source .env
./bulk-upload-mbtiles.sh /app/data/mbtiles
```

## 🔍 Process Flow

```
1. Scan source folder for *.mbtiles files
   ↓
2. For each file:
   ↓
   2.1. Validate MBTiles (check tiles table, count tiles)
   ↓
   2.2. Generate metadata:
        - ID: DRN-XXXXXXXX (random hex)
        - Title: dari filename (replace _ dan - dengan space)
        - Size: calculate file size in MB
   ↓
   2.3. Upload to MinIO:
        - Path: s3://idpm/layers/drone/mbtiles/filename.mbtiles
        - Public URL: https://api-minio.ptnaghayasha.com/idpm/layers/drone/mbtiles/filename.mbtiles
        - Replace if exists
   ↓
   2.4. Insert to PostgreSQL:
        - Table: geoportal.pmn_drone_imagery
        - ON CONFLICT DO NOTHING (skip if ID exists)
   ↓
3. Show summary (success/failed count)
   ↓
4. MinIO webhook auto-trigger generate-config script
```

## 📊 Database Schema

Script akan insert data ke table `geoportal.pmn_drone_imagery` dengan struktur:

```sql
INSERT INTO geoportal.pmn_drone_imagery (
    id,                    -- DRN-XXXXXXXX (unique)
    title,                 -- Generated from filename
    thumbnail_url,         -- NULL (untuk sementara)
    captured_at,           -- NULL (bisa diupdate manual nanti)
    captured_display,      -- NULL
    location_label,        -- Dari --location flag
    bpdas,                 -- Dari --bpdas flag (uppercase)
    format_label,          -- 'MBTILES'
    file_size_label,       -- '125.50 MB'
    operator_name,         -- Dari --operator flag
    mission_summary,       -- NULL
    weather_notes,         -- NULL
    status,                -- Dari --status flag (default: 'Dalam Proses')
    notes,                 -- 'Bulk upload otomatis dari berkas <filename>'
    storage_path,          -- https://api-minio.ptnaghayasha.com/idpm/layers/drone/mbtiles/<filename>
    map_preview_url        -- NULL
)
ON CONFLICT (id) DO NOTHING;
```

## ⚠️ Important Notes

### 1. Generate Config Script

**TIDAK PERLU** menjalankan `generate-config-incremental.sh` secara manual setelah bulk upload!

MinIO sudah dikonfigurasi dengan **webhook API** yang akan:
- Auto-detect file baru di bucket
- Trigger generate-config script otomatis
- Update tileserver configuration

### 2. File Validation

Script akan skip file jika:
- Bukan file valid SQLite database
- Tidak punya table `tiles`
- Tile count = 0
- File not readable

### 3. Duplicate Handling

- **MinIO**: File yang sudah ada akan di-replace
- **Database**: Record dengan ID sama akan di-skip (ON CONFLICT DO NOTHING)

### 4. Error Handling

Jika satu file gagal:
- Script akan continue ke file berikutnya
- Summary akan menampilkan failed count
- Exit code = 1 jika ada yang gagal

## 🐛 Troubleshooting

### Error: "mc (MinIO Client) not found"

```bash
# Install mc
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
```

### Error: "psql (PostgreSQL client) not found"

```bash
sudo apt-get update
sudo apt-get install postgresql-client
```

### Error: "Invalid MBTiles file"

Check file dengan:
```bash
sqlite3 your-file.mbtiles ".tables"
sqlite3 your-file.mbtiles "SELECT COUNT(*) FROM tiles;"
```

### Error: "Failed to configure MinIO client"

Check credentials:
```bash
mc alias set test http://52.76.171.132:9005 $S3_ACCESS_KEY $S3_SECRET_KEY --insecure
mc ls test/idpm/
```

### Error: "Connection refused" (PostgreSQL)

Check connection:
```bash
psql -h 172.26.11.153 -p 5432 -U postgres -d postgres -c "SELECT 1;"
```

### Database: "relation does not exist"

Pastikan table sudah ada:
```sql
-- Check if table exists
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'geoportal' 
    AND table_name = 'pmn_drone_imagery'
);
```

## 📚 Related Scripts

- `generate-config-incremental.sh` - Auto-triggered by MinIO webhook (tidak perlu manual)
- `clean-glmap.sh` - Remove grid tiles from merged file
- `install-tippecanoe.sh` - Install tippecanoe for grid generation

## 🔗 References

- MinIO API: http://52.76.171.132:9005
- MinIO Public: https://api-minio.ptnaghayasha.com
- PostgreSQL: 172.26.11.153:5432
- Database: postgres
- Table: geoportal.pmn_drone_imagery

## 📄 License

Proprietary - PT Naghayasha

---

**Last Updated:** November 2025  
**Version:** 1.0.0
