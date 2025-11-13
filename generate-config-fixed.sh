#!/bin/bash

# Script untuk membuat config.json untuk tileserver-gl
# dan menggabungkan semua file .mbtiles menjadi glmap.mbtiles
# Versi yang diperbaiki untuk environment Docker API

set -e

DATA_DIR="/app/data"
CONFIG_FILE="/app/config.json"
STYLE_DIR="/app/styles/default"
STYLE_FILE="/app/styles/default/style.json"
GLMAP_FILE="/app/data/glmap.mbtiles"
TEMP_CONFIG="/tmp/config_temp.json"

echo "=== Generate Config Script Started (Fixed Version) ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"

# Buat direktori jika belum ada
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

# Buat style.json default jika belum ada
if [ ! -f "$STYLE_FILE" ]; then
    echo "Creating default style.json..."
    cat > "$STYLE_FILE" << 'EOF'
{
  "version": 8,
  "name": "Default Style",
  "sources": {
    "glmap": {
      "type": "raster",
      "tiles": ["/data/glmap/{z}/{x}/{y}.png"],
      "tileSize": 256
    }
  },
  "layers": [
    {
      "id": "glmap",
      "type": "raster",
      "source": "glmap"
    }
  ]
}
EOF
    echo "Default style.json created."
fi

# Cek apakah ada file .mbtiles di DATA_DIR
if [ ! -d "$DATA_DIR" ]; then
    echo "Warning: Data directory $DATA_DIR does not exist"
    mkdir -p "$DATA_DIR"
fi

# Fungsi untuk validasi file mbtiles
validate_mbtiles() {
    local file="$1"
    
    # Cek apakah file readable
    if [ ! -r "$file" ]; then
        echo "  - Warning: Cannot read file $(basename "$file")"
        return 1
    fi
    
    # Cek apakah file adalah database sqlite yang valid
    if ! sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table' AND name='tiles';" 2>/dev/null | grep -q "tiles"; then
        echo "  - Warning: $(basename "$file") is not a valid mbtiles file (missing tiles table)"
        return 1
    fi
    
    # Cek apakah database corrupt
    if ! sqlite3 "$file" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
        echo "  - Warning: $(basename "$file") database is corrupted"
        return 1
    fi
    
    return 0
}

# Scan file .mbtiles yang valid
echo "Scanning for valid .mbtiles files..."
VALID_MBTILES=""
VALID_COUNT=0

if [ -d "$DATA_DIR" ]; then
    echo "Data directory exists: $DATA_DIR"
    echo "Files in data directory:"
    ls -la "$DATA_DIR"/*.mbtiles 2>/dev/null || echo "No .mbtiles files found"
    
    for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
        if [ -f "$mbtiles_file" ] && [ "$(basename "$mbtiles_file")" != "glmap.mbtiles" ]; then
            echo "Checking: $(basename "$mbtiles_file")"
            if validate_mbtiles "$mbtiles_file"; then
                tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
                if [ "$tile_count" -gt 0 ]; then
                    echo "  - Valid: $tile_count tiles found"
                    VALID_MBTILES="$VALID_MBTILES $mbtiles_file"
                    VALID_COUNT=$((VALID_COUNT + 1))
                    echo "  - Added to valid list: $mbtiles_file"
                else
                    echo "  - Warning: No tiles found in $(basename "$mbtiles_file")"
                fi
            fi
        fi
    done
else
    echo "Warning: Data directory $DATA_DIR does not exist!"
fi

echo "Found $VALID_COUNT valid .mbtiles files"
echo "Valid files list: $VALID_MBTILES"

# Hapus glmap.mbtiles lama jika ada
if [ -f "$GLMAP_FILE" ]; then
    echo "Removing existing glmap.mbtiles..."
    rm -f "$GLMAP_FILE"
fi

# Gabungkan semua file .mbtiles yang valid menjadi glmap.mbtiles
if [ "$VALID_COUNT" -gt 0 ]; then
    echo "Merging valid .mbtiles files into glmap.mbtiles..."
    
    # Buat database glmap.mbtiles baru
    sqlite3 "$GLMAP_FILE" "CREATE TABLE IF NOT EXISTS metadata (name text, value text);"
    sqlite3 "$GLMAP_FILE" "CREATE TABLE IF NOT EXISTS tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);"
    sqlite3 "$GLMAP_FILE" "CREATE UNIQUE INDEX IF NOT EXISTS tile_index ON tiles (zoom_level, tile_column, tile_row);"
    
    # Set metadata untuk glmap
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('name', 'GL Map');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('type', 'baselayer');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('version', '1.0.0');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('description', 'Merged tiles from multiple sources');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('format', 'jpg');"
    
    # Gabungkan tiles dari semua file .mbtiles yang valid
    for mbtiles_file in $VALID_MBTILES; do
        if [ -f "$mbtiles_file" ]; then
            echo "Merging: $(basename "$mbtiles_file")"
            
            # Gunakan INSERT OR IGNORE untuk menghindari duplikasi
            if sqlite3 "$GLMAP_FILE" "
                ATTACH DATABASE '$mbtiles_file' AS source;
                INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
                DETACH DATABASE source;
            " 2>/dev/null; then
                echo "  - Successfully merged $(basename "$mbtiles_file")"
            else
                echo "  - Warning: Failed to merge tiles from $(basename "$mbtiles_file")"
            fi
        fi
    done
    
    # Hitung total tiles setelah merge
    total_tiles=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    echo "Successfully merged $VALID_COUNT files into glmap.mbtiles (Total tiles: $total_tiles)"
else
    echo "No valid .mbtiles files found to merge"
    # Buat file glmap.mbtiles kosong untuk mencegah error
    sqlite3 "$GLMAP_FILE" "CREATE TABLE IF NOT EXISTS metadata (name text, value text);"
    sqlite3 "$GLMAP_FILE" "CREATE TABLE IF NOT EXISTS tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('name', 'Empty GL Map');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('type', 'baselayer');"
fi

# Buat config.json dengan format yang benar
echo "Generating config.json..."

# Buat config ke temporary file terlebih dahulu
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

# Collect valid files first
echo "Adding individual .mbtiles files to config..."
VALID_FILES_ARRAY=()

# Scan dan collect valid files
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    if [ -f "$mbtiles_file" ]; then
        filename=$(basename "$mbtiles_file")
        basename_only=$(basename "$mbtiles_file" .mbtiles)
        
        # Skip glmap.mbtiles dan file yang mengandung "_trails"
        if [ "$filename" = "glmap.mbtiles" ]; then
            echo "  - Skipping: $filename (glmap)"
            continue
        fi
        
        if [[ "$filename" == *"_trails"* ]]; then
            echo "  - Skipping: $filename (trails file - known corrupt)"
            continue
        fi
        
        echo "Checking: $filename"
        
        # Validasi file
        if validate_mbtiles "$mbtiles_file" >/dev/null 2>&1; then
            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            if [ "$tile_count" -gt 0 ]; then
                echo "  - Valid: $basename_only ($tile_count tiles)"
                VALID_FILES_ARRAY+=("$mbtiles_file")
            else
                echo "  - Skipping: $basename_only (no tiles)"
            fi
        else
            echo "  - Skipping: $basename_only (invalid/corrupt)"
        fi
    fi
done

# Add glmap first
echo '    "glmap": {' >> "$TEMP_CONFIG"
echo '      "mbtiles": "data/glmap.mbtiles"' >> "$TEMP_CONFIG"

# Add individual files with proper comma placement
ADDED_COUNT=0
for mbtiles_file in "${VALID_FILES_ARRAY[@]}"; do
    filename=$(basename "$mbtiles_file")
    basename_only=$(basename "$mbtiles_file" .mbtiles)
    
    echo "    }," >> "$TEMP_CONFIG"
    echo "    \"$basename_only\": {" >> "$TEMP_CONFIG"
    echo "      \"mbtiles\": \"data/$filename\"" >> "$TEMP_CONFIG"
    
    ADDED_COUNT=$((ADDED_COUNT + 1))
    echo "  - Added: $basename_only"
done

# Close last entry without comma
echo "    }" >> "$TEMP_CONFIG"

echo "Added $ADDED_COUNT individual files to config."

# Tutup config.json
cat >> "$TEMP_CONFIG" << 'EOF'
  }
}
EOF

# Validasi JSON sebelum mengganti file asli
if python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "JSON validation passed"
    
    # Stop tileserver-gl process jika ada yang berjalan untuk menghindari "device busy"
    echo "Stopping any running tileserver-gl processes..."
    pkill -f "tileserver-gl" || true
    sleep 2
    
    # Copy config yang sudah valid
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
    rm -f "$TEMP_CONFIG"
    
    echo "Config.json generated successfully!"
else
    echo "Error: Generated JSON is invalid!"
    echo "Content of temporary config:"
    cat "$TEMP_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# Tampilkan isi config.json untuk verifikasi
echo "=== Generated config.json content ==="
cat "$CONFIG_FILE"
echo ""
echo "=== End of config.json ==="

# Restart container tileserver-zurich via Docker API (jika container name diketahui)
CONTAINER_NAME="tileserver-zurich"
echo "Attempting to restart $CONTAINER_NAME container via Docker API..."

# Cek apakah docker command tersedia
if command -v docker > /dev/null 2>&1; then
    # Cek apakah container exists
    if docker ps -a --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
        if docker restart "$CONTAINER_NAME"; then
            echo "Container $CONTAINER_NAME restarted successfully!"
        else
            echo "Failed to restart container $CONTAINER_NAME"
            echo "Please restart the container manually"
        fi
    else
        echo "Container $CONTAINER_NAME not found"
        echo "Please restart your tileserver container manually"
    fi
else
    echo "Docker command not available in this environment"
    echo "Please restart your tileserver container manually using your Docker API"
fi

# Cleanup dan summary
echo ""
echo "=== Summary ==="
echo "Individual files added to config: $ADDED_COUNT"
echo "Total tiles in glmap.mbtiles: $(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")"
echo "Config file: $CONFIG_FILE"
echo "Style file: $STYLE_FILE"
echo ""

# Tampilkan breakdown files
echo "=== File Breakdown ==="
echo "✓ Valid files (added to config):"
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    if [ -f "$mbtiles_file" ]; then
        filename=$(basename "$mbtiles_file")
        
        # Skip glmap dan trails
        if [ "$filename" = "glmap.mbtiles" ] || [[ "$filename" == *"_trails"* ]]; then
            continue
        fi
        
        if validate_mbtiles "$mbtiles_file" >/dev/null 2>&1; then
            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            if [ "$tile_count" -gt 0 ]; then
                echo "  - $filename ($tile_count tiles)"
            fi
        fi
    fi
done

echo ""
echo "✗ Skipped files:"
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    if [ -f "$mbtiles_file" ]; then
        filename=$(basename "$mbtiles_file")
        
        if [ "$filename" = "glmap.mbtiles" ]; then
            echo "  - $filename (merged file)"
        elif [[ "$filename" == *"_trails"* ]]; then
            echo "  - $filename (trails - corrupt)"
        elif ! validate_mbtiles "$mbtiles_file" >/dev/null 2>&1; then
            echo "  - $filename (validation failed)"
        else
            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            if [ "$tile_count" -eq 0 ]; then
                echo "  - $filename (no tiles)"
            fi
        fi
    fi
done

echo "=== Generate Config Script Completed ==="