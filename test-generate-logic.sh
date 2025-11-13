#!/bin/bash

# Test script untuk memvalidasi generate-config-fixed.sh logic
# Simulasi environment server

set -e

# Simulasi environment
DATA_DIR="./data"
CONFIG_FILE="./config-test.json"
TEMP_CONFIG="/tmp/config_temp_test.json"

echo "=== Testing Generate Config Logic ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"

# Validasi function (sama seperti di script asli)
validate_mbtiles() {
    local file="$1"
    
    if [ ! -r "$file" ]; then
        return 1
    fi
    
    if ! sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table' AND name='tiles';" 2>/dev/null | grep -q "tiles"; then
        return 1
    fi
    
    if ! sqlite3 "$file" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
        return 1
    fi
    
    return 0
}

# Buat config header
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

# Tambahkan glmap
echo '    "glmap": {' >> "$TEMP_CONFIG"
echo '      "mbtiles": "data/glmap.mbtiles"' >> "$TEMP_CONFIG"
echo '    }' >> "$TEMP_CONFIG"

# Test logic untuk file individual
ADDED_COUNT=0
echo ""
echo "Processing individual files..."

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
                echo "  ✓ Adding: $basename_only ($tile_count tiles)"
                echo ',' >> "$TEMP_CONFIG"
                echo "    \"$basename_only\": {" >> "$TEMP_CONFIG"
                echo "      \"mbtiles\": \"data/$filename\"" >> "$TEMP_CONFIG"
                echo "    }" >> "$TEMP_CONFIG"
                ADDED_COUNT=$((ADDED_COUNT + 1))
            else
                echo "  - Skipping: $basename_only (no tiles)"
            fi
        else
            echo "  - Skipping: $basename_only (invalid/corrupt)"
        fi
    fi
done

# Close config
cat >> "$TEMP_CONFIG" << 'EOF'
  }
}
EOF

echo ""
echo "Added $ADDED_COUNT individual files to test config."

# Validate JSON
if python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "✓ JSON validation passed"
    
    # Show result
    echo ""
    echo "=== Generated Test Config ==="
    cat "$TEMP_CONFIG"
    echo "=== End Test Config ==="
    
    # Copy to test file
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
    echo ""
    echo "✓ Test config saved to: $CONFIG_FILE"
else
    echo "✗ JSON validation failed!"
    echo "Content:"
    cat "$TEMP_CONFIG"
fi

# Cleanup
rm -f "$TEMP_CONFIG"

echo ""
echo "=== Test Summary ==="
echo "Individual files that should be added: $ADDED_COUNT"
echo ""
echo "Expected files:"
ls -1 "$DATA_DIR"/*.mbtiles | grep -v glmap.mbtiles | grep -v "_trails" | while read file; do
    if validate_mbtiles "$file" >/dev/null 2>&1; then
        echo "  - $(basename "$file" .mbtiles)"
    fi
done

echo ""
echo "=== Test Complete ==="