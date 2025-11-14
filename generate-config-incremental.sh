#!/bin/bash

# Enhanced generate-config.sh dengan incremental merge dan separate grid layer
# Features:
# 1. Incremental merge - hanya merge file drone baru
# 2. Grid layer SEPARATE - tidak dimerge ke glmap (optimal performance)

set -e

# Force rebuild option (set to true to merge all files from scratch)
FORCE_REBUILD="${FORCE_REBUILD:-false}"

# Environment detection
if [ -n "$DATA_DIR" ]; then
    echo "Using provided DATA_DIR: $DATA_DIR"
    # Detect base directory
    BASE_DIR=$(dirname "$DATA_DIR")
elif [ -d "/app/data/tileserver" ]; then
    DATA_DIR="/app/data/tileserver"
    BASE_DIR="/app"
elif [ -d "/app/data" ]; then
    DATA_DIR="/app/data"
    BASE_DIR="/app"
else
    echo "Error: Data directory not found"
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-$BASE_DIR/config.json}"
STYLE_DIR="${STYLE_DIR:-$BASE_DIR/styles/default}"
STYLE_FILE="${STYLE_FILE:-$STYLE_DIR/style.json}"
GLMAP_FILE="${GLMAP_FILE:-$DATA_DIR/glmap.mbtiles}"
GRID_MBTILES="${GRID_MBTILES:-$DATA_DIR/grid_layer.mbtiles}"
MERGE_LOG="${MERGE_LOG:-$DATA_DIR/.merged_files.log}"
TEMP_CONFIG="${TEMP_CONFIG:-/tmp/config_temp.json}"

# Grid shapefile paths
GRID_DIR="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI"
GRID_SHP="$GRID_DIR/GRID_36_HA_EKSISTING_POTENSI.shp"

echo "=== Enhanced Generate Config Script ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"
echo "Grid directory: $GRID_DIR"
echo ""

# Create directories
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

# Create enhanced style with separate grid and glmap layers
if [ ! -f "$STYLE_FILE" ] || [ "$FORCE_STYLE_UPDATE" = "true" ]; then
    echo "Creating multi-layer style.json (separate grid + glmap)..."
    cat > "$STYLE_FILE" << 'EOF'
{
  "version": 8,
  "name": "Drone Mapping with Grid Base Layer",
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
      "minzoom": 0,
      "maxzoom": 14,
      "paint": {
        "fill-color": "rgba(255, 192, 203, 0.3)",
        "fill-outline-color": "#0066cc"
      }
    },
    {
      "id": "grid-line",
      "type": "line",
      "source": "grid",
      "source-layer": "grid_layer",
      "minzoom": 0,
      "maxzoom": 14,
      "paint": {
        "line-color": "#0066cc",
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
    echo "✓ Multi-layer style created (grid + glmap separate)"
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

# Step 1: Merge Grid + Drone into Single glmap.mbtiles
echo "=== Step 1: Creating Combined glmap (Grid + Drone) ==="

# Check data directory
if [ ! -d "$DATA_DIR" ]; then
    echo "Error: Data directory does not exist"
    exit 1
fi

# Initialize merge log if not exists
[ ! -f "$MERGE_LOG" ] && touch "$MERGE_LOG"

# Force rebuild: remove old glmap and merge log
if [ "$FORCE_REBUILD" = "true" ]; then
    echo "⚠ FORCE_REBUILD enabled - removing old glmap and merge log..."
    rm -f "$GLMAP_FILE"
    rm -f "$MERGE_LOG"
    touch "$MERGE_LOG"
    echo "✓ Old files removed, will merge all files from scratch"
fi

# Initialize glmap if not exists (should already exist from Step 1)
if [ ! -f "$GLMAP_FILE" ]; then
    echo "Creating new glmap.mbtiles (will contain grid + drone)..."
    sqlite3 "$GLMAP_FILE" "
        CREATE TABLE metadata (name text PRIMARY KEY, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
        INSERT INTO metadata (name, value) VALUES ('name', 'GL Map Combined');
        INSERT INTO metadata (name, value) VALUES ('type', 'overlay');
        INSERT INTO metadata (name, value) VALUES ('format', 'jpg');
        INSERT INTO metadata (name, value) VALUES ('description', 'Grid layer (zoom 0-14) + Drone imagery (zoom 16-22)');
        INSERT INTO metadata (name, value) VALUES ('version', '1.3');
        INSERT INTO metadata (name, value) VALUES ('attribution', 'Grid + Drone Imagery');
        INSERT INTO metadata (name, value) VALUES ('minzoom', '0');
        INSERT INTO metadata (name, value) VALUES ('maxzoom', '22');
        INSERT INTO metadata (name, value) VALUES ('bounds', '95.0,-11.0,141.0,6.0');
        INSERT INTO metadata (name, value) VALUES ('center', '105.75,-2.75,10');
        INSERT INTO metadata (name, value) VALUES ('json', '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,10],\"minzoom\":0,\"maxzoom\":22}');
    "
    echo "✓ New glmap.mbtiles initialized (DRONE ONLY - grid_layer separate)"
else
    echo "✓ Existing glmap.mbtiles found"
    # Check and fix metadata table structure
    has_primary=$(sqlite3 "$GLMAP_FILE" "SELECT sql FROM sqlite_master WHERE type='table' AND name='metadata';" 2>/dev/null | grep -i "PRIMARY KEY" || echo "")
    if [ -z "$has_primary" ]; then
        echo "  Fixing metadata table structure..."
        sqlite3 "$GLMAP_FILE" "
            CREATE TABLE metadata_new (name text PRIMARY KEY, value text);
            INSERT OR IGNORE INTO metadata_new SELECT * FROM metadata;
            DROP TABLE metadata;
            ALTER TABLE metadata_new RENAME TO metadata;
        "
    fi
    
    # Update metadata if missing - DRONE ONLY (zoom 16-22)
    has_bounds=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM metadata WHERE name='bounds';" 2>/dev/null || echo "0")
    if [ "$has_bounds" = "0" ]; then
        echo "  Adding drone imagery metadata (zoom 16-22 only)..."
        sqlite3 "$GLMAP_FILE" "
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('version', '1.3');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('attribution', 'Drone Imagery');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('minzoom', '16');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('maxzoom', '22');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('format', 'jpg');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('type', 'overlay');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('bounds', '95.0,-11.0,141.0,6.0');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('center', '105.75,-2.75,18');
            INSERT OR REPLACE INTO metadata (name, value) VALUES ('json', '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,18],\"minzoom\":16,\"maxzoom\":22}');
            VACUUM;
        "
        echo "  ✓ Drone-only metadata added (zoom 16-22 coverage)"
    fi
fi

# Step 1.5: SKIP grid layer merging - keep separate!
if [ -f "$GRID_MBTILES" ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎯 GRID LAYER FOUND: grid_layer.mbtiles"
    echo "   Status: SEPARATE file (not merged into glmap)"
    echo "   Format: Vector tiles (PBF)"
    echo "   Zoom: 0-14"
    echo "   XYZ URL: /data/grid_layer/{z}/{x}/{y}.pbf"
    echo "══════════════════════════════════════════════════════════"
    echo ""
else
    echo "⚠ Grid mbtiles not found: $GRID_MBTILES"
    echo "  Grid layer will not be available in config.json"
fi

# Step 2: Merge DRONE imagery files ONLY (exclude grid_layer.mbtiles)
echo ""
echo "=== Step 2: Merging Drone Imagery Files ==="

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

# Add grid_layer (if exists)
if [ -f "$GRID_MBTILES" ]; then
    echo '    "grid_layer": {' >> "$TEMP_CONFIG"
    echo '      "mbtiles": "data/grid_layer.mbtiles"' >> "$TEMP_CONFIG"
    echo '    },' >> "$TEMP_CONFIG"
    echo "  Added: grid_layer (vector tiles, zoom 0-14)"
fi

# Add glmap (DRONE ONLY - NO GRID)
echo '    "glmap": {' >> "$TEMP_CONFIG"
echo '      "mbtiles": "data/glmap.mbtiles"' >> "$TEMP_CONFIG"
echo '    }' >> "$TEMP_CONFIG"
echo "  Added: glmap (drone imagery only, zoom 16-22)"

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

TOTAL_DATASETS=$((INDIVIDUAL_COUNT + 1))
echo "✓ Config generated with $TOTAL_DATASETS datasets"

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
echo "══════════════════════════════════════════════════════════════"
echo "                     GENERATION SUMMARY"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "📊 TILE COUNTS:"
drone_tiles=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
grid_tiles=$(sqlite3 "$GRID_MBTILES" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")

if [ -f "$GRID_MBTILES" ]; then
    echo "✓ grid_layer.mbtiles (SEPARATE):"
    echo "  - Format: Vector (PBF)"
    echo "  - Zoom: 0-14"
    echo "  - Tiles: $grid_tiles tiles"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf"
    echo ""
fi

echo "✓ glmap.mbtiles (DRONE ONLY):"
echo "  - Format: Raster (JPG)"
echo "  - Zoom: 16-22"
echo "  - Tiles: $drone_tiles tiles"
echo "  - URL: https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg"
echo ""
echo "📦 MERGE STATUS:"
echo "✓ New drone files merged: $NEW_COUNT"
echo "✓ Already merged: $SKIPPED_COUNT"
echo "✓ Total datasets in config: $TOTAL_DATASETS"
echo "✓ Merge log: $MERGE_LOG"
echo ""
echo "🎯 2-LAYER XYZ ARCHITECTURE:"
echo "  Layer 1 (Base):    grid_layer - Grid overview (zoom 0-14)"
echo "  Layer 2 (Overlay): glmap - Drone imagery (zoom 16-22)"
echo ""
echo "📱 FRONTEND INTEGRATION:"
echo "  Add both XYZ URLs to your Leaflet/Mapbox GL JS application:"
echo "  1. Grid:  https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf"
echo "  2. Drone: https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg"
echo "  - Will show grid at zoom 0-14"
echo "  - Will show drone at zoom 16-22"
echo ""
echo "Next file upload will only merge new drone files - fast incremental! 🚀"