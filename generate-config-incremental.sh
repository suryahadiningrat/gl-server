#!/bin/bash

# Enhanced generate-config.sh dengan incremental merge dan separate grid layer
# Features:
# 1. Incremental merge - hanya merge file drone baru
# 2. Grid layer SEPARATE - tidak dimerge ke glmap (optimal performance)
# 3. YEAR + BPDAS support - merge juga ke glmap_{YEAR}_{BPDAS}.mbtiles

set -e

# ============================================================
# ARGUMENT PARSING
# Usage:
#   sh generate-config-incremental.sh
#   sh generate-config-incremental.sh 2026 AGAMKUANTAN file1.mbtiles file2.mbtiles ...
# ============================================================
YEAR=""
BPDAS=""
INPUT_FILES=()

if [ $# -ge 2 ]; then
    YEAR="$1"
    BPDAS="$2"
    shift 2
    # Remaining args = input mbtiles files
    while [ $# -gt 0 ]; do
        INPUT_FILES+=("$1")
        shift
    done
fi

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >&2
}

# Force rebuild option (set to true to merge all files from scratch)
FORCE_REBUILD="${FORCE_REBUILD:-false}"

log_info "Script started: generate-config-incremental.sh"
log_info "Working directory: $(pwd)"
log_info "User: $(whoami)"
log_info "FORCE_REBUILD: $FORCE_REBUILD"

if [ -n "$YEAR" ] && [ -n "$BPDAS" ]; then
    log_info "Mode: YEAR+BPDAS -> Year=$YEAR, BPDAS=$BPDAS, Files=${INPUT_FILES[*]:-<auto-scan>}"
else
    log_info "Mode: GLOBAL (no YEAR/BPDAS specified)"
fi

# Environment detection
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

# FIX: Config file should be in /app (Docker root), not in /app/data
CONFIG_FILE="${CONFIG_FILE:-/app/config.json}"
STYLE_DIR="${STYLE_DIR:-$BASE_DIR/styles/default}"
STYLE_FILE="${STYLE_FILE:-$STYLE_DIR/style.json}"
GLMAP_FILE="${GLMAP_FILE:-$DATA_DIR/glmap.mbtiles}"
GRID_MBTILES="${GRID_MBTILES:-$DATA_DIR/grid_layer.mbtiles}"
MERGE_LOG="${MERGE_LOG:-$DATA_DIR/.merged_files.log}"
TEMP_CONFIG="${TEMP_CONFIG:-/tmp/config_temp.json}"

# ── BPDAS-specific paths (only set when YEAR+BPDAS given) ──
BPDAS_GLMAP_FILE=""
BPDAS_MERGE_LOG=""
BPDAS_KEY=""        # key in config.json  e.g. glmap_2026_AGAMKUANTAN
BPDAS_LABEL=""      # human-readable name e.g. GL Map Combined 2026 AGAMKUANTAN

if [ -n "$YEAR" ] && [ -n "$BPDAS" ]; then
    # Normalise BPDAS: uppercase, spaces→underscore
    BPDAS_NORM=$(echo "$BPDAS" | tr '[:lower:]' '[:upper:]' | tr ' ' '_')
    BPDAS_KEY="glmap_${YEAR}_${BPDAS_NORM}"
    BPDAS_LABEL="GL Map Combined ${YEAR} ${BPDAS_NORM}"
    BPDAS_GLMAP_FILE="$DATA_DIR/${BPDAS_KEY}.mbtiles"
    BPDAS_MERGE_LOG="$DATA_DIR/.merged_files_${YEAR}_${BPDAS_NORM}.log"
fi

# Grid shapefile paths
GRID_DIR="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI"
GRID_SHP="$GRID_DIR/GRID_36_HA_EKSISTING_POTENSI.shp"

log_info "=== Configuration ==="
log_info "Data directory: $DATA_DIR"
log_info "Config file: $CONFIG_FILE"
log_info "Style file: $STYLE_FILE"
log_info "Glmap file: $GLMAP_FILE"
log_info "Grid mbtiles: $GRID_MBTILES"
log_info "Merge log: $MERGE_LOG"
log_info "Grid directory: $GRID_DIR"
[ -n "$BPDAS_GLMAP_FILE" ] && log_info "BPDAS glmap file: $BPDAS_GLMAP_FILE"
[ -n "$BPDAS_MERGE_LOG"  ] && log_info "BPDAS merge log: $BPDAS_MERGE_LOG"

echo "=== Enhanced Generate Config Script ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"
echo "Grid directory: $GRID_DIR"
[ -n "$BPDAS_KEY" ] && echo "BPDAS target: $BPDAS_LABEL ($BPDAS_KEY)"
echo ""

# Create directories
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

log_info "Directories created/verified"
log_info "Checking style file: $STYLE_FILE"

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

# ============================================================
# HELPER FUNCTIONS
# ============================================================

# Validation function
is_valid_mbtiles() {
    local file="$1"
    [ -r "$file" ] || return 1
    sqlite3 "$file" ".tables" 2>/dev/null | grep -q "tiles" || return 1
    local tiles
    tiles=$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    [ "$tiles" -gt 0 ] || return 1
    return 0
}

# Check if file has been merged before (per log file)
is_already_merged() {
    local logfile="$1"
    local file="$2"
    [ -f "$logfile" ] && grep -q "^$(basename "$file")$" "$logfile"
}

# Add file to merge log
mark_as_merged() {
    local logfile="$1"
    local file="$2"
    echo "$(basename "$file")" >> "$logfile"
}

# Ensure an mbtiles file exists with correct drone-only schema
init_glmap_mbtiles() {
    local target="$1"
    local label="$2"

    if [ ! -f "$target" ]; then
        log_info "Creating new mbtiles: $target ($label)"
        echo "Creating new mbtiles: $target ($label) ..."
        sqlite3 "$target" "
            CREATE TABLE metadata (name text PRIMARY KEY, value text);
            CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
            CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
            INSERT INTO metadata VALUES ('name', '$label');
            INSERT INTO metadata VALUES ('type', 'overlay');
            INSERT INTO metadata VALUES ('format', 'jpg');
            INSERT INTO metadata VALUES ('description', 'High-resolution drone imagery for detailed mapping');
            INSERT INTO metadata VALUES ('version', '1.3');
            INSERT INTO metadata VALUES ('attribution', 'Drone Imagery');
            INSERT INTO metadata VALUES ('minzoom', '16');
            INSERT INTO metadata VALUES ('maxzoom', '22');
            INSERT INTO metadata VALUES ('bounds', '95.0,-11.0,141.0,6.0');
            INSERT INTO metadata VALUES ('center', '105.75,-2.75,18');
            INSERT INTO metadata VALUES ('json', '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,18],\"minzoom\":16,\"maxzoom\":22}');
        "
        echo "✓ Created: $(basename "$target")"
    else
        log_info "Existing mbtiles found: $target"
        echo "✓ Existing mbtiles found: $(basename "$target")"

        # Ensure metadata table has PRIMARY KEY
        local has_primary
        has_primary=$(sqlite3 "$target" "SELECT sql FROM sqlite_master WHERE type='table' AND name='metadata';" 2>/dev/null | grep -i "PRIMARY KEY" || echo "")
        if [ -z "$has_primary" ]; then
            echo "  Fixing metadata table structure..."
            sqlite3 "$target" "
                CREATE TABLE metadata_new (name text PRIMARY KEY, value text);
                INSERT OR IGNORE INTO metadata_new SELECT * FROM metadata;
                DROP TABLE metadata;
                ALTER TABLE metadata_new RENAME TO metadata;
            "
        fi

        # Patch missing metadata
        local has_bounds
        has_bounds=$(sqlite3 "$target" "SELECT COUNT(*) FROM metadata WHERE name='bounds';" 2>/dev/null || echo "0")
        if [ "$has_bounds" = "0" ]; then
            echo "  Adding missing metadata..."
            sqlite3 "$target" "
                INSERT OR REPLACE INTO metadata VALUES ('version', '1.3');
                INSERT OR REPLACE INTO metadata VALUES ('attribution', 'Drone Imagery');
                INSERT OR REPLACE INTO metadata VALUES ('minzoom', '16');
                INSERT OR REPLACE INTO metadata VALUES ('maxzoom', '22');
                INSERT OR REPLACE INTO metadata VALUES ('format', 'jpg');
                INSERT OR REPLACE INTO metadata VALUES ('type', 'overlay');
                INSERT OR REPLACE INTO metadata VALUES ('bounds', '95.0,-11.0,141.0,6.0');
                INSERT OR REPLACE INTO metadata VALUES ('center', '105.75,-2.75,18');
                INSERT OR REPLACE INTO metadata VALUES ('json', '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,18],\"minzoom\":16,\"maxzoom\":22}');
                VACUUM;
            "
        fi
    fi
}

# Merge a single source mbtiles into a target mbtiles
merge_into() {
    local source="$1"
    local target="$2"
    local merge_log="$3"

    local filename
    filename=$(basename "$source")

    if sqlite3 "$target" "
        ATTACH DATABASE '$source' AS source;
        INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
        DETACH DATABASE source;
    " 2>/dev/null; then
        echo "    ✓ Merged $filename -> $(basename "$target")"
        mark_as_merged "$merge_log" "$source"
        return 0
    else
        echo "    ✗ Failed to merge $filename -> $(basename "$target")"
        return 1
    fi
}

# ============================================================
# STEP 1: Initialise glmap.mbtiles (global)
# ============================================================
log_info "=== Step 1: Init Global glmap.mbtiles ==="
echo ""
echo "=== Step 1: Init Global glmap.mbtiles ==="

[ ! -d "$DATA_DIR" ] && { log_error "Data directory missing: $DATA_DIR"; exit 1; }

[ ! -f "$MERGE_LOG" ] && touch "$MERGE_LOG"

if [ "$FORCE_REBUILD" = "true" ]; then
    log_info "FORCE_REBUILD: removing global glmap and merge log"
    echo "⚠ FORCE_REBUILD enabled - removing old glmap and merge log..."
    rm -f "$GLMAP_FILE" "$MERGE_LOG"
    touch "$MERGE_LOG"
fi

init_glmap_mbtiles "$GLMAP_FILE" "Drone Imagery (High Resolution)"

# ============================================================
# STEP 1b: Initialise BPDAS-specific glmap (if YEAR+BPDAS given)
# ============================================================
if [ -n "$BPDAS_GLMAP_FILE" ]; then
    log_info "=== Step 1b: Init BPDAS glmap: $BPDAS_KEY ==="
    echo ""
    echo "=== Step 1b: Init BPDAS glmap: $BPDAS_KEY ==="

    [ ! -f "$BPDAS_MERGE_LOG" ] && touch "$BPDAS_MERGE_LOG"

    if [ "$FORCE_REBUILD" = "true" ]; then
        log_info "FORCE_REBUILD: removing BPDAS glmap and merge log"
        rm -f "$BPDAS_GLMAP_FILE" "$BPDAS_MERGE_LOG"
        touch "$BPDAS_MERGE_LOG"
    fi

    init_glmap_mbtiles "$BPDAS_GLMAP_FILE" "$BPDAS_LABEL"
fi

# ============================================================
# STEP 1c: Grid layer status (static — never touched)
# ============================================================
if [ -f "$GRID_MBTILES" ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎯 GRID LAYER: grid_layer.mbtiles (STATIC - not modified)"
    echo "   Format: Vector tiles (PBF) | Zoom: 0-14"
    echo "   URL: /data/grid_layer/{z}/{x}/{y}.pbf"
    echo "══════════════════════════════════════════════════════════"
else
    echo "⚠ Grid mbtiles not found: $GRID_MBTILES"
fi

# ============================================================
# STEP 2: Determine which drone files to merge
# ============================================================
log_info "=== Step 2: Collecting Drone Files to Merge ==="
echo ""
echo "=== Step 2: Collecting Drone Files to Merge ==="

# Collect candidate files
#   - If INPUT_FILES is supplied → use those (after resolving paths)
#   - Otherwise               → auto-scan DATA_DIR/*.mbtiles

CANDIDATE_FILES=()

if [ "${#INPUT_FILES[@]}" -gt 0 ]; then
    echo "Input files explicitly provided: ${#INPUT_FILES[@]}"
    for f in "${INPUT_FILES[@]}"; do
        # Accept bare filename or full path
        if [ -f "$f" ]; then
            CANDIDATE_FILES+=("$f")
        elif [ -f "$DATA_DIR/$f" ]; then
            CANDIDATE_FILES+=("$DATA_DIR/$f")
        else
            echo "  ⚠ File not found, skipping: $f"
        fi
    done
else
    echo "No input files specified – auto-scanning $DATA_DIR/*.mbtiles"
    for f in "$DATA_DIR"/*.mbtiles; do
        [ -f "$f" ] || continue
        fn=$(basename "$f")
        [ "$fn" = "glmap.mbtiles"      ] && continue
        [ "$fn" = "grid_layer.mbtiles" ] && continue
        # Skip any existing BPDAS combined files to avoid circular merge
        [[ "$fn" == glmap_*_*.mbtiles  ]] && continue
        case "$fn" in *_trails*) continue ;; esac
        CANDIDATE_FILES+=("$f")
    done
fi

echo "Candidates collected: ${#CANDIDATE_FILES[@]}"

# ============================================================
# STEP 3: Merge into GLOBAL glmap.mbtiles (incremental)
# ============================================================
log_info "=== Step 3: Merging into Global glmap.mbtiles ==="
echo ""
echo "=== Step 3: Merging into Global glmap.mbtiles ==="

GLOBAL_NEW_COUNT=0
GLOBAL_SKIP_COUNT=0

for mbtiles_file in "${CANDIDATE_FILES[@]}"; do
    [ -f "$mbtiles_file" ] || continue
    filename=$(basename "$mbtiles_file")

    if is_already_merged "$MERGE_LOG" "$filename"; then
        GLOBAL_SKIP_COUNT=$((GLOBAL_SKIP_COUNT + 1))
        continue
    fi

    if is_valid_mbtiles "$mbtiles_file"; then
        tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        echo "  Merging (global): $filename ($tile_count tiles)"
        merge_into "$mbtiles_file" "$GLMAP_FILE" "$MERGE_LOG"
        GLOBAL_NEW_COUNT=$((GLOBAL_NEW_COUNT + 1))
    else
        echo "  Skipping (invalid): $filename"
    fi
done

global_total=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
log_success "Global merge done. New=$GLOBAL_NEW_COUNT Skipped=$GLOBAL_SKIP_COUNT Total tiles=$global_total"
echo "✓ Global merge: $GLOBAL_NEW_COUNT new, $GLOBAL_SKIP_COUNT already merged. Total tiles=$global_total"

# ============================================================
# STEP 4: Merge into BPDAS-specific glmap (if YEAR+BPDAS given)
# ============================================================
BPDAS_NEW_COUNT=0
BPDAS_SKIP_COUNT=0

if [ -n "$BPDAS_GLMAP_FILE" ]; then
    log_info "=== Step 4: Merging into BPDAS glmap ($BPDAS_KEY) ==="
    echo ""
    echo "=== Step 4: Merging into BPDAS glmap ($BPDAS_KEY) ==="

    for mbtiles_file in "${CANDIDATE_FILES[@]}"; do
        [ -f "$mbtiles_file" ] || continue
        filename=$(basename "$mbtiles_file")

        if is_already_merged "$BPDAS_MERGE_LOG" "$filename"; then
            BPDAS_SKIP_COUNT=$((BPDAS_SKIP_COUNT + 1))
            continue
        fi

        if is_valid_mbtiles "$mbtiles_file"; then
            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            echo "  Merging (BPDAS): $filename ($tile_count tiles)"
            merge_into "$mbtiles_file" "$BPDAS_GLMAP_FILE" "$BPDAS_MERGE_LOG"
            BPDAS_NEW_COUNT=$((BPDAS_NEW_COUNT + 1))
        else
            echo "  Skipping (invalid): $filename"
        fi
    done

    bpdas_total=$(sqlite3 "$BPDAS_GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    log_success "BPDAS merge done. New=$BPDAS_NEW_COUNT Skipped=$BPDAS_SKIP_COUNT Total tiles=$bpdas_total"
    echo "✓ BPDAS merge ($BPDAS_KEY): $BPDAS_NEW_COUNT new, $BPDAS_SKIP_COUNT already merged. Total tiles=$bpdas_total"
fi

# ============================================================
# STEP 5: Generate config.json
# ============================================================
log_info "=== Step 5: Generating Config ==="
echo ""
echo "=== Step 5: Generating Config ==="

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

# --- grid_layer (static vector)
if [ -f "$GRID_MBTILES" ]; then
    cat >> "$TEMP_CONFIG" << 'EOF'
    "grid_layer": {
      "mbtiles": "data/grid_layer.mbtiles"
    },
EOF
    echo "  Added: grid_layer (vector, zoom 0-14)"
fi

# --- global glmap (drone raster)
cat >> "$TEMP_CONFIG" << 'EOF'
    "glmap": {
      "mbtiles": "data/glmap.mbtiles"
    }
EOF
echo "  Added: glmap (global drone, zoom 16-22)"

# --- BPDAS-specific glmap (if applicable)
if [ -n "$BPDAS_GLMAP_FILE" ] && [ -f "$BPDAS_GLMAP_FILE" ]; then
    cat >> "$TEMP_CONFIG" << EOF
    ,
    "$BPDAS_KEY": {
      "mbtiles": "data/${BPDAS_KEY}.mbtiles"
    }
EOF
    echo "  Added: $BPDAS_KEY ($BPDAS_LABEL)"
fi

# --- Scan for any OTHER existing BPDAS combined files not yet in config
#     (so previously generated ones persist across runs)
for existing_bpdas in "$DATA_DIR"/glmap_*_*.mbtiles; do
    [ -f "$existing_bpdas" ] || continue
    eb_filename=$(basename "$existing_bpdas" .mbtiles)

    # Skip the one we just added above (already included)
    [ "$eb_filename" = "$BPDAS_KEY" ] && continue

    if is_valid_mbtiles "$existing_bpdas"; then
        cat >> "$TEMP_CONFIG" << EOF
    ,
    "$eb_filename": {
      "mbtiles": "data/${eb_filename}.mbtiles"
    }
EOF
        echo "  Added (existing BPDAS): $eb_filename"
    fi
done

# --- Individual drone files
INDIVIDUAL_COUNT=0
SKIPPED_INVALID=0
echo "Scanning individual mbtiles for config..."

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue

    filename=$(basename "$mbtiles_file")
    basename_only=$(basename "$mbtiles_file" .mbtiles)

    # Skip special/combined files
    [ "$filename" = "glmap.mbtiles"      ] && continue
    [ "$filename" = "grid_layer.mbtiles" ] && continue
    [[ "$filename" == glmap_*_*.mbtiles  ]] && continue
    case "$filename" in *_trails*) echo "  Skipping (trails): $filename"; continue ;; esac

    if is_valid_mbtiles "$mbtiles_file"; then
        cat >> "$TEMP_CONFIG" << EOF
    ,
    "$basename_only": {
      "mbtiles": "data/$filename"
    }
EOF
        echo "  Added: $filename"
        INDIVIDUAL_COUNT=$((INDIVIDUAL_COUNT + 1))
    else
        echo "  Skipping (invalid): $filename"
        SKIPPED_INVALID=$((SKIPPED_INVALID + 1))
    fi
done

echo "  }" >> "$TEMP_CONFIG"
echo "}" >> "$TEMP_CONFIG"

echo "✓ Added $INDIVIDUAL_COUNT individual files | $SKIPPED_INVALID skipped"

# Validate & write
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool "$TEMP_CONFIG" >/dev/null 2>&1; then
        echo "✓ JSON valid"
        cp "$TEMP_CONFIG" "$CONFIG_FILE"
    else
        echo "✗ JSON invalid! Dumping:"
        cat "$TEMP_CONFIG"
        exit 1
    fi
else
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
fi

TOTAL_DATASETS=$((INDIVIDUAL_COUNT + 1))
echo "✓ Config written: $CONFIG_FILE ($TOTAL_DATASETS datasets)"

# Preview
echo ""
echo "=== Generated Config Preview ==="
if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$CONFIG_FILE" 2>/dev/null | head -60 || head -60 "$CONFIG_FILE"
else
    head -60 "$CONFIG_FILE"
fi
echo "..."

# ============================================================
# STEP 6: Restart tileserver container
# ============================================================
log_info "=== Step 6: Restarting Tileserver Container ==="
echo ""
echo "=== Step 6: Restarting Tileserver Container ==="
if command -v docker >/dev/null 2>&1; then
    echo "Restarting tileserver container..."
    if docker restart tileserver-zurich; then
        echo "✓ Container restarted – new tiles now available"
    else
        echo "✗ Restart failed"
    fi
else
    echo "⚠ Docker not available – restart container manually"
fi

# ============================================================
# STEP 7: Database update (PostgreSQL)
# ============================================================
log_info "=== Step 7: Updating PostgreSQL Database ==="
echo ""
echo "=== Step 7: Updating PostgreSQL Database ==="

DBHOST="172.26.11.153"
DBUSER="pg"
DBPASS="~nagha2025yasha@~"
DBNAME="postgres"
DBPORT="5432"

log_info "Database: $DBUSER@$DBHOST:$DBPORT/$DBNAME"

if [ "$SKIP_DB_UPDATE" = "true" ]; then
    log_info "Database update skipped (SKIP_DB_UPDATE=true)"
    echo "Database update skipped."
else
    DB_UPDATE_AVAILABLE="true"

    if ! python3 -c "import psycopg2" 2>/dev/null; then
        echo "Installing psycopg2-binary..."
        pip3 install psycopg2-binary >/dev/null 2>&1 && echo "✓ Installed" || { echo "✗ Failed – skipping DB update"; DB_UPDATE_AVAILABLE="false"; }
    else
        echo "✓ psycopg2 available"
    fi

    command -v bc >/dev/null 2>&1 || apt-get install -y bc >/dev/null 2>&1 || true

    extract_coordinates() {
        local mbtiles_file="$1"
        local bounds center west south east north lat lon

        bounds=$(sqlite3 "$mbtiles_file" "SELECT value FROM metadata WHERE name='bounds';" 2>/dev/null || echo "")
        if [ -n "$bounds" ]; then
            west=$(echo "$bounds" | cut -d',' -f1)
            south=$(echo "$bounds" | cut -d',' -f2)
            east=$(echo "$bounds"  | cut -d',' -f3)
            north=$(echo "$bounds" | cut -d',' -f4)
            if command -v bc >/dev/null 2>&1; then
                lat=$(echo "scale=6; ($south + $north) / 2" | bc 2>/dev/null || echo "-0.469")
                lon=$(echo "scale=6; ($west  + $east)  / 2" | bc 2>/dev/null || echo "117.172")
            else
                lat=$(awk "BEGIN {printf \"%.6f\", ($south + $north) / 2}")
                lon=$(awk "BEGIN {printf \"%.6f\", ($west  + $east)  / 2}")
            fi
            echo "$lat,$lon"; return 0
        fi

        center=$(sqlite3 "$mbtiles_file" "SELECT value FROM metadata WHERE name='center';" 2>/dev/null || echo "")
        if [ -n "$center" ]; then
            lon=$(echo "$center" | cut -d',' -f1)
            lat=$(echo "$center" | cut -d',' -f2)
            echo "$lat,$lon"; return 0
        fi

        echo "-0.469,117.172"
    }

    update_database() {
        local filename="$1" latitude="$2" longitude="$3"
        echo "Updating DB: $filename -> lat=$latitude, lon=$longitude"
        python3 << PYEOF
import psycopg2, sys
try:
    conn = psycopg2.connect(host='$DBHOST', port=$DBPORT, user='$DBUSER', password='$DBPASS', database='$DBNAME')
    cur  = conn.cursor()
    cur.execute("""
        SELECT id, title, latitude, longitude, storage_path
        FROM geoportal.pmn_drone_imagery
        WHERE storage_path LIKE %s
    """, ('%${filename}.mbtiles%',))
    records = cur.fetchall()
    if records:
        for r in records:
            print(f"  Found: {r[0]} - {r[1]} (was: {r[2]}, {r[3]})")
        cur.execute("""
            UPDATE geoportal.pmn_drone_imagery
            SET latitude=%s, longitude=%s, status='Aktif', updated_at=NOW()
            WHERE storage_path LIKE %s
        """, ($latitude, $longitude, '%${filename}.mbtiles%'))
        print(f"  ✓ Updated {cur.rowcount} record(s)")
        conn.commit()
    else:
        print(f"  ⚠ No records found for ${filename}")
    cur.close(); conn.close()
except Exception as e:
    print(f"  ✗ DB error: {e}")
    sys.exit(1)
PYEOF
    }

    if [ "$DB_UPDATE_AVAILABLE" = "true" ]; then
        echo "Updating newly merged files..."

        # Update global newly merged files
        for mbtiles_file in "${CANDIDATE_FILES[@]}"; do
            [ -f "$mbtiles_file" ] || continue
            filename=$(basename "$mbtiles_file" .mbtiles)
            echo ""; echo "Processing (DB): $filename"
            coords=$(extract_coordinates "$mbtiles_file")
            lat=$(echo "$coords" | cut -d',' -f1)
            lon=$(echo "$coords" | cut -d',' -f2)
            echo "  Coordinates: lat=$lat, lon=$lon"
            update_database "$filename" "$lat" "$lon"
        done

        # Update glmap global
        if [ -f "$GLMAP_FILE" ]; then
            echo ""; echo "Processing (DB): glmap"
            coords=$(extract_coordinates "$GLMAP_FILE")
            lat=$(echo "$coords" | cut -d',' -f1)
            lon=$(echo "$coords" | cut -d',' -f2)
            update_database "glmap" "$lat" "$lon"
        fi

        # Update BPDAS glmap
        if [ -n "$BPDAS_GLMAP_FILE" ] && [ -f "$BPDAS_GLMAP_FILE" ]; then
            echo ""; echo "Processing (DB): $BPDAS_KEY"
            coords=$(extract_coordinates "$BPDAS_GLMAP_FILE")
            lat=$(echo "$coords" | cut -d',' -f1)
            lon=$(echo "$coords" | cut -d',' -f2)
            update_database "$BPDAS_KEY" "$lat" "$lon"
        fi

        echo ""; echo "✓ Database update completed"
    fi
fi

# Cleanup
rm -f "$TEMP_CONFIG"

# ============================================================
# FINAL SUMMARY
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "                     GENERATION SUMMARY"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "📊 TILE COUNTS:"

drone_tiles=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
grid_tiles=0
[ -f "$GRID_MBTILES" ] && grid_tiles=$(sqlite3 "$GRID_MBTILES" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")

if [ -f "$GRID_MBTILES" ]; then
    echo "✓ grid_layer.mbtiles (STATIC / SEPARATE):"
    echo "  - Format: Vector (PBF) | Zoom: 0-14 | Tiles: $grid_tiles"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf"
    echo ""
fi

echo "✓ glmap.mbtiles (GLOBAL DRONE):"
echo "  - Format: Raster (JPG) | Zoom: 16-22 | Tiles: $drone_tiles"
echo "  - URL: https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg"
echo "  - New merged: $GLOBAL_NEW_COUNT | Already merged: $GLOBAL_SKIP_COUNT"
echo ""

if [ -n "$BPDAS_GLMAP_FILE" ] && [ -f "$BPDAS_GLMAP_FILE" ]; then
    bpdas_total=$(sqlite3 "$BPDAS_GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    echo "✓ $BPDAS_KEY ($BPDAS_LABEL):"
    echo "  - Format: Raster (JPG) | Zoom: 16-22 | Tiles: $bpdas_total"
    echo "  - URL: https://glserver.ptnaghayasha.com/data/$BPDAS_KEY/{z}/{x}/{y}.jpg"
    echo "  - New merged: $BPDAS_NEW_COUNT | Already merged: $BPDAS_SKIP_COUNT"
    echo "  - Merge log: $BPDAS_MERGE_LOG"
    echo ""
fi

echo "📦 MERGE STATUS:"
echo "  Global new: $GLOBAL_NEW_COUNT | Global skipped: $GLOBAL_SKIP_COUNT"
[ -n "$BPDAS_KEY" ] && echo "  BPDAS new:  $BPDAS_NEW_COUNT | BPDAS skipped:  $BPDAS_SKIP_COUNT"
echo "  Total datasets in config: $TOTAL_DATASETS"
echo ""
echo "🎯 XYZ ARCHITECTURE:"
echo "  Layer 1 (Base):    grid_layer      — Grid overview (zoom 0-14)"
echo "  Layer 2 (Overlay): glmap           — All drone imagery (zoom 16-22)"
[ -n "$BPDAS_KEY" ] && \
echo "  Layer 3 (BPDAS):   $BPDAS_KEY — $BPDAS_LABEL (zoom 16-22)"
echo ""
echo "Next run will only merge NEW drone files — fast incremental! 🚀"