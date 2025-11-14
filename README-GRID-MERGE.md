# Grid Layer Merge - Manual QGIS Conversion

## 📋 Konsep Baru

Grid layer (yang sudah di-convert manual di QGIS) akan **dimerge sekali saja** ke dalam `glmap.mbtiles`. Setelah itu, proses selanjutnya hanya merge drone imagery baru.

## 🎯 Workflow

### Step 1: Convert Grid di QGIS (Manual - Sekali saja)

1. Buka QGIS
2. Load shapefile: `GRID_DRONE_36_HA_EKSISTING_POTENSI.shp`
3. Menu: **Processing** → **Toolbox** → **Raster tools** → **Rasterize (vector to raster)**
   - Atau gunakan plugin untuk convert ke MBTiles
4. Export hasil sebagai: `grid_layer.mbtiles`
5. Copy file ke server: `/app/data/grid_layer.mbtiles`

### Step 2: Run Generate Config

```bash
cd /app
./generate-config-incremental.sh
```

**Apa yang terjadi di run pertama:**
- ✅ Deteksi `grid_layer.mbtiles` ada
- ✅ Create `glmap.mbtiles` baru (kosong)
- ✅ **Merge grid ke glmap** (one-time operation)
- ✅ Create flag file: `.grid_merged`
- ✅ Merge semua drone imagery ke glmap
- ✅ Generate config.json

**File yang tercipta:**
```
/app/data/
├── grid_layer.mbtiles      # Grid original (tetap ada)
├── glmap.mbtiles            # Grid + Drone merged
├── .grid_merged             # Flag: grid sudah dimerge
└── .merged_files.log        # Log drone files yang sudah dimerge
```

### Step 3: Upload Drone File Baru

```bash
# Upload file baru ke /app/data/
scp new_drone_123.mbtiles server:/app/data/

# Run lagi
./generate-config-incremental.sh
```

**Apa yang terjadi di run berikutnya:**
- ✅ Deteksi flag `.grid_merged` → **Skip grid merge**
- ✅ Scan hanya file baru (belum ada di `.merged_files.log`)
- ✅ Merge hanya file baru ke glmap
- ⚡ **SUPER CEPAT** - tidak merge grid lagi!

## 🔧 Kontrol Manual

### Reset Grid Merge (Jika Perlu Merge Ulang)

```bash
# Hapus flag dan glmap
rm /app/data/.grid_merged
rm /app/data/glmap.mbtiles

# Run lagi - grid akan dimerge ulang
./generate-config-incremental.sh
```

### Reset Drone Merge (Tapi Keep Grid)

```bash
# Hapus glmap tapi keep flag grid
rm /app/data/glmap.mbtiles
rm /app/data/.merged_files.log

# Grid akan dimerge dari grid_layer.mbtiles (sekali)
# Semua drone files akan dimerge dari awal
./generate-config-incremental.sh
```

### Lihat Status

```bash
# Cek grid status
if [ -f /app/data/.grid_merged ]; then
    echo "Grid already merged"
else
    echo "Grid not merged yet"
fi

# Cek berapa drone files sudah dimerge
wc -l /app/data/.merged_files.log
```

## 📊 Performance

| Scenario | Time | Notes |
|----------|------|-------|
| First run (grid + 50 drones) | ~3-5 min | Grid merge + all drones |
| Add 1 new drone | ~2-5 sec | Only merge new file |
| Add 10 new drones | ~20-50 sec | Only merge 10 files |
| Reset & re-merge all | ~3-5 min | Same as first run |

## 🎨 Hasil Akhir

**Config.json:**
```json
{
  "data": {
    "glmap": {
      "mbtiles": "data/glmap.mbtiles"
    },
    "individual_file_1": {...},
    "individual_file_2": {...}
  }
}
```

**glmap.mbtiles contains:**
- Grid layer (pink tiles) - base
- Drone imagery - overlay

**Tileserver menampilkan:**
- 1 dataset utama: `glmap` (grid + drone merged)
- 50+ dataset individual (optional untuk view per-file)

## ⚠️ Important Notes

1. **Grid hanya merge sekali** - setelah ada flag `.grid_merged`, grid tidak akan dimerge lagi
2. **Grid layer original tetap ada** - `grid_layer.mbtiles` tidak dihapus, bisa digunakan untuk reset
3. **Incremental drone merge** - hanya file baru yang dimerge ke glmap
4. **Fast updates** - upload file baru jadi sangat cepat (2-5 detik)

## 🐛 Troubleshooting

**Q: Grid tidak muncul di map?**
```bash
# Check grid tiles
sqlite3 /app/data/grid_layer.mbtiles "SELECT COUNT(*) FROM tiles;"

# Check grid merged to glmap
sqlite3 /app/data/glmap.mbtiles "SELECT COUNT(*) FROM tiles WHERE zoom_level < 10;"
```

**Q: Ingin ganti grid dengan versi baru?**
```bash
# 1. Replace grid_layer.mbtiles dengan file baru
rm /app/data/grid_layer.mbtiles
cp /path/to/new_grid.mbtiles /app/data/grid_layer.mbtiles

# 2. Reset merge
rm /app/data/.grid_merged
rm /app/data/glmap.mbtiles

# 3. Run lagi
./generate-config-incremental.sh
```

**Q: Ingin merge ulang semua dari awal?**
```bash
# Nuclear option - reset everything
rm /app/data/.grid_merged
rm /app/data/.merged_files.log
rm /app/data/glmap.mbtiles

# Run - akan merge grid + semua drone dari awal
./generate-config-incremental.sh
```

## 🚀 Best Practices

1. **Keep grid_layer.mbtiles** - jangan dihapus, berguna untuk reset
2. **Backup .merged_files.log** - track history file yang sudah dimerge
3. **Monitor glmap size** - `du -h /app/data/glmap.mbtiles`
4. **Regular validation** - pastikan tiles count masuk akal

## 📝 Example Commands

```bash
# Full workflow dari awal
cd /app/data
# ... upload grid_layer.mbtiles dari QGIS
# ... upload drone files
cd /app
./generate-config-incremental.sh

# Check result
sqlite3 /app/data/glmap.mbtiles "SELECT COUNT(*) FROM tiles;"
cat /app/data/.merged_files.log

# Upload new file
scp new_file.mbtiles server:/app/data/
./generate-config-incremental.sh  # Fast!

# View in browser
# http://your-server/data/glmap/
```
