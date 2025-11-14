# Grid Layer Conversion Result

## ✅ Conversion Successful

**Source:** `data/GRID_DRONE_36_HA_EKSISTING_POTENSI/GRID_36_HA_EKSISTING_POTENSI.shp`
**Output:** `data/grid_layer.mbtiles`

## 📊 Statistics

- **File Size:** 2.7 GB
- **Total Tiles:** 6,542,471 tiles
- **Format:** Vector tiles (PBF)
- **Zoom Levels:** 0-18
- **Total Features:** 238,807 polygons
- **Coverage:** Indonesia (Banyuasin, Sumatera Selatan area)

## 🔧 Conversion Process

```bash
# Step 1: Convert SHP to GeoJSON
ogr2ogr -f GeoJSON data/grid_temp.geojson \
  data/GRID_DRONE_36_HA_EKSISTING_POTENSI/GRID_36_HA_EKSISTING_POTENSI.shp

# Step 2: Convert GeoJSON to MBTiles
tippecanoe -o data/grid_layer.mbtiles \
  -l grid_layer \
  -z 18 -Z 0 \
  --drop-densest-as-needed \
  --extend-zooms-if-still-dropping \
  --force \
  data/grid_temp.geojson
```

## 📍 Metadata

```
name: data/grid_layer.mbtiles
description: data/grid_layer.mbtiles
version: 2
minzoom: 0
maxzoom: 18
center: 95.263138, 5.855792, 18
bounds: 95.141602, -10.941192, 141.004028, 5.878332
type: overlay
format: pbf (vector tiles)
```

## 🎨 Feature Properties

Each grid polygon contains:
- `id_zona`: Grid identifier (e.g., "51967_33212")
- `Shape_Leng`: Polygon perimeter
- `Shape_Area`: Polygon area
- `NAMOBJ`: Object name (e.g., "Banyuasin")
- `WADMKK`: District
- `WADMPR`: Province (e.g., "Sumatera Selatan")
- `BPDAS`: Watershed area (e.g., "MUSI")
- `KTTJ`: Land cover type (e.g., "LAHAN TERBUKA")
- `FS_KWS`: Forest status (e.g., "HP")
- `KWS`: Zone status (e.g., "DALAM KAWASAN")
- `DRONE`: Drone status (e.g., "NOT YET")

## 🚀 Next Steps

1. **Merge to glmap:**
   ```bash
   ./generate-config-incremental.sh
   ```
   This will merge grid_layer.mbtiles into glmap.mbtiles (one-time operation)

2. **Verify merge:**
   ```bash
   sqlite3 data/glmap.mbtiles "SELECT COUNT(*) FROM tiles;"
   ```

3. **Check if grid merged:**
   ```bash
   ls -la data/.grid_merged
   ```

## 🎯 Expected Result

After running `generate-config-incremental.sh`:
- Grid tiles will be merged into `glmap.mbtiles`
- Flag file `.grid_merged` will be created
- Future runs will skip grid merge (incremental only)
- Tileserver will display grid + drone imagery combined

## 📝 Notes

- Vector tiles format provides better zoom quality
- File size is large (2.7GB) due to high detail (238k+ features)
- Grid covers multiple provinces in Indonesia
- Tippecanoe automatically optimized tiles for web performance
