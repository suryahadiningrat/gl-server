#!/bin/bash

# Enhanced generate-config.sh dengan incremental merge dan grid layer
# Features:
# 1. Incremental merge - hanya merge file baru
# 2. Grid layer integration - add SHP as base layer

set -e

# Environment detection
if [ -n "$DATA_DIR" ]; then
    echo "Using provided DATA_DIR: $DATA_DIR"
elif [ -d "/app/data/tileserver" ]; then
    DATA_DIR="/app/data/tileserver"
elif [ -d "/app/data" ]; then
    DATA_DIR="/app/data"
else
    echo "Error: Data directory not found"
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-/app/config.json}"
STYLE_DIR="${STYLE_DIR:-/app/styles/default}"
STYLE_FILE="${STYLE_FILE:-$STYLE_DIR/style.json}"
GLMAP_FILE="${GLMAP_FILE:-$DATA_DIR/glmap.mbtiles}"
GRID_MBTILES="${GRID_MBTILES:-$DATA_DIR/grid_layer.mbtiles}"
MERGE_LOG="${MERGE_LOG:-$DATA_DIR/.merged_files.log}"
TEMP_CONFIG="${TEMP_CONFIG:-/tmp/config_temp.json}"

# Grid shapefile paths
GRID_DIR="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI 3"
GRID_SHP="$GRID_DIR/GRID_36_HA_EKSISTING_POTENSI.shp"

echo "=== Enhanced Generate Config Script ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"
echo "Grid directory: $GRID_DIR"
echo ""

# Create directories
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

# Create enhanced style with multiple layers
if [ ! -f "$STYLE_FILE" ] || [ "$FORCE_STYLE_UPDATE" = "true" ]; then
    echo "Creating multi-layer style.json..."
    cat > "$STYLE_FILE" << 'EOF'
{
  "version": 8,
  "name": "Drone Mapping Style",
  "sources": {
    "grid": {
      "type": "vector",
      "tiles": ["/data/grid_layer/{z}/{x}/{y}.pbf"],
      "minzoom": 0,
      "maxzoom": 14
    },
    "glmap": {
      "type": "raster",
      "tiles": ["/data/glmap/{z}/{x}/{y}.jpg"],
      "tileSize": 256,
      "minzoom": 0,
      "maxzoom": 21
    }
  },
  "layers": [
    {
      "id": "grid-fill",
      "type": "fill",
      "source": "grid",
      "source-layer": "grid_layer",
      "paint": {
        "fill-color": "rgba(255, 182, 193, 0.3)",
        "fill-outline-color": "#0000ff"
      }
    },
    {
      "id": "grid-line",
      "type": "line",
      "source": "grid",
      "source-layer": "grid_layer",
      "paint": {
        "line-color": "#0000ff",
        "line-width": 1
      }
    },
    {
      "id": "glmap-raster",
      "type": "raster",
      "source": "glmap",
      "paint": {
        "raster-opacity": 1
      }
    }
  ]
}
EOF
    echo "✓ Enhanced style created with grid + glmap layers"
fi

# Validation function
is_valid_mbtiles() {
    local file="$1"
    [ -r "$file" ] || return 1
    sqlite3 "$file" ".tables" 2>/dev/null | grep -q "tiles" || return 1
    tiles=$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    [ "$tiles" -gt 0 ] || return 1
    return 0
}

# Check if file has been merged before
is_already_merged() {
    local file="$1"
    [ -f "$MERGE_LOG" ] && grep -q "^$(basename "$file")$" "$MERGE_LOG"
}

# Add file to merge log
mark_as_merged() {
    local file="$1"
    echo "$(basename "$file")" >> "$MERGE_LOG"
}

# Step 1: Convert grid SHP to mbtiles (only once)
echo "=== Step 1: Processing Grid Layer ==="
if [ -f "$GRID_SHP" ] && [ ! -f "$GRID_MBTILES" ]; then
    echo "Converting grid shapefile to mbtiles..."
    
    # Check if tippecanoe is available
    if command -v tippecanoe >/dev/null 2>&1; then
        echo "Using tippecanoe for vector tiles..."
        tippecanoe -o "$GRID_MBTILES" \
            -l grid_layer \
            -z 14 -Z 0 \
            --drop-densest-as-needed \
            --extend-zooms-if-still-dropping \
            "$GRID_SHP" && echo "✓ Grid layer created" || {
                echo "✗ Failed to create grid layer with tippecanoe"
            }
    elif command -v ogr2ogr >/dev/null 2>&1 && command -v mb-util >/dev/null 2>&1; then
        echo "Using ogr2ogr + mb-util for conversion..."
        # Convert to GeoJSON first
        ogr2ogr -f GeoJSON /tmp/grid.geojson "$GRID_SHP"
        # Then to mbtiles (simplified approach)
        echo "⚠ Manual conversion needed - tippecanoe recommended"
    else
        echo "⚠ Grid conversion tools not available (tippecanoe/ogr2ogr)"
        echo "  Grid layer will be skipped. Install tippecanoe for vector tiles:"
        echo "  sudo apt-get install tippecanoe"
    fi
elif [ -f "$GRID_MBTILES" ]; then
    echo "✓ Grid layer already exists: $GRID_MBTILES"
else
    echo "⚠ Grid shapefile not found: $GRID_SHP"
    echo "  Grid layer will be skipped"
fi

# Step 2: Incremental merge for glmap
echo ""
echo "=== Step 2: Incremental Merge for GLMap ==="

# Check data directory
if [ ! -d "$DATA_DIR" ]; then
    echo "Error: Data directory does not exist"
    exit 1
fi

# Initialize merge log if not exists
[ ! -f "$MERGE_LOG" ] && touch "$MERGE_LOG"

# Initialize glmap if not exists
if [ ! -f "$GLMAP_FILE" ]; then
    echo "Creating new glmap.mbtiles..."
    sqlite3 "$GLMAP_FILE" "
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
        INSERT INTO metadata (name, value) VALUES ('name', 'GL Map');
        INSERT INTO metadata (name, value) VALUES ('type', 'overlay');
        INSERT INTO metadata (name, value) VALUES ('format', 'jpg');
        INSERT INTO metadata (name, value) VALUES ('description', 'Merged drone imagery tiles');
    "
    echo "✓ New glmap.mbtiles initialized"
else
    echo "✓ Existing glmap.mbtiles found"
fi

# Find new files to merge
echo "Scanning for new files to merge..."
NEW_FILES=""
NEW_COUNT=0
SKIPPED_COUNT=0

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    
    filename=$(basename "$mbtiles_file")
    
    # Skip special files
    [ "$filename" = "glmap.mbtiles" ] && continue
    [ "$filename" = "grid_layer.mbtiles" ] && continue
    
    # Skip trails (corrupt)
    case "$filename" in
        *_trails*)
            continue
            ;;
    esac
    
    # Check if already merged
    if is_already_merged "$filename"; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi
    
    # Validate
    if is_valid_mbtiles "$mbtiles_file"; then
        tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        echo "  New file: $filename ($tile_count tiles)"
        NEW_FILES="$NEW_FILES $mbtiles_file"
        NEW_COUNT=$((NEW_COUNT + 1))
    fi
done

echo "Found: $NEW_COUNT new files, $SKIPPED_COUNT already merged"

# Merge only new files
if [ "$NEW_COUNT" -gt 0 ]; then
    echo "Merging new files into glmap..."
    
    for mbtiles_file in $NEW_FILES; do
        filename=$(basename "$mbtiles_file")
        echo "  Merging: $filename"
        
        if sqlite3 "$GLMAP_FILE" "
            ATTACH DATABASE '$mbtiles_file' AS source;
            INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
            DETACH DATABASE source;
        " 2>/dev/null; then
            echo "    ✓ Merged successfully"
            mark_as_merged "$filename"
        else
            echo "    ✗ Failed to merge"
        fi
    done
    
    total=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    echo "✓ Incremental merge complete (Total tiles: $total)"
else
    echo "✓ No new files to merge"
fi

# Step 3: Generate config.json
echo ""
echo "=== Step 3: Generating Config ==="

# Start config
cat > "$TEMP_CONFIG" << 'EOF'
{
  "options": {
    "paths": {
      "root": "",
      "fonts": "fonts",
      "styles": "styles"
    }
  },
  "styles": {
    "default": {
      "style": "styles/default/style.json"
    }
  },
  "data": {
EOF

# Add grid layer first (base layer)
if [ -f "$GRID_MBTILES" ]; then
    echo '    "grid_layer": {' >> "$TEMP_CONFIG"
    echo '      "mbtiles": "data/grid_layer.mbtiles"' >> "$TEMP_CONFIG"
    echo '    },' >> "$TEMP_CONFIG"
    echo "  Added: grid_layer (base)"
fi

# Add glmap (overlay)
echo '    "glmap": {' >> "$TEMP_CONFIG"
echo '      "mbtiles": "data/glmap.mbtiles"' >> "$TEMP_CONFIG"
echo '    }' >> "$TEMP_CONFIG"

# Add individual files
INDIVIDUAL_COUNT=0
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    
    filename=$(basename "$mbtiles_file")
    basename_only=$(basename "$mbtiles_file" .mbtiles)
    
    # Skip special files
    [ "$filename" = "glmap.mbtiles" ] && continue
    [ "$filename" = "grid_layer.mbtiles" ] && continue
    
    # Skip trails
    case "$filename" in
        *_trails*) continue ;;
    esac
    
    # Validate
    if is_valid_mbtiles "$mbtiles_file"; then
        echo "," >> "$TEMP_CONFIG"
        echo "    \"$basename_only\": {" >> "$TEMP_CONFIG"
        echo "      \"mbtiles\": \"data/$filename\"" >> "$TEMP_CONFIG"
        echo "    }" >> "$TEMP_CONFIG"
        INDIVIDUAL_COUNT=$((INDIVIDUAL_COUNT + 1))
    fi
done

# Close config
echo "  }" >> "$TEMP_CONFIG"
echo "}" >> "$TEMP_CONFIG"

# Validate JSON
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool "$TEMP_CONFIG" >/dev/null 2>&1; then
        echo "✓ JSON valid"
        cp "$TEMP_CONFIG" "$CONFIG_FILE"
    else
        echo "✗ JSON invalid!"
        cat "$TEMP_CONFIG"
        exit 1
    fi
else
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
fi

echo "✓ Config generated with $((INDIVIDUAL_COUNT + 2)) datasets"

# Show config
echo ""
echo "=== Generated Config Preview ==="
if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$CONFIG_FILE" 2>/dev/null | head -50 || cat "$CONFIG_FILE" | head -50
else
    cat "$CONFIG_FILE" | head -50
fi
echo "..."

# Step 4: Restart container
echo ""
if command -v docker >/dev/null 2>&1; then
    echo "Restarting tileserver container..."
    docker restart tileserver-zurich && echo "✓ Container restarted" || echo "✗ Restart failed"
else
    echo "Docker not available - please restart container manually"
fi

# Step 5: Database update (optional)
if [ "$SKIP_DB_UPDATE" != "true" ]; then
    echo ""
    echo "=== Step 5: Database Update ==="
    echo "Database update code here (using previous implementation)"
    # TODO: Add database update code
else
    echo "Database update skipped"
fi

# Cleanup
rm -f "$TEMP_CONFIG"

# Final summary
echo ""
echo "=== Summary ==="
echo "✓ Grid layer: $([ -f "$GRID_MBTILES" ] && echo "Available" || echo "Not created")"
echo "✓ New files merged: $NEW_COUNT"
echo "✓ Already merged: $SKIPPED_COUNT"
echo "✓ Total datasets in config: $((INDIVIDUAL_COUNT + 2))"
echo "✓ Merge log: $MERGE_LOG"
echo ""
echo "Layer stack (bottom to top):"
echo "  1. Grid layer (base - GRID_36_HA_EKSISTING_POTENSI)"
echo "  2. GLMap layer (overlay - merged drone imagery)"
echo ""
echo "Next file upload will only merge new files - much faster! 🚀"