#!/bin/bash

# Enhanced generate-config.sh dengan incremental merge dan separate grid layer
# Features:
# 1. Incremental merge - hanya merge file drone baru
# 2. Grid layer SEPARATE - tidak dimerge ke glmap (optimal performance)

set -e

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

# Environment detection
if [ -n "$DATA_DIR" ]; then
    log_info "Using provided DATA_DIR: $DATA_DIR"
    # Detect base directory
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

echo "=== Enhanced Generate Config Script ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"
echo "Grid directory: $GRID_DIR"
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
log_info "=== Step 1: Creating Combined glmap (Grid + Drone) ==="
echo "=== Step 1: Creating Combined glmap (Grid + Drone) ==="

# Check data directory
if [ ! -d "$DATA_DIR" ]; then
    log_error "Data directory does not exist: $DATA_DIR"
    echo "Error: Data directory does not exist"
    exit 1
fi

log_info "Data directory exists: $DATA_DIR"

# Initialize merge log if not exists
[ ! -f "$MERGE_LOG" ] && touch "$MERGE_LOG"

log_info "Merge log initialized: $MERGE_LOG"

# Force rebuild: remove old glmap and merge log
if [ "$FORCE_REBUILD" = "true" ]; then
    log_info "FORCE_REBUILD enabled - removing old files"
    echo "⚠ FORCE_REBUILD enabled - removing old glmap and merge log..."
    rm -f "$GLMAP_FILE"
    rm -f "$MERGE_LOG"
    touch "$MERGE_LOG"
    echo "✓ Old files removed, will merge all files from scratch"
    log_success "Old files removed for rebuild"
fi

# Initialize glmap if not exists (should already exist from Step 1)
if [ ! -f "$GLMAP_FILE" ]; then
    log_info "Creating new glmap.mbtiles (DRONE ONLY - zoom 16-22)"
    echo "Creating new glmap.mbtiles (DRONE ONLY - zoom 16-22)..."
    sqlite3 "$GLMAP_FILE" "
        CREATE TABLE metadata (name text PRIMARY KEY, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
        INSERT INTO metadata (name, value) VALUES ('name', 'Drone Imagery (High Resolution)');
        INSERT INTO metadata (name, value) VALUES ('type', 'overlay');
        INSERT INTO metadata (name, value) VALUES ('format', 'jpg');
        INSERT INTO metadata (name, value) VALUES ('description', 'High-resolution drone imagery for detailed mapping');
        INSERT INTO metadata (name, value) VALUES ('version', '1.3');
        INSERT INTO metadata (name, value) VALUES ('attribution', 'Drone Imagery');
        INSERT INTO metadata (name, value) VALUES ('minzoom', '16');
        INSERT INTO metadata (name, value) VALUES ('maxzoom', '22');
        INSERT INTO metadata (name, value) VALUES ('bounds', '95.0,-11.0,141.0,6.0');
        INSERT INTO metadata (name, value) VALUES ('center', '105.75,-2.75,18');
        INSERT INTO metadata (name, value) VALUES ('json', '{\"bounds\":[95.0,-11.0,141.0,6.0],\"center\":[105.75,-2.75,18],\"minzoom\":16,\"maxzoom\":22}');
    "
    echo "✓ New glmap.mbtiles initialized (DRONE ONLY - zoom 16-22)"
    log_success "New glmap.mbtiles created"
else
    log_info "Existing glmap.mbtiles found: $GLMAP_FILE"
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
log_info "=== Step 2: Merging Drone Imagery Files ==="
echo ""
echo "=== Step 2: Merging Drone Imagery Files ==="

# Find new files to merge
log_info "Scanning for new files to merge..."
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

log_info "Found: $NEW_COUNT new files, $SKIPPED_COUNT already merged"
echo "Found: $NEW_COUNT new files, $SKIPPED_COUNT already merged"

# Merge only new files
if [ "$NEW_COUNT" -gt 0 ]; then
    log_info "Merging $NEW_COUNT new files into glmap..."
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
    log_success "Incremental merge complete (Total tiles: $total)"
    echo "✓ Incremental merge complete (Total tiles: $total)"
else
    log_info "No new files to merge"
    echo "✓ No new files to merge"
fi

# Step 3: Generate config.json
log_info "=== Step 3: Generating Config ==="
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
SKIPPED_INVALID=0
echo "Scanning individual mbtiles files for config..."
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    
    filename=$(basename "$mbtiles_file")
    basename_only=$(basename "$mbtiles_file" .mbtiles)
    
    # Skip special files
    if [ "$filename" = "glmap.mbtiles" ] || [ "$filename" = "grid_layer.mbtiles" ]; then
        continue
    fi
    
    # Skip trails
    case "$filename" in
        *_trails*) 
            echo "  Skipping (trails): $filename"
            continue 
            ;;
    esac
    
    # Validate
    if is_valid_mbtiles "$mbtiles_file"; then
        echo "," >> "$TEMP_CONFIG"
        echo "    \"$basename_only\": {" >> "$TEMP_CONFIG"
        echo "      \"mbtiles\": \"data/$filename\"" >> "$TEMP_CONFIG"
        echo "    }" >> "$TEMP_CONFIG"
        echo "  Added: $filename"
        INDIVIDUAL_COUNT=$((INDIVIDUAL_COUNT + 1))
    else
        echo "  Skipping (invalid): $filename"
        SKIPPED_INVALID=$((SKIPPED_INVALID + 1))
    fi
done

echo "✓ Added $INDIVIDUAL_COUNT individual files to config"
if [ $SKIPPED_INVALID -gt 0 ]; then
    echo "⚠ Skipped $SKIPPED_INVALID invalid files"
fi

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

# Step 4: Restart container (before PMTiles generation)
log_info "=== Step 4: Restarting Tileserver Container ==="
echo ""
echo "=== Step 4: Restarting Tileserver Container ==="
if command -v docker >/dev/null 2>&1; then
    echo "Restarting tileserver container..."
    if docker restart tileserver-zurich; then
        echo "✓ Container restarted successfully"
        echo "✓ New tiles are now available via XYZ URLs"
    else
        echo "✗ Restart failed"
    fi
else
    echo "⚠ Docker not available - please restart container manually"
fi

# # Step 5: Generate PMTiles from glmap.mbtiles
# echo ""
# echo "=== Step 5: Generating PMTiles ==="

# PMTILES_FILE="$DATA_DIR/glmap.pmtiles"

# if command -v pmtiles >/dev/null 2>&1; then
#     echo "Converting glmap.mbtiles to PMTiles format..."
    
#     # Remove old pmtiles if exists
#     rm -f "$PMTILES_FILE"
    
#     # Convert mbtiles to pmtiles
#     pmtiles convert "$GLMAP_FILE" "$PMTILES_FILE"
    
#     if [ -f "$PMTILES_FILE" ]; then
#         pmtiles_size=$(du -h "$PMTILES_FILE" | cut -f1)
#         echo "✓ PMTiles generated: $PMTILES_FILE ($pmtiles_size)"
#     else
#         echo "✗ Failed to generate PMTiles"
#     fi
# else
#     echo "⚠ pmtiles command not found. Installing..."
    
#     # Detect OS and architecture
#     OS=$(uname -s | tr '[:upper:]' '[:lower:]')
#     ARCH=$(uname -m)
    
#     case "$ARCH" in
#         x86_64) ARCH="x86_64" ;;
#         aarch64|arm64) ARCH="arm64" ;;
#         *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
#     esac
    
#     # Download and install pmtiles
#     PMTILES_VERSION="1.28.2"
#     PMTILES_URL="https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_${OS}_${ARCH}.tar.gz"
#     PMTILES_INSTALL_DIR="/usr/local/bin"
    
#     echo "  Downloading pmtiles v${PMTILES_VERSION} for ${OS}/${ARCH}..."
    
#     if command -v curl >/dev/null 2>&1; then
#         curl -L "$PMTILES_URL" -o /tmp/pmtiles.tar.gz
#     elif command -v wget >/dev/null 2>&1; then
#         wget "$PMTILES_URL" -O /tmp/pmtiles.tar.gz
#     else
#         echo "✗ Neither curl nor wget found. Install with:"
#         echo "  apt-get install curl"
#         exit 1
#     fi
    
#     # Extract and install
#     echo "  Installing pmtiles to $PMTILES_INSTALL_DIR..."
#     tar -xzf /tmp/pmtiles.tar.gz -C /tmp/
    
#     if [ -w "$PMTILES_INSTALL_DIR" ]; then
#         mv /tmp/pmtiles "$PMTILES_INSTALL_DIR/"
#         chmod +x "$PMTILES_INSTALL_DIR/pmtiles"
#     else
#         echo "  Need sudo for installation..."
#         sudo mv /tmp/pmtiles "$PMTILES_INSTALL_DIR/"
#         sudo chmod +x "$PMTILES_INSTALL_DIR/pmtiles"
#     fi
    
#     rm -f /tmp/pmtiles.tar.gz
    
#     # Verify installation
#     if command -v pmtiles >/dev/null 2>&1; then
#         echo "  ✓ pmtiles installed successfully"
        
#         # Now convert
#         echo "  Converting glmap.mbtiles to PMTiles..."
#         pmtiles convert "$GLMAP_FILE" "$PMTILES_FILE"
        
#         if [ -f "$PMTILES_FILE" ]; then
#             pmtiles_size=$(du -h "$PMTILES_FILE" | cut -f1)
#             echo "  ✓ PMTiles generated: $PMTILES_FILE ($pmtiles_size)"
#         fi
#     else
#         echo "✗ Failed to install pmtiles"
#         echo "  Manual installation:"
#         echo "  1. Download from: https://github.com/protomaps/go-pmtiles/releases"
#         echo "  2. Extract and move to /usr/local/bin/"
#     fi
# fi

# # Step 6: Upload PMTiles to MinIO S3
# if [ -f "$PMTILES_FILE" ]; then
#     echo ""
#     echo "=== Step 6: Uploading to MinIO S3 ==="
    
#     # S3 Configuration
#     S3_HOST="${S3_HOST:-http://52.76.171.132:9005}"
#     S3_BUCKET="${S3_BUCKET:-idpm}"
#     S3_PATH="${S3_PATH:-layers}"
#     S3_ACCESS_KEY="${S3_ACCESS_KEY:-eY7VQA55gjPQu1CGv540}"
#     S3_SECRET_KEY="${S3_SECRET_KEY:-u6feeKC1s8ttqU1PLLILrfyqdv79UOvBkzpWhIIn}"
#     S3_HOSTNAME="${S3_HOSTNAME:-https://api-minio.ptnaghayasha.com}"
    
#     PMTILES_FILENAME=$(basename "$PMTILES_FILE")
#     S3_DEST="s3://$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME"
    
#     echo "Uploading to MinIO..."
#     echo "  Source: $PMTILES_FILE"
#     echo "  Destination: $S3_DEST"
#     echo "  Host: $S3_HOST"
#     echo ""
    
#     # Prefer mc (MinIO Client) over aws cli
#     if command -v mc >/dev/null 2>&1; then
#         # Configure mc alias
#         MC_ALIAS="glmap_minio"
        
#         echo "Configuring MinIO client..."
#         mc alias set "$MC_ALIAS" "$S3_HOST" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" --insecure >/dev/null 2>&1
        
#         # Check if file exists
#         echo "Checking if file exists in MinIO..."
#         if mc stat "$MC_ALIAS/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME" --insecure >/dev/null 2>&1; then
#             echo "⚠ File already exists - will be replaced"
#         else
#             echo "✓ New file - will be uploaded"
#         fi
        
#         # Upload with progress
#         echo "Uploading file (this may take a while)..."
#         if mc cp "$PMTILES_FILE" "$MC_ALIAS/$S3_BUCKET/$S3_PATH/" --insecure; then
#             echo ""
#             echo "✓ Upload successful!"
#             echo ""
#             echo "📍 PMTiles URLs:"
#             echo "   Internal: $S3_HOST/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME"
#             echo "   Public:   $S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME"
#             echo ""
            
#             # Set public policy
#             echo "Setting public read access..."
#             mc anonymous set download "$MC_ALIAS/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME" --insecure 2>/dev/null && \
#                 echo "✓ File set to public" || \
#                 echo "  (Public policy not set - file may still be accessible via presigned URL)"
#         else
#             echo "✗ Upload failed"
#         fi
    
#     # Fallback to AWS CLI
#     elif command -v aws >/dev/null 2>&1; then
#         # Configure AWS CLI for MinIO
#         export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
#         export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
        
#         # Check if file exists
#         echo "Checking if file exists in MinIO..."
#         if aws s3 ls "$S3_DEST" --endpoint-url "$S3_HOST" --no-verify-ssl >/dev/null 2>&1; then
#             echo "⚠ File already exists - will be replaced"
#         else
#             echo "✓ New file - will be uploaded"
#         fi
        
#         # Upload with simple method (not multipart for compatibility)
#         echo "  Uploading file (overwrite if exists, may take a while)..."
        
#         if aws s3 cp "$PMTILES_FILE" "$S3_DEST" \
#             --endpoint-url "$S3_HOST" \
#             --no-verify-ssl; then
            
#             echo "✓ Upload successful!"
#             echo ""
#             echo "📍 PMTiles URL:"
#             echo "   $S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME"
#             echo ""
            
#             # Make public (optional)
#             echo "Setting public read access..."
#             aws s3api put-object-acl \
#                 --bucket "$S3_BUCKET" \
#                 --key "$S3_PATH/$PMTILES_FILENAME" \
#                 --acl public-read \
#                 --endpoint-url "$S3_HOST" \
#                 --no-verify-ssl 2>/dev/null && echo "✓ File set to public" || echo "  (Public ACL not set - may require permissions)"
#         else
#             echo "✗ Upload failed"
#             echo ""
#             echo "Alternative: Manual upload using mc (MinIO Client)"
#             echo "  Install mc first, then run:"
#             echo "  mc alias set myminio $S3_HOST $S3_ACCESS_KEY $S3_SECRET_KEY"
#             echo "  mc cp $PMTILES_FILE myminio/$S3_BUCKET/$S3_PATH/"
#         fi
        
#         # Cleanup environment
#         unset AWS_ACCESS_KEY_ID
#         unset AWS_SECRET_ACCESS_KEY
    
#     # No client installed - install mc
#     else
#         echo "⚠ No S3 client found (mc or awscli). Installing mc..."
        
#         # Detect OS and architecture
#         OS=$(uname -s | tr '[:upper:]' '[:lower:]')
#         ARCH=$(uname -m)
        
#         case "$ARCH" in
#             x86_64) ARCH="amd64" ;;
#             aarch64|arm64) ARCH="arm64" ;;
#             *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
#         esac
        
#         # Download and install mc
#         MC_URL="https://dl.min.io/client/mc/release/${OS}-${ARCH}/mc"
#         MC_INSTALL_DIR="/usr/local/bin"
        
#         echo "  Downloading MinIO Client for ${OS}/${ARCH}..."
        
#         if command -v curl >/dev/null 2>&1; then
#             curl -L "$MC_URL" -o /tmp/mc
#         elif command -v wget >/dev/null 2>&1; then
#             wget "$MC_URL" -O /tmp/mc
#         else
#             echo "✗ Neither curl nor wget found. Install with:"
#             echo "  apt-get install curl"
#             exit 1
#         fi
        
#         # Install mc
#         echo "  Installing mc to $MC_INSTALL_DIR..."
#         chmod +x /tmp/mc
        
#         if [ -w "$MC_INSTALL_DIR" ]; then
#             mv /tmp/mc "$MC_INSTALL_DIR/"
#         else
#             echo "  Need sudo for installation..."
#             sudo mv /tmp/mc "$MC_INSTALL_DIR/"
#         fi
        
#         # Verify installation
#         if command -v mc >/dev/null 2>&1; then
#             echo "  ✓ mc installed successfully"
            
#             # Configure and upload
#             MC_ALIAS="glmap_minio"
#             echo "  Configuring MinIO client..."
#             mc alias set "$MC_ALIAS" "$S3_HOST" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" --insecure
            
#             # Check if file exists
#             echo "  Checking if file exists in MinIO..."
#             if mc stat "$MC_ALIAS/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME" --insecure >/dev/null 2>&1; then
#                 echo "  ⚠ File already exists - will be replaced"
#             else
#                 echo "  ✓ New file - will be uploaded"
#             fi
            
#             echo "  Uploading file (overwrite if exists)..."
#             if mc cp "$PMTILES_FILE" "$MC_ALIAS/$S3_BUCKET/$S3_PATH/" --insecure; then
#                 echo ""
#                 echo "✓ Upload successful!"
#                 echo ""
#                 echo "📍 PMTiles URLs:"
#                 echo "   Internal: $S3_HOST/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME"
#                 echo "   Public:   $S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME"
                
#                 # Set public policy
#                 mc anonymous set download "$MC_ALIAS/$S3_BUCKET/$S3_PATH/$PMTILES_FILENAME" --insecure 2>/dev/null
#             else
#                 echo "✗ Upload failed"
#             fi
#         else
#             echo "✗ Failed to install mc"
#             echo "  Manual installation:"
#             echo "  wget https://dl.min.io/client/mc/release/linux-amd64/mc"
#             echo "  chmod +x mc"
#             echo "  sudo mv mc /usr/local/bin/"
#         fi
#     fi
# fi

# Step 7: Database update (optional)
log_info "=== Step 7: Updating PostgreSQL Database ==="
echo ""
echo "=== Step 7: Updating PostgreSQL Database ==="

# Database credentials
DBHOST="172.26.11.153"
DBUSER="pg"
DBPASS="~nagha2025yasha@~"
DBNAME="postgres"
DBPORT="5432"

log_info "Database: $DBUSER@$DBHOST:$DBPORT/$DBNAME"
echo "Database: $DBUSER@$DBHOST:$DBPORT/$DBNAME"

# Check if database update should be skipped
if [ "$SKIP_DB_UPDATE" = "true" ]; then
    log_info "Database update skipped (SKIP_DB_UPDATE=true)"
    echo "Database update skipped (SKIP_DB_UPDATE=true)"
else
    # Check dependencies
    DB_UPDATE_AVAILABLE="true"
    
    # Install psycopg2 if needed
    if ! python3 -c "import psycopg2" 2>/dev/null; then
        echo "Installing psycopg2-binary..."
        if pip3 install psycopg2-binary >/dev/null 2>&1; then
            echo "✓ psycopg2-binary installed"
        else
            echo "✗ Could not install psycopg2, skipping database update"
            DB_UPDATE_AVAILABLE="false"
        fi
    else
        echo "✓ psycopg2 already available"
    fi

    # Install bc for calculations if needed  
    if ! command -v bc >/dev/null 2>&1; then
        echo "Installing bc for coordinate calculations..."
        if apt-get update -qq && apt-get install -y bc >/dev/null 2>&1; then
            echo "✓ bc installed"
        else
            echo "⚠ Could not install bc, using awk fallback"
        fi
    fi

    # Function to extract coordinates from mbtiles
    extract_coordinates() {
        local mbtiles_file="$1"
        
        # Try to get bounds from metadata
        local bounds=$(sqlite3 "$mbtiles_file" "SELECT value FROM metadata WHERE name='bounds';" 2>/dev/null || echo "")
        
        if [ -n "$bounds" ] && [ "$bounds" != "" ]; then
            # Parse bounds: west,south,east,north
            local west=$(echo "$bounds" | cut -d',' -f1)
            local south=$(echo "$bounds" | cut -d',' -f2) 
            local east=$(echo "$bounds" | cut -d',' -f3)
            local north=$(echo "$bounds" | cut -d',' -f4)
            
            # Calculate center using bc or fallback to awk
            if command -v bc >/dev/null 2>&1; then
                local lat=$(echo "scale=6; ($south + $north) / 2" | bc 2>/dev/null || echo "-0.469")
                local lon=$(echo "scale=6; ($west + $east) / 2" | bc 2>/dev/null || echo "117.172")
            else
                # Fallback using awk
                local lat=$(awk "BEGIN {printf \"%.6f\", ($south + $north) / 2}")
                local lon=$(awk "BEGIN {printf \"%.6f\", ($west + $east) / 2}")
            fi
            
            echo "$lat,$lon"
            return 0
        fi
        
        # Try center metadata
        local center=$(sqlite3 "$mbtiles_file" "SELECT value FROM metadata WHERE name='center';" 2>/dev/null || echo "")
        
        if [ -n "$center" ] && [ "$center" != "" ]; then
            # Center format: lon,lat,zoom
            local lon=$(echo "$center" | cut -d',' -f1)
            local lat=$(echo "$center" | cut -d',' -f2)
            echo "$lat,$lon"
            return 0
        fi
        
        # Default coordinates based on your sample data (Indonesia region)
        echo "-0.469,117.172"
    }

    # Function to update database
    update_database() {
        local filename="$1"
        local latitude="$2"
        local longitude="$3"
        
        echo "Updating: $filename -> lat=$latitude, lon=$longitude"
        
        python3 << EOF
import psycopg2
import sys

try:
    conn = psycopg2.connect(
        host='$DBHOST',
        port=$DBPORT,
        user='$DBUSER',
        password='$DBPASS',
        database='$DBNAME'
    )
    
    cur = conn.cursor()
    
    # Check existing records
    cur.execute("""
        SELECT id, title, latitude, longitude, storage_path 
        FROM geoportal.pmn_drone_imagery 
        WHERE storage_path LIKE %s
    """, ('%$filename.mbtiles%',))
    
    records = cur.fetchall()
    
    if records:
        for record in records:
            old_lat = record[2] or 'NULL'
            old_lon = record[3] or 'NULL'
            print(f"  Found: {record[0]} - {record[1]} (was: {old_lat}, {old_lon})")
        
        # Update coordinates
        cur.execute("""
            UPDATE geoportal.pmn_drone_imagery 
            SET latitude = %s, longitude = %s, updated_at = NOW()
            WHERE storage_path LIKE %s
        """, ($latitude, $longitude, '%$filename.mbtiles%'))
        
        rows = cur.rowcount
        conn.commit()
        print(f"  ✓ Updated {rows} record(s)")
        
    else:
        print(f"  ⚠ No matching records found for $filename")
    
    cur.close()
    conn.close()

except Exception as e:
    print(f"  ✗ Error: {e}")
    sys.exit(1)
EOF
    }

    # Process all valid files that were processed
    if [ "$DB_UPDATE_AVAILABLE" = "true" ]; then
        echo ""
        echo "Processing coordinates for database update..."
        
        # Process only newly merged files
        if [ "$NEW_COUNT" -gt 0 ] && [ -n "$NEW_FILES" ]; then
            echo "Updating coordinates for $NEW_COUNT newly merged files..."
            
            for mbtiles_file in $NEW_FILES; do
                [ -f "$mbtiles_file" ] || continue
                
                filename=$(basename "$mbtiles_file" .mbtiles)
                echo ""
                echo "Processing: $filename"
                
                # Extract coordinates
                coords=$(extract_coordinates "$mbtiles_file")
                lat=$(echo "$coords" | cut -d',' -f1)
                lon=$(echo "$coords" | cut -d',' -f2)
                
                echo "  Coordinates: lat=$lat, lon=$lon"
                
                # Update database
                update_database "$filename" "$lat" "$lon"
            done
        else
            echo "No new files to update in database"
        fi
        
        # Also update glmap coordinates
        if [ -f "$GLMAP_FILE" ]; then
            echo ""
            echo "Processing: glmap"
            coords=$(extract_coordinates "$GLMAP_FILE")
            lat=$(echo "$coords" | cut -d',' -f1)
            lon=$(echo "$coords" | cut -d',' -f2)
            echo "  Coordinates: lat=$lat, lon=$lon"
            update_database "glmap" "$lat" "$lon"
        fi
        
        echo ""
        echo "✓ Database coordinate update completed"
    else
        echo "Database update skipped (dependencies not available)"
    fi
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

if [ -f "$PMTILES_FILE" ]; then
    pmtiles_size=$(du -h "$PMTILES_FILE" | cut -f1)
    echo "✓ glmap.pmtiles (Cloud-Optimized):"
    echo "  - Format: PMTiles"
    echo "  - Size: $pmtiles_size"
    echo "  - Location: $PMTILES_FILE"
    if [ -n "$S3_HOSTNAME" ]; then
        echo "  - S3 URL: $S3_HOSTNAME/$S3_BUCKET/$S3_PATH/glmap.pmtiles"
    fi
    echo ""
fi

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