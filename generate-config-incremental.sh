#!/bin/bash

# Enhanced generate-config.sh dengan incremental merge, separate grid layer,
# dan dukungan penuh filter tahun/bulan/bpdas (semua kombinasi).
#
# Semua non-empty subset dari {tahun, bulan, bpdas} yang di-provide akan
# menghasilkan combined mbtiles tersendiri, misalnya:
#   glmap_2026.mbtiles            (tahun saja)
#   glmap_06.mbtiles              (bulan saja)
#   glmap_AGAMKUANTAN.mbtiles     (bpdas saja)
#   glmap_2026_06.mbtiles         (tahun + bulan)
#   glmap_2026_AGAMKUANTAN.mbtiles (tahun + bpdas)
#   glmap_06_AGAMKUANTAN.mbtiles  (bulan + bpdas)
#   glmap_2026_06_AGAMKUANTAN.mbtiles (tahun + bulan + bpdas)
#
# Usage (named flags — recommended):
#   ./generate-config-incremental.sh
#   ./generate-config-incremental.sh --tahun 2026
#   ./generate-config-incremental.sh --tahun 2026 --bulan 6
#   ./generate-config-incremental.sh --tahun 2026 --bulan 6 --bpdas AGAMKUANTAN file1.mbtiles ...
#
# Legacy positional form (masih di-support untuk backward compat webhook):
#   ./generate-config-incremental.sh 2026 AGAMKUANTAN file1.mbtiles ...

set -e

# ─────────────────────────────────────────────
# Logging functions
# ─────────────────────────────────────────────
log_info()    { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]    $*" >&2; }
log_error()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]   $*" >&2; }
log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >&2; }

# ─────────────────────────────────────────────
# Parse arguments
# Named flags: --tahun, --bulan, --bpdas; remaining args = file list
# Legacy positional: YEAR BPDAS [files...]
# ─────────────────────────────────────────────
PARAM_YEAR=""
PARAM_BULAN=""
PARAM_BPDAS=""
PARAM_FILES=()

if [ $# -ge 2 ] && [[ "$1" =~ ^[0-9]{4}$ ]] && [[ "$2" != --* ]]; then
    # Legacy positional mode
    PARAM_YEAR="$1"
    PARAM_BPDAS=$(echo "$2" | tr '[:lower:]' '[:upper:]')
    shift 2
    while [ $# -gt 0 ]; do PARAM_FILES+=("$1"); shift; done
else
    while [ $# -gt 0 ]; do
        case "$1" in
            --tahun) PARAM_YEAR="$2"; shift 2 ;;
            --bulan) PARAM_BULAN="$2"; shift 2 ;;
            --bpdas) PARAM_BPDAS=$(echo "$2" | tr '[:lower:]' '[:upper:]'); shift 2 ;;
            --) shift; while [ $# -gt 0 ]; do PARAM_FILES+=("$1"); shift; done; break ;;
            -*) log_error "Unknown flag: $1"; exit 1 ;;
            *) PARAM_FILES+=("$1"); shift ;;
        esac
    done
fi

# Zero-pad month: 6 → 06 (konsisten dengan slugFor di frontend)
PARAM_BULAN_PAD=""
[ -n "$PARAM_BULAN" ] && PARAM_BULAN_PAD=$(printf "%02d" "$PARAM_BULAN")

log_info "Script started: generate-config-incremental.sh"
log_info "PARAM_YEAR:  ${PARAM_YEAR:-<not set>}"
log_info "PARAM_BULAN: ${PARAM_BULAN:-<not set>} (padded: ${PARAM_BULAN_PAD:-n/a})"
log_info "PARAM_BPDAS: ${PARAM_BPDAS:-<not set>}"
log_info "PARAM_FILES: ${PARAM_FILES[*]:-<none>}"

# ─────────────────────────────────────────────
# Build TARGET_SUFFIXES: semua non-empty subset dari params yang di-provide.
# Setiap suffix → glmap_${suffix}.mbtiles + .merged_${suffix}.log
# ─────────────────────────────────────────────
TARGET_SUFFIXES=()

[ -n "$PARAM_YEAR" ]      && TARGET_SUFFIXES+=("$PARAM_YEAR")
[ -n "$PARAM_BULAN_PAD" ] && TARGET_SUFFIXES+=("$PARAM_BULAN_PAD")
[ -n "$PARAM_BPDAS" ]     && TARGET_SUFFIXES+=("$PARAM_BPDAS")

if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BULAN_PAD" ]; then
    TARGET_SUFFIXES+=("${PARAM_YEAR}_${PARAM_BULAN_PAD}")
fi
if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BPDAS" ]; then
    TARGET_SUFFIXES+=("${PARAM_YEAR}_${PARAM_BPDAS}")
fi
if [ -n "$PARAM_BULAN_PAD" ] && [ -n "$PARAM_BPDAS" ]; then
    TARGET_SUFFIXES+=("${PARAM_BULAN_PAD}_${PARAM_BPDAS}")
fi
if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BULAN_PAD" ] && [ -n "$PARAM_BPDAS" ]; then
    TARGET_SUFFIXES+=("${PARAM_YEAR}_${PARAM_BULAN_PAD}_${PARAM_BPDAS}")
fi

log_info "TARGET_SUFFIXES: ${TARGET_SUFFIXES[*]:-<none — global only>}"

# ─────────────────────────────────────────────
# Environment & paths
# ─────────────────────────────────────────────
FORCE_REBUILD="${FORCE_REBUILD:-false}"

log_info "Working directory: $(pwd)"
log_info "FORCE_REBUILD: $FORCE_REBUILD"

if [ -n "$DATA_DIR" ]; then
    log_info "Using provided DATA_DIR: $DATA_DIR"
    case "$DATA_DIR" in
      /app/*) BASE_DIR="/app" ;;
      *)      BASE_DIR=$(dirname "$DATA_DIR") ;;
    esac
elif [ -d "/app/data/tileserver" ]; then
    DATA_DIR="/app/data/tileserver"
    BASE_DIR="/app"
    log_info "Detected Docker environment: /app/data/tileserver"
elif [ -d "/app/data" ]; then
    DATA_DIR="/app/data"
    BASE_DIR="/app"
    log_info "Detected Docker environment: /app/data"
elif [ -d "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/data" ]; then
    BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    DATA_DIR="$BASE_DIR/data"
    log_info "Detected host environment (relative to script): $DATA_DIR"
else
    log_error "Data directory not found"
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-$BASE_DIR/config.json}"
STYLE_DIR="${STYLE_DIR:-$BASE_DIR/styles/default}"
STYLE_FILE="${STYLE_FILE:-$STYLE_DIR/style.json}"
GLMAP_FILE="${GLMAP_FILE:-$DATA_DIR/glmap.mbtiles}"
GRID_MBTILES="${GRID_MBTILES:-$DATA_DIR/grid_layer.mbtiles}"
MERGE_LOG="${MERGE_LOG:-$DATA_DIR/.merged_files.log}"
TEMP_CONFIG="${TEMP_CONFIG:-/tmp/config_temp.json}"

GRID_DIR="$DATA_DIR/GRID_DRONE_36_HA_EKSISTING_POTENSI"
GRID_SHP="$GRID_DIR/GRID_36_HA_EKSISTING_POTENSI.shp"

log_info "=== Configuration ==="
log_info "Data directory: $DATA_DIR"
log_info "Config file:    $CONFIG_FILE"
log_info "Glmap (global): $GLMAP_FILE"
for s in "${TARGET_SUFFIXES[@]}"; do
    log_info "Glmap ($s): $DATA_DIR/glmap_${s}.mbtiles"
done

echo "=== Enhanced Generate Config Script ==="
echo "Data directory: $DATA_DIR"
printf "Params — Year: %s | Bulan: %s | BPDAS: %s\n" \
    "${PARAM_YEAR:-none}" "${PARAM_BULAN:-none}" "${PARAM_BPDAS:-none}"
echo "Targets: global ${TARGET_SUFFIXES[*]:-}"
echo ""

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
# Step 0: Handle FORCE_REBUILD — hapus semua target lama
# ─────────────────────────────────────────────
if [ "$FORCE_REBUILD" = "true" ]; then
    log_info "FORCE_REBUILD enabled — removing old files"
    echo "⚠ FORCE_REBUILD enabled..."
    rm -f "$GLMAP_FILE" "$MERGE_LOG"
    touch "$MERGE_LOG"
    for s in "${TARGET_SUFFIXES[@]}"; do
        rm -f "$DATA_DIR/glmap_${s}.mbtiles" "$DATA_DIR/.merged_${s}.log"
        touch "$DATA_DIR/.merged_${s}.log"
        log_info "Cleared: glmap_${s}.mbtiles"
    done
    echo "✓ Old files removed, will merge from scratch"
fi

# ─────────────────────────────────────────────
# Step 1: Initialize merge logs & mbtiles targets
# ─────────────────────────────────────────────
log_info "=== Step 1: Initializing mbtiles targets ==="
echo ""
echo "=== Step 1: Initializing mbtiles targets ==="

[ ! -f "$MERGE_LOG" ] && touch "$MERGE_LOG"
ensure_mbtiles "$GLMAP_FILE" "Drone Imagery (High Resolution)"

for s in "${TARGET_SUFFIXES[@]}"; do
    target="$DATA_DIR/glmap_${s}.mbtiles"
    log_file="$DATA_DIR/.merged_${s}.log"
    [ ! -f "$log_file" ] && touch "$log_file"
    ensure_mbtiles "$target" "GL Map Combined ${s//_/ }"
done

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
# Step 3: Merge ALL new *.mbtiles in DATA_DIR into global glmap
# (Incremental — skip already-merged files)
# ─────────────────────────────────────────────
log_info "=== Step 3: Merging Drone Imagery into Global glmap ==="
echo ""
echo "=== Step 3: Merging Drone Imagery into Global glmap ==="

NEW_FILES_GLOBAL=()
SKIPPED_COUNT=0

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    filename=$(basename "$mbtiles_file")

    # Skip special/managed files
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
# Step 4: Merge argument files into per-filter targets
# Setiap file yang di-pass sebagai argumen di-merge ke SEMUA TARGET_SUFFIXES
# (karena file itu termasuk dalam tahun+bulan+bpdas yang di-specify)
# ─────────────────────────────────────────────
if [ "${#TARGET_SUFFIXES[@]}" -gt 0 ]; then
    log_info "=== Step 4: Merging Argument Files into Per-Filter Targets ==="
    echo ""
    echo "=== Step 4: Merging Argument Files into Per-Filter Targets ==="
    echo "Targets: ${TARGET_SUFFIXES[*]}"

    if [ "${#PARAM_FILES[@]}" -eq 0 ]; then
        echo "⚠ No files specified as arguments — per-filter targets will not receive new tiles"
        log_info "No argument files provided, skipping per-filter merge"
    else
        for filename in "${PARAM_FILES[@]}"; do
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

            for s in "${TARGET_SUFFIXES[@]}"; do
                target="$DATA_DIR/glmap_${s}.mbtiles"
                log_file="$DATA_DIR/.merged_${s}.log"
                merge_into "$target" "$mbtiles_file" "$log_file"
            done
        done

        echo ""
        for s in "${TARGET_SUFFIXES[@]}"; do
            target="$DATA_DIR/glmap_${s}.mbtiles"
            count=$(sqlite3 "$target" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            log_success "glmap_${s}.mbtiles → $count tiles"
            echo "✓ glmap_${s}.mbtiles → $count tiles"
        done
    fi
fi

# ─────────────────────────────────────────────
# Step 4b: Auto-discover BPDAS dari DB dan generate per-BPDAS combinations
# Hanya berjalan jika --bpdas TIDAK di-set tapi ada tahun/bulan.
# Script query DB → dapat semua BPDAS beserta daftar filenya → merge masing-masing.
# ─────────────────────────────────────────────
if [ -z "$PARAM_BPDAS" ] && { [ -n "$PARAM_YEAR" ] || [ -n "$PARAM_BULAN_PAD" ]; }; then
    log_info "=== Step 4b: Auto-discovering BPDAS from database ==="
    echo ""
    echo "=== Step 4b: Auto-discovering BPDAS from database ==="

    DB_UPDATE_AVAILABLE_4B="true"
    if ! python3 -c "import psycopg2" 2>/dev/null; then
        if ! pip3 install psycopg2-binary >/dev/null 2>&1; then
            echo "⚠ psycopg2 not available — skipping BPDAS auto-discover"
            DB_UPDATE_AVAILABLE_4B="false"
        fi
    fi

    if [ "$DB_UPDATE_AVAILABLE_4B" = "true" ]; then
        # Query DB: bpdas → list of filenames (diambil dari storage_path)
        BPDAS_MAP_JSON=$(python3 << PYEOF
import psycopg2, json, sys
from collections import defaultdict
try:
    conn = psycopg2.connect(
        host='$DBHOST', port=$DBPORT,
        user='$DBUSER', password='$DBPASS', database='$DBNAME'
    )
    cur = conn.cursor()
    where = ["bpdas IS NOT NULL", "captured_at IS NOT NULL", "storage_path IS NOT NULL"]
    params = []
    if '$PARAM_YEAR':
        where.append("EXTRACT(YEAR FROM captured_at) = %s")
        params.append(int('$PARAM_YEAR'))
    if '$PARAM_BULAN':
        where.append("EXTRACT(MONTH FROM captured_at) = %s")
        params.append(int('$PARAM_BULAN'))
    sql = "SELECT bpdas, storage_path FROM geoportal.pmn_drone_imagery WHERE " + " AND ".join(where)
    cur.execute(sql, params)
    bpdas_files = defaultdict(list)
    for bpdas, sp in cur.fetchall():
        fname = sp.rstrip('/').split('/')[-1]
        bpdas_files[bpdas.strip().upper()].append(fname)
    print(json.dumps(dict(bpdas_files)))
    cur.close(); conn.close()
except Exception as e:
    print(json.dumps({}), file=sys.stderr)
    print("{}")
PYEOF
)

        # Iterasi setiap BPDAS yang ditemukan
        BPDAS_LIST=$(python3 -c "import json,sys; d=json.loads('$BPDAS_MAP_JSON'); [print(k) for k in d.keys()]" 2>/dev/null || true)

        if [ -z "$BPDAS_LIST" ]; then
            echo "⚠ Tidak ada BPDAS ditemukan di DB untuk filter ini"
        else
            echo "BPDAS ditemukan:"
            echo "$BPDAS_LIST" | while read -r bpdas; do echo "  - $bpdas"; done

            echo "$BPDAS_LIST" | while read -r AUTO_BPDAS; do
                [ -z "$AUTO_BPDAS" ] && continue
                echo ""
                echo "── Processing BPDAS: $AUTO_BPDAS ──"

                # Ambil daftar file untuk BPDAS ini dari JSON
                AUTO_FILES_JSON=$(python3 -c "
import json
d = json.loads('''$BPDAS_MAP_JSON''')
files = d.get('$AUTO_BPDAS', [])
print(' '.join(files))
" 2>/dev/null || echo "")

                # Build target suffixes untuk kombinasi yang melibatkan AUTO_BPDAS
                AUTO_SUFFIXES=()
                AUTO_SUFFIXES+=("$AUTO_BPDAS")
                [ -n "$PARAM_YEAR" ]      && AUTO_SUFFIXES+=("${PARAM_YEAR}_${AUTO_BPDAS}")
                [ -n "$PARAM_BULAN_PAD" ] && AUTO_SUFFIXES+=("${PARAM_BULAN_PAD}_${AUTO_BPDAS}")
                if [ -n "$PARAM_YEAR" ] && [ -n "$PARAM_BULAN_PAD" ]; then
                    AUTO_SUFFIXES+=("${PARAM_YEAR}_${PARAM_BULAN_PAD}_${AUTO_BPDAS}")
                fi

                # Init targets
                for s in "${AUTO_SUFFIXES[@]}"; do
                    target="$DATA_DIR/glmap_${s}.mbtiles"
                    log_file="$DATA_DIR/.merged_${s}.log"
                    [ ! -f "$log_file" ] && touch "$log_file"
                    ensure_mbtiles "$target" "GL Map Combined ${s//_/ }"
                done

                # Merge file-file yang ada di DATA_DIR
                MERGED_FOR_BPDAS=0
                for fname in $AUTO_FILES_JSON; do
                    mbtiles_file="$DATA_DIR/$fname"
                    [ -f "$mbtiles_file" ] || { echo "  ⚠ Not in DATA_DIR: $fname"; continue; }
                    ! is_valid_mbtiles "$mbtiles_file" && { echo "  ✗ Invalid: $fname"; continue; }

                    tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
                    echo "  File: $fname ($tile_count tiles)"
                    for s in "${AUTO_SUFFIXES[@]}"; do
                        target="$DATA_DIR/glmap_${s}.mbtiles"
                        log_file="$DATA_DIR/.merged_${s}.log"
                        merge_into "$target" "$mbtiles_file" "$log_file"
                    done
                    MERGED_FOR_BPDAS=$((MERGED_FOR_BPDAS + 1))
                done

                echo "  → $MERGED_FOR_BPDAS file(s) processed for $AUTO_BPDAS"
                for s in "${AUTO_SUFFIXES[@]}"; do
                    target="$DATA_DIR/glmap_${s}.mbtiles"
                    count=$(sqlite3 "$target" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
                    echo "  ✓ glmap_${s}.mbtiles → $count tiles"
                done
            done
        fi
    fi
fi

# ─────────────────────────────────────────────
# Step 5: Generate config.json
# Scan semua glmap_*.mbtiles di disk (dinamis, tidak perlu daftar manual)
# ─────────────────────────────────────────────
log_info "=== Step 5: Generating Config ==="
echo ""
echo "=== Step 5: Generating Config ==="

# Helper: append a data entry to temp config
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
      "style": "default/style.json"
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

# All existing per-filter glmap files — scan disk (picks up all combinations)
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
# Step 7: Database update — update lat/lon/status untuk file yang baru dimerge
# ─────────────────────────────────────────────
log_info "=== Step 7: Updating PostgreSQL Database ==="
echo ""
echo "=== Step 7: Updating PostgreSQL Database ==="

DBHOST="${DBHOST:-172.16.3.102}"
DBUSER="${DBUSER:-app_db}"
DBPASS="${DBPASS:-R00T_DB_M4ND4R4}"
DBNAME="${DBNAME:-postgres}"
DBPORT="${DBPORT:-5432}"

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

        # Update argument files (per-filter)
        if [ "${#TARGET_SUFFIXES[@]}" -gt 0 ] && [ "${#PARAM_FILES[@]}" -gt 0 ]; then
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
    echo "  - URL: https://mandara.pdasrh.kehutanan.go.id/glserver/data/grid_layer/{z}/{x}/{y}.pbf"
    echo ""
fi

echo "✓ glmap.mbtiles (Drone Global):"
echo "  - Zoom: 16-22  |  Tiles: $drone_tiles"
echo "  - URL: https://mandara.pdasrh.kehutanan.go.id/glserver/data/glmap/{z}/{x}/{y}.jpg"

if [ "${#TARGET_SUFFIXES[@]}" -gt 0 ]; then
    echo ""
    for s in "${TARGET_SUFFIXES[@]}"; do
        target="$DATA_DIR/glmap_${s}.mbtiles"
        count=$(sqlite3 "$target" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        echo "✓ glmap_${s}.mbtiles:"
        echo "  - Tiles: $count"
        echo "  - URL: https://mandara.pdasrh.kehutanan.go.id/glserver/data/glmap_${s}/{z}/{x}/{y}.jpg"
    done
fi

echo ""
echo "📦 MERGE STATUS:"
echo "✓ New files merged (global): ${#NEW_FILES_GLOBAL[@]}"
echo "✓ Already merged (global):   $SKIPPED_COUNT"
[ "${#TARGET_SUFFIXES[@]}" -gt 0 ] && echo "✓ Targets generated:         ${#TARGET_SUFFIXES[@]}"
[ "${#TARGET_SUFFIXES[@]}" -gt 0 ] && echo "✓ Argument files (filters):  ${#PARAM_FILES[@]}"
echo "✓ Total datasets in config:  $TOTAL_DATASETS"
echo ""
echo "🎯 ARCHITECTURE:"
echo "  Layer 1 (Base):    grid_layer — Grid overview (zoom 0-14)"
echo "  Layer 2 (Overlay): glmap      — Drone imagery global (zoom 16-22)"
for s in "${TARGET_SUFFIXES[@]}"; do
    echo "  Filter subset:     glmap_${s} (zoom 16-22)"
done
echo ""
echo "🚀 Next run will only process new files!"
