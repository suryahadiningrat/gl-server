#!/bin/sh

# Simplified grid conversion - use tippecanoe to create raster-like vector tiles

set -e

DATA_DIR="${DATA_DIR:-/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data}"
GRID_SHP="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI/GRID_36_HA_EKSISTING_POTENSI.shp"
GRID_GEOJSON="/tmp/grid_simple.geojson"
GRID_RASTER="$DATA_DIR/grid_layer_raster.mbtiles"

echo "═══════════════════════════════════════════════════════"
echo "  Simplified Grid Conversion (Raster-style Vector)"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check if shapefile exists
if [ ! -f "$GRID_SHP" ]; then
    echo "✗ Error: Shapefile not found at $GRID_SHP"
    exit 1
fi

# Check tippecanoe
if ! command -v tippecanoe >/dev/null 2>&1; then
    echo "✗ Error: tippecanoe not found. Please install:"
    echo "  brew install tippecanoe"
    exit 1
fi

# Step 1: Convert SHP to GeoJSON with style properties
echo "Step 1: Converting shapefile to GeoJSON..."
rm -f "$GRID_GEOJSON"

ogr2ogr -f GeoJSON \
    -t_srs EPSG:4326 \
    "$GRID_GEOJSON" \
    "$GRID_SHP"

echo "  ✓ GeoJSON created"

# Step 2: Use tippecanoe to create simplified tiles (more like raster)
echo ""
echo "Step 2: Creating simplified tiles..."

rm -f "$GRID_RASTER"

tippecanoe \
    -o "$GRID_RASTER" \
    -z 14 \
    -Z 0 \
    -l grid_layer \
    --drop-densest-as-needed \
    --simplification=2 \
    --no-tile-size-limit \
    --force \
    "$GRID_GEOJSON"

if [ ! -f "$GRID_RASTER" ]; then
    echo "✗ Error: Failed to create tiles"
    exit 1
fi

echo "  ✓ Tiles created"

# Step 3: Update metadata for better Leaflet compatibility
echo ""
echo "Step 3: Updating metadata..."

sqlite3 "$GRID_RASTER" "
    UPDATE metadata SET value = 'Grid 36 HA (Simplified)' WHERE name = 'name';
    UPDATE metadata SET value = 'Grid 36 HA' WHERE name = 'attribution';
    UPDATE metadata SET value = 'overlay' WHERE name = 'type';
    INSERT OR REPLACE INTO metadata (name, value) VALUES ('description', 'Grid layer optimized for Leaflet with vector tile plugin');
    VACUUM;
"

echo "  ✓ Metadata updated"

# Verify
echo ""
echo "Verifying tiles..."
TILE_COUNT=$(sqlite3 "$GRID_RASTER" "SELECT COUNT(*) FROM tiles;")
MIN_ZOOM=$(sqlite3 "$GRID_RASTER" "SELECT MIN(zoom_level) FROM tiles;")
MAX_ZOOM=$(sqlite3 "$GRID_RASTER" "SELECT MAX(zoom_level) FROM tiles;")

echo "  Total tiles: $TILE_COUNT"
echo "  Zoom range: $MIN_ZOOM - $MAX_ZOOM"

# Cleanup
rm -f "$GRID_GEOJSON"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✓ Conversion Complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Created: $GRID_RASTER"
echo ""
echo "⚠️  IMPORTANT: This is still vector tiles (PBF format)"
echo "    You need to use Leaflet with vector tile plugin:"
echo ""
echo "npm install leaflet.vectorgrid"
echo ""
echo "L.vectorGrid.protobuf("
echo "  'https://glserver.ptnaghayasha.com/data/grid_layer_raster/{z}/{x}/{y}.pbf',"
echo "  {"
echo "    vectorTileLayerStyles: {"
echo "      'grid_layer': {"
echo "        fillColor: '#90EE90',"
echo "        fill: true,"
echo "        fillOpacity: 0.5,"
echo "        stroke: true,"
echo "        color: '#228B22'"
echo "      }"
echo "    }"
echo "  }"
echo ").addTo(map);"
echo ""
