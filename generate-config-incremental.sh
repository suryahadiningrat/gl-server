#!/bin/bash

# Enhanced generate-config.sh dengan incremental merge dan separate grid layer
# Features:
# 1. Incremental merge - hanya merge file drone baru
# 2. Grid layer SEPARATE - tidak dimerge ke glmap (optimal performance)
# 3. Per-year, per-BPDAS, per-year-BPDAS glmap support
#
# Usage:
#   ./generate-config-incremental.sh                                          -> global only
#   ./generate-config-incremental.sh 2026 AGAMKUANTAN file1.mbtiles ...      -> global + per-year/bpdas
#   ./generate-config-incremental.sh 2026 AGAMKUANTAN file1.mbtiles file2.mbtiles

set -e

# ─────────────────────────────────────────────
# Logging functions
# ─────────────────────────────────────────────
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >&2
}

# ─────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────
# Arguments: [YEAR] [BPDAS] [file1.mbtiles] [file2.mbtiles] ...
PARAM_YEAR=""
PARAM_BPDAS=""
PARAM_FILES=()   # Specific files to merge (filenames only, not full paths)

if [ $# -ge 2 ]; then
    # First arg is YEAR (numeric), second is BPDAS (string)
    if [[ "$1" =~ ^[0-9]{4}$ ]]; then
        PARAM_YEAR="$1"
        PARAM_BPDAS="$2"
        shift 2

        # Remaining args are mbtiles filenames
        for f in "$@"; do
            PARAM_FILES+=("$f")
        done
    fi
fi

log_info "Script started: generate-config-incremental.sh"
log_info "PARAM_YEAR: ${PARAM_YEAR:-<not set>}"
log_info "PARAM_BPDAS: ${PARAM_BPDAS:-<not set>}"
log_info "PARAM_FILES: ${PARAM_FILES[*]:-<none>}"

# ─────────────────────────────────────────────
# Environment & paths
# ─────────────────────────────────────────────
FORCE_REBUILD="${FORCE_REBUILD:-false}"

log_info "Working directory: $(pwd)"
log_info "FORCE_REBUILD: $FORCE_REBUILD"

if [ -n "$DATA_DIR" ]; then
    log_info "Using provided DATA_DIR: $DATA_DIR"
    BASE_DIR=$(dirname "$DATA_DIR")
elif [ -d "/app/data/tileserver" ]; then
    DATA_DIR="/app/data/tileserver"
    BASE_DIR="/app"
    log_info "Detected Docker environment: /app/data/tileserver"
elif [ -d "/app/data" ]; then
    DATA_DIR="/app/data"
    BASE_DIR="/app"
    log_info "Detected Docker environment: /app/data"
else
    log_error "Data directory not found"
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-/app/config.json}"
STYLE_DIR="${STYLE_DIR:-$BASE_DIR/styles/default}"
STYLE_FILE="${STYLE_FILE:-$STYLE_DIR/style.json}"
GLMAP_FILE="${GLMAP_FILE:-$DATA_DIR/glmap.mbtiles}"
GRID_MBTILES="${GRID_MBTILES:-$DATA_DIR/grid_layer.mbtiles}"
MERGE_LOG="${MERGE_LOG:-$DATA_DIR/.merged_files.log}"
TEMP_CONFIG="${TEMP_CONFIG:-/tmp/config_temp.json}"

# Derived paths for year/bpdas targets
GLMAP_YEAR=""
GLMAP_BPDAS=""
GLMAP_YEAR_BPDAS=""
MERGE_LOG_YEAR=""
MERGE_LOG_BPDAS=""
MERGE_LOG_YEAR_BPDAS=""

if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BPDAS" ]; then
    GLMAP_YEAR="$DATA_DIR/glmap_${PARAM_YEAR}.mbtiles"
    GLMAP_BPDAS="$DATA_DIR/glmap_${PARAM_BPDAS}.mbtiles"
    GLMAP_YEAR_BPDAS="$DATA_DIR/glmap_${PARAM_YEAR}_${PARAM_BPDAS}.mbtiles"
    MERGE_LOG_YEAR="$DATA_DIR/.merged_${PARAM_YEAR}.log"
    MERGE_LOG_BPDAS="$DATA_DIR/.merged_${PARAM_BPDAS}.log"
    MERGE_LOG_YEAR_BPDAS="$DATA_DIR/.merged_${PARAM_YEAR}_${PARAM_BPDAS}.log"
fi

GRID_DIR="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI"
GRID_SHP="$GRID_DIR/GRID_36_HA_EKSISTING_POTENSI.shp"

log_info "=== Configuration ==="
log_info "Data directory: $DATA_DIR"
log_info "Config file: $CONFIG_FILE"
log_info "Glmap (global): $GLMAP_FILE"
[ -n "$GLMAP_YEAR" ]      && log_info "Glmap (year):   $GLMAP_YEAR"
[ -n "$GLMAP_BPDAS" ]     && log_info "Glmap (bpdas):  $GLMAP_BPDAS"
[ -n "$GLMAP_YEAR_BPDAS" ] && log_info "Glmap (y+b):    $GLMAP_YEAR_BPDAS"

echo "=== Enhanced Generate Config Script ==="
echo "Data directory: $DATA_DIR"
echo "Year/BPDAS: ${PARAM_YEAR:-none} / ${PARAM_BPDAS:-none}"
echo ""

# Create directories
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

# ─────────────────────────────────────────────
# Style file
# ─────────────────────────────────────────────
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

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────

is_valid_mbtiles() {
    local file="$1"
    [ -r "$file" ] || return 1
    sqlite3 "$file" ".tables" 2>/dev/null | grep -q "tiles" || return 1
    local tiles
    tiles=$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    [ "$tiles" -gt 0 ] || return 1
    return 0
}

is_already_merged() {
    local log_file="$1"
    local filename="$2"
    [ -f "$log_file" ] && grep -q "^${filename}$" "$log_file"
}

mark_as_merged() {
    local log_file="$1"
    local filename="$2"
    echo "$filename" >> "$log_file"
}

# Initialize a fresh mbtiles with drone-only metadata
init_mbtiles() {
    local target="$1"
    local display_name="$2"
    log_info "Creating new mbtiles: $target ($display_name)"
    sqlite3 "$target" "
        CREATE TABLE metadata (name text PRIMARY KEY, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
        INSERT INTO metadata VALUES ('name',        '$display_name');
        INSERT INTO metadata VALUES ('type',        'overlay');
        INSERT INTO metadata VALUES ('format',      'jpg');
        INSERT INTO metadata VALUES ('description', 'High-resolution drone imagery for detailed mapping');
        INSERT INTO metadata VALUES ('version',     '1.3');
        INSERT INTO metadata VALUES ('attribution', 'Drone Imagery');
        INSERT INTO metadata VALUES ('minzoom',     '16');
        INSERT INTO metadata VALUES ('maxzoom',     '22');
        INSERT INTO metadata VALUES ('bounds',      '95.0,-11.0,141.0,6.0');
        INSERT INTO metadata VALUES ('center',      '105.75,-2.75,18');
        INSERT INTO metadata VALUES ('json',        '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,18],\"minzoom\":16,\"maxzoom\":22}');
    "
}

# Fix & update metadata on existing mbtiles if needed
fix_mbtiles_metadata() {
    local target="$1"

    # Ensure PRIMARY KEY on metadata
    local has_primary
    has_primary=$(sqlite3 "$target" "SELECT sql FROM sqlite_master WHERE type='table' AND name='metadata';" 2>/dev/null | grep -i "PRIMARY KEY" || echo "")
    if [ -z "$has_primary" ]; then
        sqlite3 "$target" "
            CREATE TABLE metadata_new (name text PRIMARY KEY, value text);
            INSERT OR IGNORE INTO metadata_new SELECT * FROM metadata;
            DROP TABLE metadata;
            ALTER TABLE metadata_new RENAME TO metadata;
        "
    fi

    # Add missing bounds/minzoom etc
    local has_bounds
    has_bounds=$(sqlite3 "$target" "SELECT COUNT(*) FROM metadata WHERE name='bounds';" 2>/dev/null || echo "0")
    if [ "$has_bounds" = "0" ]; then
        sqlite3 "$target" "
            INSERT OR REPLACE INTO metadata VALUES ('version',     '1.3');
            INSERT OR REPLACE INTO metadata VALUES ('attribution', 'Drone Imagery');
            INSERT OR REPLACE INTO metadata VALUES ('minzoom',     '16');
            INSERT OR REPLACE INTO metadata VALUES ('maxzoom',     '22');
            INSERT OR REPLACE INTO metadata VALUES ('format',      'jpg');
            INSERT OR REPLACE INTO metadata VALUES ('type',        'overlay');
            INSERT OR REPLACE INTO metadata VALUES ('bounds',      '95.0,-11.0,141.0,6.0');
            INSERT OR REPLACE INTO metadata VALUES ('center',      '105.75,-2.75,18');
            INSERT OR REPLACE INTO metadata VALUES ('json',        '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,18],\"minzoom\":16,\"maxzoom\":22}');
            VACUUM;
        "
    fi
}

# Ensure an mbtiles exists (create if not, fix if yes)
ensure_mbtiles() {
    local target="$1"
    local display_name="$2"

    if [ ! -f "$target" ]; then
        init_mbtiles "$target" "$display_name"
        echo "✓ Created: $(basename "$target") ($display_name)"
    else
        fix_mbtiles_metadata "$target"
        echo "✓ Existing: $(basename "$target")"
    fi
}

# Merge a single source mbtiles into a target mbtiles
merge_into() {
    local target="$1"
    local source="$2"
    local log_file="$3"
    local filename
    filename=$(basename "$source")

    if is_already_merged "$log_file" "$filename"; then
        echo "    → Already merged into $(basename "$target"), skip"
        return 0
    fi

    if sqlite3 "$target" "
        ATTACH DATABASE '$source' AS source;
        INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
        DETACH DATABASE source;
    " 2>/dev/null; then
        mark_as_merged "$log_file" "$filename"
        echo "    ✓ Merged into $(basename "$target")"
    else
        echo "    ✗ Failed to merge into $(basename "$target")"
    fi
}

# ─────────────────────────────────────────────
# Step 0: Handle FORCE_REBUILD for all targets
# ─────────────────────────────────────────────
if [ "$FORCE_REBUILD" = "true" ]; then
    log_info "FORCE_REBUILD enabled - removing old files"
    echo "⚠ FORCE_REBUILD enabled..."
    rm -f "$GLMAP_FILE" "$MERGE_LOG"
    touch "$MERGE_LOG"
    if [ -n "$PARAM_YEAR" ]; then
        rm -f "$GLMAP_YEAR" "$MERGE_LOG_YEAR"
        rm -f "$GLMAP_BPDAS" "$MERGE_LOG_BPDAS"
        rm -f "$GLMAP_YEAR_BPDAS" "$MERGE_LOG_YEAR_BPDAS"
        touch "$MERGE_LOG_YEAR" "$MERGE_LOG_BPDAS" "$MERGE_LOG_YEAR_BPDAS"
    fi
    echo "✓ Old files removed, will merge from scratch"
fi

# ─────────────────────────────────────────────
# Step 1: Initialize merge logs & mbtiles
# ─────────────────────────────────────────────
log_info "=== Step 1: Initializing mbtiles targets ==="
echo ""
echo "=== Step 1: Initializing mbtiles targets ==="

[ ! -f "$MERGE_LOG" ] && touch "$MERGE_LOG"

ensure_mbtiles "$GLMAP_FILE" "Drone Imagery (High Resolution)"

if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BPDAS" ]; then
    [ ! -f "$MERGE_LOG_YEAR" ]      && touch "$MERGE_LOG_YEAR"
    [ ! -f "$MERGE_LOG_BPDAS" ]     && touch "$MERGE_LOG_BPDAS"
    [ ! -f "$MERGE_LOG_YEAR_BPDAS" ] && touch "$MERGE_LOG_YEAR_BPDAS"

    ensure_mbtiles "$GLMAP_YEAR"      "GL Map Combined ${PARAM_YEAR}"
    ensure_mbtiles "$GLMAP_BPDAS"     "GL Map Combined ${PARAM_BPDAS}"
    ensure_mbtiles "$GLMAP_YEAR_BPDAS" "GL Map Combined ${PARAM_YEAR} ${PARAM_BPDAS}"
fi

# ─────────────────────────────────────────────
# Step 2: Grid layer status
# ─────────────────────────────────────────────
if [ -f "$GRID_MBTILES" ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎯 GRID LAYER FOUND: grid_layer.mbtiles"
    echo "   Status: SEPARATE file (not merged into glmap)"
    echo "   Format: Vector tiles (PBF)"
    echo "   Zoom: 0-14"
    echo "   XYZ URL: /data/grid_layer/{z}/{x}/{y}.pbf"
    echo "══════════════════════════════════════════════════════════"
else
    echo "⚠ Grid mbtiles not found: $GRID_MBTILES"
fi

# ─────────────────────────────────────────────
# Step 3: Merge files into global glmap (existing behavior)
# Scans all *.mbtiles in $DATA_DIR, skips already-merged
# ─────────────────────────────────────────────
log_info "=== Step 3: Merging Drone Imagery into Global glmap ==="
echo ""
echo "=== Step 3: Merging Drone Imagery into Global glmap ==="

NEW_FILES_GLOBAL=()
SKIPPED_COUNT=0

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    filename=$(basename "$mbtiles_file")

    # Skip special files
    [[ "$filename" == "glmap.mbtiles" ]]       && continue
    [[ "$filename" == "grid_layer.mbtiles" ]]   && continue
    [[ "$filename" == glmap_*.mbtiles ]]        && continue
    [[ "$filename" == *_trails* ]]              && continue

    if is_already_merged "$MERGE_LOG" "$filename"; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    if is_valid_mbtiles "$mbtiles_file"; then
        tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        echo "  New (global): $filename ($tile_count tiles)"
        NEW_FILES_GLOBAL+=("$mbtiles_file")
    fi
done

log_info "Global: ${#NEW_FILES_GLOBAL[@]} new, $SKIPPED_COUNT skipped"
echo "Global: ${#NEW_FILES_GLOBAL[@]} new files, $SKIPPED_COUNT already merged"

if [ "${#NEW_FILES_GLOBAL[@]}" -gt 0 ]; then
    for mbtiles_file in "${NEW_FILES_GLOBAL[@]}"; do
        filename=$(basename "$mbtiles_file")
        echo "  Merging (global): $filename"
        merge_into "$GLMAP_FILE" "$mbtiles_file" "$MERGE_LOG"
    done
    total=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    log_success "Global merge done (Total tiles: $total)"
    echo "✓ Global merge done (Total tiles: $total)"
else
    echo "✓ No new files for global glmap"
fi

# ─────────────────────────────────────────────
# Step 4: Merge argument files into per-year/bpdas targets
# Only runs if YEAR + BPDAS + files were provided
# ─────────────────────────────────────────────
if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BPDAS" ]; then
    log_info "=== Step 4: Merging Argument Files into Year/BPDAS targets ==="
    echo ""
    echo "=== Step 4: Merging Argument Files into Year/BPDAS targets ==="

    if [ "${#PARAM_FILES[@]}" -eq 0 ]; then
        echo "⚠ No files specified as arguments — Year/BPDAS targets will not receive new tiles"
        log_info "No argument files provided, skipping year/bpdas merge"
    else
        for filename in "${PARAM_FILES[@]}"; do
            # Support full path or filename only
            if [[ "$filename" == /* ]]; then
                mbtiles_file="$filename"
            else
                mbtiles_file="$DATA_DIR/$filename"
            fi

            if [ ! -f "$mbtiles_file" ]; then
                echo "  ✗ File not found: $mbtiles_file — skipping"
                continue
            fi

            if ! is_valid_mbtiles "$mbtiles_file"; then
                echo "  ✗ Invalid mbtiles: $(basename "$mbtiles_file") — skipping"
                continue
            fi

            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            echo ""
            echo "  Processing: $(basename "$mbtiles_file") ($tile_count tiles)"

            merge_into "$GLMAP_YEAR"      "$mbtiles_file" "$MERGE_LOG_YEAR"
            merge_into "$GLMAP_BPDAS"     "$mbtiles_file" "$MERGE_LOG_BPDAS"
            merge_into "$GLMAP_YEAR_BPDAS" "$mbtiles_file" "$MERGE_LOG_YEAR_BPDAS"
        done

        year_tiles=$(sqlite3 "$GLMAP_YEAR"      "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        bpdas_tiles=$(sqlite3 "$GLMAP_BPDAS"    "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        yb_tiles=$(sqlite3 "$GLMAP_YEAR_BPDAS"  "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")

        log_success "Year/BPDAS merge done"
        echo ""
        echo "✓ glmap_${PARAM_YEAR}.mbtiles          → $year_tiles tiles"
        echo "✓ glmap_${PARAM_BPDAS}.mbtiles         → $bpdas_tiles tiles"
        echo "✓ glmap_${PARAM_YEAR}_${PARAM_BPDAS}.mbtiles → $yb_tiles tiles"
    fi
fi

# ─────────────────────────────────────────────
# Step 5: Generate config.json
# ─────────────────────────────────────────────
log_info "=== Step 5: Generating Config ==="
echo ""
echo "=== Step 5: Generating Config ==="

# Helper: append a data entry to temp config
# $1 = key, $2 = mbtiles relative path, $3 = description (for echo)
# $4 = "first" if first entry (no leading comma)
append_data_entry() {
    local key="$1"
    local path="$2"
    local desc="$3"
    local is_first="${4:-}"

    if [ "$is_first" != "first" ]; then
        echo "," >> "$TEMP_CONFIG"
    fi
    printf '    "%s": {\n      "mbtiles": "%s"\n    }' "$key" "$path" >> "$TEMP_CONFIG"
    echo "  Added: $desc"
}

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

FIRST_DATA="first"

# grid_layer
if [ -f "$GRID_MBTILES" ]; then
    append_data_entry "grid_layer" "data/grid_layer.mbtiles" "grid_layer (vector, zoom 0-14)" "$FIRST_DATA"
    FIRST_DATA=""
fi

# glmap (global)
append_data_entry "glmap" "data/glmap.mbtiles" "glmap (drone global, zoom 16-22)" "$FIRST_DATA"
FIRST_DATA=""

# All existing per-year/bpdas glmap files — scan disk, not just current args
for glmap_variant in "$DATA_DIR"/glmap_*.mbtiles; do
    [ -f "$glmap_variant" ] || continue
    basename_only=$(basename "$glmap_variant" .mbtiles)
    if is_valid_mbtiles "$glmap_variant"; then
        append_data_entry "$basename_only" "data/$(basename "$glmap_variant")" "$basename_only"
    fi
done

# Individual drone files
INDIVIDUAL_COUNT=0
SKIPPED_INVALID=0

echo "Scanning individual mbtiles files for config..."
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    filename=$(basename "$mbtiles_file")
    basename_only=$(basename "$mbtiles_file" .mbtiles)

    # Skip all managed/special files
    [[ "$filename" == "glmap.mbtiles" ]]     && continue
    [[ "$filename" == "grid_layer.mbtiles" ]] && continue
    [[ "$filename" == glmap_*.mbtiles ]]     && continue
    [[ "$filename" == *_trails* ]]           && { echo "  Skipping (trails): $filename"; continue; }

    if is_valid_mbtiles "$mbtiles_file"; then
        append_data_entry "$basename_only" "data/$filename" "$filename"
        INDIVIDUAL_COUNT=$((INDIVIDUAL_COUNT + 1))
    else
        echo "  Skipping (invalid): $filename"
        SKIPPED_INVALID=$((SKIPPED_INVALID + 1))
    fi
done

echo "  }" >> "$TEMP_CONFIG"
echo "}" >> "$TEMP_CONFIG"

echo "✓ Added $INDIVIDUAL_COUNT individual files"
[ $SKIPPED_INVALID -gt 0 ] && echo "⚠ Skipped $SKIPPED_INVALID invalid files"

# Validate & save JSON
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
echo "✓ Config generated: $CONFIG_FILE"

# Preview
echo ""
echo "=== Generated Config Preview ==="
if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$CONFIG_FILE" 2>/dev/null | head -60 || head -60 "$CONFIG_FILE"
else
    head -60 "$CONFIG_FILE"
fi
echo "..."

# ─────────────────────────────────────────────
# Step 6: Restart tileserver container
# ─────────────────────────────────────────────
log_info "=== Step 6: Restarting Tileserver Container ==="
echo ""
echo "=== Step 6: Restarting Tileserver Container ==="
if command -v docker >/dev/null 2>&1; then
    if docker restart tileserver-zurich; then
        echo "✓ Container restarted successfully"
        echo "✓ New tiles are now available via XYZ URLs"
    else
        echo "✗ Restart failed"
    fi
else
    echo "⚠ Docker not available - please restart container manually"
fi

# ─────────────────────────────────────────────
# Step 7: Database update
# ─────────────────────────────────────────────
log_info "=== Step 7: Updating PostgreSQL Database ==="
echo ""
echo "=== Step 7: Updating PostgreSQL Database ==="

DBHOST="172.26.11.153"
DBUSER="pg"
DBPASS="~nagha2025yasha@~"
DBNAME="postgres"
DBPORT="5432"

if [ "$SKIP_DB_UPDATE" = "true" ]; then
    log_info "Database update skipped (SKIP_DB_UPDATE=true)"
    echo "Database update skipped"
else
    DB_UPDATE_AVAILABLE="true"

    if ! python3 -c "import psycopg2" 2>/dev/null; then
        echo "Installing psycopg2-binary..."
        if pip3 install psycopg2-binary >/dev/null 2>&1; then
            echo "✓ psycopg2-binary installed"
        else
            echo "✗ Could not install psycopg2, skipping"
            DB_UPDATE_AVAILABLE="false"
        fi
    fi

    if ! command -v bc >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y bc >/dev/null 2>&1 || true
    fi

    extract_coordinates() {
        local mbtiles_file="$1"
        local bounds
        bounds=$(sqlite3 "$mbtiles_file" "SELECT value FROM metadata WHERE name='bounds';" 2>/dev/null || echo "")
        if [ -n "$bounds" ]; then
            local west south east north
            west=$(echo "$bounds"  | cut -d',' -f1)
            south=$(echo "$bounds" | cut -d',' -f2)
            east=$(echo "$bounds"  | cut -d',' -f3)
            north=$(echo "$bounds" | cut -d',' -f4)
            if command -v bc >/dev/null 2>&1; then
                local lat lon
                lat=$(echo "scale=6; ($south + $north) / 2" | bc 2>/dev/null || echo "-0.469")
                lon=$(echo "scale=6; ($west  + $east)  / 2" | bc 2>/dev/null || echo "117.172")
            else
                local lat lon
                lat=$(awk "BEGIN {printf \"%.6f\", ($south + $north) / 2}")
                lon=$(awk "BEGIN {printf \"%.6f\", ($west  + $east)  / 2}")
            fi
            echo "$lat,$lon"
            return 0
        fi
        local center
        center=$(sqlite3 "$mbtiles_file" "SELECT value FROM metadata WHERE name='center';" 2>/dev/null || echo "")
        if [ -n "$center" ]; then
            local lon lat
            lon=$(echo "$center" | cut -d',' -f1)
            lat=$(echo "$center" | cut -d',' -f2)
            echo "$lat,$lon"
            return 0
        fi
        echo "-0.469,117.172"
    }

    update_database() {
        local filename="$1"
        local latitude="$2"
        local longitude="$3"
        echo "Updating DB: $filename -> lat=$latitude, lon=$longitude"
        python3 << EOF
import psycopg2, sys
try:
    conn = psycopg2.connect(host='$DBHOST', port=$DBPORT, user='$DBUSER', password='$DBPASS', database='$DBNAME')
    cur = conn.cursor()
    cur.execute("""
        SELECT id, title, latitude, longitude, storage_path
        FROM geoportal.pmn_drone_imagery WHERE storage_path LIKE %s
    """, ('%$filename.mbtiles%',))
    records = cur.fetchall()
    if records:
        for r in records:
            print(f"  Found: {r[0]} - {r[1]} (was: {r[2]}, {r[3]})")
        cur.execute("""
            UPDATE geoportal.pmn_drone_imagery
            SET latitude=%s, longitude=%s, status='Aktif', updated_at=NOW()
            WHERE storage_path LIKE %s
        """, ($latitude, $longitude, '%$filename.mbtiles%'))
        print(f"  ✓ Updated {cur.rowcount} record(s)")
        conn.commit()
    else:
        print(f"  ⚠ No matching records for $filename")
    cur.close(); conn.close()
except Exception as e:
    print(f"  ✗ DB Error: {e}"); sys.exit(1)
EOF
    }

    if [ "$DB_UPDATE_AVAILABLE" = "true" ]; then
        # Update newly merged global files
        if [ "${#NEW_FILES_GLOBAL[@]}" -gt 0 ]; then
            for mbtiles_file in "${NEW_FILES_GLOBAL[@]}"; do
                [ -f "$mbtiles_file" ] || continue
                filename=$(basename "$mbtiles_file" .mbtiles)
                coords=$(extract_coordinates "$mbtiles_file")
                lat=$(echo "$coords" | cut -d',' -f1)
                lon=$(echo "$coords" | cut -d',' -f2)
                update_database "$filename" "$lat" "$lon"
            done
        fi

        # Update argument files (year/bpdas)
        if [ -n "$PARAM_YEAR" ] && [ "${#PARAM_FILES[@]}" -gt 0 ]; then
            for filename in "${PARAM_FILES[@]}"; do
                mbtiles_file="$DATA_DIR/$filename"
                [[ "$filename" == /* ]] && mbtiles_file="$filename"
                [ -f "$mbtiles_file" ] || continue
                base=$(basename "$mbtiles_file" .mbtiles)
                coords=$(extract_coordinates "$mbtiles_file")
                lat=$(echo "$coords" | cut -d',' -f1)
                lon=$(echo "$coords" | cut -d',' -f2)
                update_database "$base" "$lat" "$lon"
            done
        fi

        # Update glmap
        if [ -f "$GLMAP_FILE" ]; then
            coords=$(extract_coordinates "$GLMAP_FILE")
            lat=$(echo "$coords" | cut -d',' -f1)
            lon=$(echo "$coords" | cut -d',' -f2)
            update_database "glmap" "$lat" "$lon"
        fi

        echo "✓ Database update completed"
    fi
fi

# ─────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────
rm -f "$TEMP_CONFIG"

# ─────────────────────────────────────────────
# Final summary
# ─────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "                     GENERATION SUMMARY"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "📊 TILE COUNTS:"

drone_tiles=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
grid_tiles=$(sqlite3 "$GRID_MBTILES" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")

if [ -f "$GRID_MBTILES" ]; then
    echo "✓ grid_layer.mbtiles (SEPARATE vector):"
    echo "  - Zoom: 0-14  |  Tiles: $grid_tiles"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf"
    echo ""
fi

echo "✓ glmap.mbtiles (Drone Global):"
echo "  - Zoom: 16-22  |  Tiles: $drone_tiles"
echo "  - URL: https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg"

if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BPDAS" ]; then
    echo ""
    year_tiles=$(sqlite3 "$GLMAP_YEAR"     "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    bpdas_tiles=$(sqlite3 "$GLMAP_BPDAS"  "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    yb_tiles=$(sqlite3 "$GLMAP_YEAR_BPDAS" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")

    echo "✓ glmap_${PARAM_YEAR}.mbtiles (GL Map Combined ${PARAM_YEAR}):"
    echo "  - Tiles: $year_tiles"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/glmap_${PARAM_YEAR}/{z}/{x}/{y}.jpg"
    echo ""
    echo "✓ glmap_${PARAM_BPDAS}.mbtiles (GL Map Combined ${PARAM_BPDAS}):"
    echo "  - Tiles: $bpdas_tiles"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/glmap_${PARAM_BPDAS}/{z}/{x}/{y}.jpg"
    echo ""
    echo "✓ glmap_${PARAM_YEAR}_${PARAM_BPDAS}.mbtiles (GL Map Combined ${PARAM_YEAR} ${PARAM_BPDAS}):"
    echo "  - Tiles: $yb_tiles"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/glmap_${PARAM_YEAR}_${PARAM_BPDAS}/{z}/{x}/{y}.jpg"
fi

echo ""
echo "📦 MERGE STATUS:"
echo "✓ New files merged (global): ${#NEW_FILES_GLOBAL[@]}"
echo "✓ Already merged (global):   $SKIPPED_COUNT"
[ -n "$PARAM_YEAR" ] && echo "✓ Argument files (year/bpdas): ${#PARAM_FILES[@]}"
echo "✓ Total datasets in config:  $TOTAL_DATASETS"
echo ""
echo "🎯 ARCHITECTURE:"
echo "  Layer 1 (Base):    grid_layer - Grid overview (zoom 0-14)"
echo "  Layer 2 (Overlay): glmap      - Drone imagery (zoom 16-22)"
[ -n "$PARAM_YEAR" ] && echo "  Layer 3 (Subset):  glmap_${PARAM_YEAR}_${PARAM_BPDAS} - Drone ${PARAM_YEAR} ${PARAM_BPDAS} (zoom 16-22)"
echo ""
echo "🚀 Next run will only process new files!"