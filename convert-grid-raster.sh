#!/bin/bash

# Script alternatif untuk convert grid SHP ke raster mbtiles
# Menggunakan GDAL jika tippecanoe tidak tersedia

set -e

DATA_DIR="${DATA_DIR:-/app/data}"
GRID_DIR="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI 3"
GRID_SHP="$GRID_DIR/GRID_36_HA_EKSISTING_POTENSI.shp"
OUTPUT_MBTILES="$DATA_DIR/grid_layer.mbtiles"

echo "=== Converting Grid SHP to Raster MBTiles ==="
echo "Input: $GRID_SHP"
echo "Output: $OUTPUT_MBTILES"
echo ""

# Check if input exists
if [ ! -f "$GRID_SHP" ]; then
    echo "Error: Shapefile not found: $GRID_SHP"
    exit 1
fi

# Check if GDAL is available
if ! command -v gdal_rasterize >/dev/null 2>&1; then
    echo "Installing GDAL..."
    sudo apt-get update
    sudo apt-get install -y gdal-bin python3-gdal
fi

# Get bounds from shapefile
echo "Extracting bounds from shapefile..."
BOUNDS=$(ogrinfo -al -so "$GRID_SHP" | grep "Extent" | sed 's/Extent: //g' | tr -d '()' | sed 's/ - /,/g')
echo "Bounds: $BOUNDS"

# Convert to GeoTIFF first (for better control)
echo "Converting to GeoTIFF..."
TEMP_TIF="/tmp/grid_temp.tif"

gdal_rasterize \
    -burn 255 \
    -burn 182 \
    -burn 193 \
    -a_nodata 0 \
    -ts 4096 4096 \
    -ot Byte \
    -of GTiff \
    "$GRID_SHP" \
    "$TEMP_TIF"

echo "✓ GeoTIFF created"

# Convert GeoTIFF to MBTiles using gdal_translate
echo "Converting to MBTiles..."

gdal_translate \
    -of MBTiles \
    -co TILE_FORMAT=PNG \
    -co ZOOM_LEVEL_STRATEGY=AUTO \
    -co RESAMPLING=NEAREST \
    "$TEMP_TIF" \
    "$OUTPUT_MBTILES"

echo "✓ MBTiles created: $OUTPUT_MBTILES"

# Add metadata
echo "Adding metadata..."
sqlite3 "$OUTPUT_MBTILES" "
    UPDATE metadata SET value='Grid 36 HA' WHERE name='name';
    INSERT OR REPLACE INTO metadata (name, value) VALUES ('description', 'Grid layer for drone mapping areas');
    INSERT OR REPLACE INTO metadata (name, value) VALUES ('type', 'baselayer');
"

echo "✓ Metadata added"

# Cleanup
rm -f "$TEMP_TIF"

# Show info
echo ""
echo "=== MBTiles Info ==="
tile_count=$(sqlite3 "$OUTPUT_MBTILES" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
echo "Total tiles: $tile_count"

echo ""
echo "=== Conversion Complete ==="
echo "Grid layer ready at: $OUTPUT_MBTILES"