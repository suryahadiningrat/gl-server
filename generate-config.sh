#!/bin/bash

# Script untuk membuat config.json untuk tileserver-gl
# dan menggabungkan semua file .mbtiles menjadi glmap.mbtiles

set -e

DATA_DIR="/app/data/tileserver"
CONFIG_FILE="/app/config.json"
STYLE_FILE="/app/styles/default/style.json"
GLMAP_FILE="/app/data/tileserver/glmap.mbtiles"

echo "=== Generate Config Script Started ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"

# Buat direktori jika belum ada
mkdir -p /app/styles/default
mkdir -p /app/data

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

MBTILES_FILES=$(find "$DATA_DIR" -name "*.mbtiles" 2>/dev/null || true)
MBTILES_COUNT=$(echo "$MBTILES_FILES" | grep -c . || echo "0")

echo "Found $MBTILES_COUNT .mbtiles files"

# Hapus glmap.mbtiles lama jika ada
if [ -f "$GLMAP_FILE" ]; then
    echo "Removing existing glmap.mbtiles..."
    rm -f "$GLMAP_FILE"
fi

# Gabungkan semua file .mbtiles menjadi glmap.mbtiles jika ada file
if [ "$MBTILES_COUNT" -gt 0 ]; then
    echo "Merging .mbtiles files into glmap.mbtiles..."
    
    # Buat database glmap.mbtiles baru
    sqlite3 "$GLMAP_FILE" "CREATE TABLE IF NOT EXISTS metadata (name text, value text);"
    sqlite3 "$GLMAP_FILE" "CREATE TABLE IF NOT EXISTS tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);"
    
    # Set metadata untuk glmap
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('name', 'GL Map');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('type', 'baselayer');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('version', '1.0.0');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('description', 'Merged tiles from multiple sources');"
    sqlite3 "$GLMAP_FILE" "INSERT OR REPLACE INTO metadata (name, value) VALUES ('format', 'jpg');"
    
    # Gabungkan tiles dari semua file .mbtiles
    for mbtiles_file in $MBTILES_FILES; do
        if [ -f "$mbtiles_file" ]; then
            echo "Merging: $(basename "$mbtiles_file")"
            
            # Cek apakah file mbtiles valid dan memiliki tabel tiles
            if sqlite3 "$mbtiles_file" "SELECT name FROM sqlite_master WHERE type='table' AND name='tiles';" | grep -q "tiles"; then
                # Cek apakah tabel tiles memiliki data
                tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
                if [ "$tile_count" -gt 0 ]; then
                    echo "  - Found $tile_count tiles, merging..."
                    # Gunakan satu perintah sqlite3 untuk attach, insert, dan detach
                    sqlite3 "$GLMAP_FILE" "
                        ATTACH DATABASE '$mbtiles_file' AS source;
                        INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
                        DETACH DATABASE source;
                    " 2>/dev/null || {
                        echo "  - Warning: Failed to merge tiles from $(basename "$mbtiles_file")"
                    }
                else
                    echo "  - Warning: No tiles found in $(basename "$mbtiles_file")"
                fi
            else
                echo "  - Warning: $(basename "$mbtiles_file") is not a valid mbtiles file (missing tiles table)"
            fi
        fi
    done
    
    echo "Successfully merged $(echo "$MBTILES_FILES" | wc -l) files into glmap.mbtiles"
else
    echo "No .mbtiles files found to merge"
fi

# Buat config.json
echo "Generating config.json..."

# Mulai membuat config.json
cat > "$CONFIG_FILE" << 'EOF'
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

# Tambahkan glmap jika file ada
if [ -f "$GLMAP_FILE" ]; then
    echo '    "glmap": {' >> "$CONFIG_FILE"
    echo '      "mbtiles": "data/glmap.mbtiles"' >> "$CONFIG_FILE"
    echo '    }' >> "$CONFIG_FILE"
    
    # Tambahkan koma jika ada file .mbtiles lain
    if [ "$MBTILES_COUNT" -gt 0 ]; then
        echo ',' >> "$CONFIG_FILE"
    fi
fi

# Tambahkan semua file .mbtiles individual
if [ "$MBTILES_COUNT" -gt 0 ]; then
    first=true
    for mbtiles_file in $MBTILES_FILES; do
        if [ -f "$mbtiles_file" ]; then
            filename=$(basename "$mbtiles_file" .mbtiles)
            
            if [ "$first" = false ]; then
                echo ',' >> "$CONFIG_FILE"
            fi
            
            echo "    \"$filename\": {" >> "$CONFIG_FILE"
            echo "      \"mbtiles\": \"data/$(basename "$mbtiles_file")\"" >> "$CONFIG_FILE"
            echo '    }' >> "$CONFIG_FILE"
            
            first=false
        fi
    done
fi

# Tutup config.json
cat >> "$CONFIG_FILE" << 'EOF'
  }
}
EOF

echo "Config.json generated successfully!"

# Tampilkan isi config.json untuk verifikasi
echo "=== Generated config.json content ==="
cat "$CONFIG_FILE"
echo "=== End of config.json ==="

# Restart container tileserver-zurich
echo "Restarting tileserver-zurich container..."
if docker restart tileserver-zurich; then
    echo "Container tileserver-zurich restarted successfully!"
else
    echo "Failed to restart container tileserver-zurich"
    exit 1
fi

echo "=== Generate Config Script Completed ==="