#!/bin/bash

# Script simple untuk generate config yang pasti bekerja

set -e

DATA_DIR="/app/data"
CONFIG_FILE="/app/config.json"
TEMP_CONFIG="/tmp/simple_config.json"

echo "=== Simple Config Generation ==="

# Validasi function
is_valid_mbtiles() {
    local file="$1"
    
    [ -r "$file" ] && \
    sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table' AND name='tiles';" 2>/dev/null | grep -q "tiles" && \
    sqlite3 "$file" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok" && \
    [ "$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")" -gt 0 ]
}

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
    "glmap": {
      "mbtiles": "data/glmap.mbtiles"
    }
EOF

# Scan dan tambah file valid
ADDED_COUNT=0

if [ -d "$DATA_DIR" ]; then
    for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
        if [ -f "$mbtiles_file" ] && [ "$(basename "$mbtiles_file")" != "glmap.mbtiles" ]; then
            echo "Testing: $(basename "$mbtiles_file")"
            
            if is_valid_mbtiles "$mbtiles_file"; then
                filename=$(basename "$mbtiles_file" .mbtiles)
                echo "  ✓ Adding: $filename"
                
                echo ',' >> "$TEMP_CONFIG"
                echo "    \"$filename\": {" >> "$TEMP_CONFIG"
                echo "      \"mbtiles\": \"data/$(basename "$mbtiles_file")\"" >> "$TEMP_CONFIG"
                echo "    }" >> "$TEMP_CONFIG"
                
                ADDED_COUNT=$((ADDED_COUNT + 1))
            else
                echo "  ✗ Skipping: $(basename "$mbtiles_file") (invalid/corrupt)"
            fi
        fi
    done
fi

# Close config
cat >> "$TEMP_CONFIG" << 'EOF'
  }
}
EOF

echo ""
echo "Added $ADDED_COUNT individual .mbtiles files"

# Validate
if python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "✓ JSON is valid"
    
    # Show preview
    echo ""
    echo "=== Config Preview ==="
    cat "$TEMP_CONFIG"
    echo "=== End Preview ==="
    
    # Stop processes
    pkill -f "tileserver-gl" || true
    sleep 1
    
    # Apply
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
    rm -f "$TEMP_CONFIG"
    
    echo ""
    echo "✓ Config applied successfully!"
    echo "Total datasets: $((ADDED_COUNT + 1)) (including glmap)"
    
else
    echo "✗ JSON validation failed!"
    cat "$TEMP_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

echo "=== Simple Config Generation Complete ==="