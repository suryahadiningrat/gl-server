#!/bin/sh

# Convert grid_layer from vector (PBF) to raster (PNG) for Leaflet compatibility

set -e

DATA_DIR="${DATA_DIR:-/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data}"
GRID_VECTOR="$DATA_DIR/grid_layer.mbtiles"
GRID_RASTER="$DATA_DIR/grid_layer_raster.mbtiles"
TEMP_DIR="/tmp/grid_conversion"

echo "═══════════════════════════════════════════════════════"
echo "  Grid Layer: Vector to Raster Conversion"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check if source exists
if [ ! -f "$GRID_VECTOR" ]; then
    echo "✗ Error: grid_layer.mbtiles not found at $GRID_VECTOR"
    exit 1
fi

# Check dependencies
if ! command -v ogr2ogr >/dev/null 2>&1; then
    echo "✗ Error: ogr2ogr not found. Please install GDAL:"
    echo "  brew install gdal"
    exit 1
fi

if ! command -v gdal_rasterize >/dev/null 2>&1; then
    echo "✗ Error: gdal_rasterize not found. Please install GDAL:"
    echo "  brew install gdal"
    exit 1
fi

echo "Source: $GRID_VECTOR"
echo "Target: $GRID_RASTER"
echo ""

# Clean up temp dir
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Step 1: Extract vector tiles to GeoJSON
echo "Step 1: Extracting vector data to GeoJSON..."
ogr2ogr -f GeoJSON \
    "$TEMP_DIR/grid.geojson" \
    "$GRID_VECTOR" \
    -sql "SELECT * FROM tiles LIMIT 1" \
    2>/dev/null || true

# Alternative: Use tippecanoe-decode if ogr2ogr doesn't work with mbtiles directly
if [ ! -f "$TEMP_DIR/grid.geojson" ] || [ ! -s "$TEMP_DIR/grid.geojson" ]; then
    echo "  Using alternative method: tile-join to extract..."
    
    # Use GDAL to read the MBTiles as vector
    ogrinfo -ro -al -geom=YES "$GRID_VECTOR" > "$TEMP_DIR/grid_info.txt" 2>&1 || true
    
    # Direct approach: Export all zoom levels
    echo "  Extracting tiles directly from MBTiles..."
    
    # Create a VRT file to read MBTiles as vector source
    cat > "$TEMP_DIR/grid.vrt" << EOF
<OGRVRTDataSource>
    <OGRVRTLayer name="grid_layer">
        <SrcDataSource>$GRID_VECTOR</SrcDataSource>
        <SrcLayer>grid_layer</SrcLayer>
    </OGRVRTLayer>
</OGRVRTDataSource>
EOF
    
    # Try to export using the VRT
    ogr2ogr -f GeoJSON \
        "$TEMP_DIR/grid.geojson" \
        "$TEMP_DIR/grid.vrt" \
        2>/dev/null || echo "  Note: VRT export attempted"
fi

# Step 2: Use original shapefile if GeoJSON export failed
GRID_SHP="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI/GRID_36_HA_EKSISTING_POTENSI.shp"

if [ ! -f "$TEMP_DIR/grid.geojson" ] || [ ! -s "$TEMP_DIR/grid.geojson" ]; then
    if [ -f "$GRID_SHP" ]; then
        echo "  Using original shapefile instead..."
        rm -f "$TEMP_DIR/grid.geojson"
        ogr2ogr -f GeoJSON \
            "$TEMP_DIR/grid.geojson" \
            "$GRID_SHP"
        echo "  ✓ Shapefile converted to GeoJSON"
    else
        echo "✗ Error: Cannot extract vector data and shapefile not found"
        exit 1
    fi
else
    echo "  ✓ Vector data extracted"
fi

# Step 3: Rasterize to PNG tiles using gdal2tiles
echo ""
echo "Step 2: Rasterizing to PNG tiles..."

# Get bounds from metadata
BOUNDS=$(sqlite3 "$GRID_VECTOR" "SELECT value FROM metadata WHERE name='bounds';" 2>/dev/null || echo "95.0,-11.0,141.0,6.0")
echo "  Bounds: $BOUNDS"

# Parse bounds (minlon,minlat,maxlon,maxlat)
MINLON=$(echo $BOUNDS | cut -d',' -f1)
MINLAT=$(echo $BOUNDS | cut -d',' -f2)
MAXLON=$(echo $BOUNDS | cut -d',' -f3)
MAXLAT=$(echo $BOUNDS | cut -d',' -f4)

# Create a temporary GeoTIFF
TEMP_GEOTIFF="$TEMP_DIR/grid.tif"

echo "  Creating GeoTIFF..."
gdal_rasterize \
    -a_srs EPSG:4326 \
    -te $MINLON $MINLAT $MAXLON $MAXLAT \
    -ts 4096 4096 \
    -burn 144 -burn 238 -burn 144 \
    -ot Byte \
    -of GTiff \
    -co COMPRESS=LZW \
    "$TEMP_DIR/grid.geojson" \
    "$TEMP_GEOTIFF"

if [ ! -f "$TEMP_GEOTIFF" ]; then
    echo "✗ Error: Failed to create GeoTIFF"
    exit 1
fi

echo "  ✓ GeoTIFF created"

# Step 4: Convert GeoTIFF to MBTiles with PNG tiles (all zoom levels 0-14)
echo ""
echo "Step 3: Converting to MBTiles (PNG tiles, zoom 0-14)..."

# Use gdal2tiles to generate tiles for all zoom levels
TILES_DIR="$TEMP_DIR/tiles"
rm -rf "$TILES_DIR"

echo "  Generating tiles for zoom 0-14..."
gdal2tiles.py \
    -z 0-14 \
    --processes=4 \
    "$TEMP_GEOTIFF" \
    "$TILES_DIR"

if [ ! -d "$TILES_DIR" ]; then
    echo "✗ Error: Failed to generate tiles"
    exit 1
fi

echo "  ✓ Tiles generated"

# Now convert tile directory to MBTiles
echo "  Packing tiles into MBTiles..."

# Create MBTiles database
rm -f "$GRID_RASTER"
sqlite3 "$GRID_RASTER" "
    CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
    CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
    CREATE TABLE metadata (name TEXT, value TEXT);
    CREATE UNIQUE INDEX metadata_index ON metadata (name);
"

# Import tiles from directory
for z in $(seq 0 14); do
    if [ -d "$TILES_DIR/$z" ]; then
        echo "    Packing zoom level $z..."
        for x_dir in "$TILES_DIR/$z"/*; do
            if [ -d "$x_dir" ]; then
                x=$(basename "$x_dir")
                for tile_file in "$x_dir"/*.png; do
                    if [ -f "$tile_file" ]; then
                        y=$(basename "$tile_file" .png)
                        # Convert TMS y to XYZ y
                        max_tile=$((2 ** z - 1))
                        xyz_y=$((max_tile - y))
                        # Insert tile
                        sqlite3 "$GRID_RASTER" "INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES ($z, $x, $xyz_y, readfile('$tile_file'));"
                    fi
                done
            fi
        done
    fi
done

if [ ! -f "$GRID_RASTER" ]; then
    echo "✗ Error: Failed to create raster MBTiles"
    exit 1
fi

echo "  ✓ Raster MBTiles created"

# Step 5: Update metadata
echo ""
echo "Step 4: Updating metadata..."

sqlite3 "$GRID_RASTER" "
    UPDATE metadata SET value = 'png' WHERE name = 'format';
    UPDATE metadata SET value = '0' WHERE name = 'minzoom';
    UPDATE metadata SET value = '14' WHERE name = 'maxzoom';
    UPDATE metadata SET value = 'Grid 36 HA (Raster)' WHERE name = 'name';
    UPDATE metadata SET value = 'Grid 36 HA' WHERE name = 'attribution';
    UPDATE metadata SET value = 'baselayer' WHERE name = 'type';
    INSERT OR REPLACE INTO metadata (name, value) VALUES ('description', 'Grid layer converted from vector to raster for Leaflet compatibility');
    VACUUM;
"

echo "  ✓ Metadata updated"

# Step 6: Verify
echo ""
echo "Step 5: Verifying raster tiles..."
TILE_COUNT=$(sqlite3 "$GRID_RASTER" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
MIN_ZOOM=$(sqlite3 "$GRID_RASTER" "SELECT MIN(zoom_level) FROM tiles;" 2>/dev/null || echo "?")
MAX_ZOOM=$(sqlite3 "$GRID_RASTER" "SELECT MAX(zoom_level) FROM tiles;" 2>/dev/null || echo "?")

echo "  Total tiles: $TILE_COUNT"
echo "  Zoom range: $MIN_ZOOM - $MAX_ZOOM"
echo "  Format: PNG (raster)"

# Cleanup
echo ""
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✓ Conversion Complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Created: $GRID_RASTER"
echo "Format: PNG raster tiles"
echo "Zoom: 0-14"
echo ""
echo "Next steps:"
echo "1. Add to config.json (will be done automatically)"
echo "2. Use in Leaflet:"
echo ""
echo "   L.tileLayer('https://glserver.ptnaghayasha.com/data/grid_layer_raster/{z}/{x}/{y}.png', {"
echo "       minZoom: 0,"
echo "       maxZoom: 14,"
echo "       opacity: 0.5"
echo "   }).addTo(map);"
echo ""
