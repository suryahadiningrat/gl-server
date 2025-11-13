#!/bin/bash

# Debug script untuk melihat apa yang terjadi dengan config generation

set -e

DATA_DIR="/app/data"
CONFIG_FILE="/app/config.json"

echo "=== Debug Config Generation ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"

# Cek direktori data
if [ -d "$DATA_DIR" ]; then
    echo "✓ Data directory exists"
    echo "Files in $DATA_DIR:"
    ls -la "$DATA_DIR"/*.mbtiles 2>/dev/null || echo "No .mbtiles files found"
    echo ""
else
    echo "✗ Data directory does not exist: $DATA_DIR"
    exit 1
fi

# Fungsi validasi
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

# Scan files
echo "=== File Analysis ==="
VALID_FILES=""
INVALID_FILES=""
VALID_COUNT=0

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    if [ -f "$mbtiles_file" ] && [ "$(basename "$mbtiles_file")" != "glmap.mbtiles" ]; then
        echo "Analyzing: $(basename "$mbtiles_file")"
        
        if validate_mbtiles "$mbtiles_file"; then
            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            echo "  ✓ Valid - $tile_count tiles"
            VALID_FILES="$VALID_FILES $mbtiles_file"
            VALID_COUNT=$((VALID_COUNT + 1))
        else
            echo "  ✗ Invalid/Corrupt"
            INVALID_FILES="$INVALID_FILES $mbtiles_file"
        fi
    fi
done

echo ""
echo "=== Summary ==="
echo "Valid files ($VALID_COUNT):"
for file in $VALID_FILES; do
    echo "  - $(basename "$file")"
done

echo ""
echo "Invalid files:"
for file in $INVALID_FILES; do
    echo "  - $(basename "$file")"
done

echo ""
echo "=== Generate Test Config ==="

# Buat config test
TEST_CONFIG="/tmp/test_config.json"

cat > "$TEST_CONFIG" << 'EOF'
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

# Tambahkan file valid
if [ "$VALID_COUNT" -gt 0 ]; then
    for mbtiles_file in $VALID_FILES; do
        if [ -f "$mbtiles_file" ]; then
            filename=$(basename "$mbtiles_file" .mbtiles)
            echo "," >> "$TEST_CONFIG"
            echo "    \"$filename\": {" >> "$TEST_CONFIG"
            echo "      \"mbtiles\": \"data/$(basename "$mbtiles_file")\"" >> "$TEST_CONFIG"
            echo "    }" >> "$TEST_CONFIG"
        fi
    done
fi

cat >> "$TEST_CONFIG" << 'EOF'
  }
}
EOF

echo "Test config generated:"
echo "========================"
cat "$TEST_CONFIG"
echo "========================"

# Validasi JSON
if python3 -m json.tool "$TEST_CONFIG" > /dev/null 2>&1; then
    echo "✓ JSON is valid"
else
    echo "✗ JSON is invalid"
fi

# Copy to actual config if requested
if [ "$1" = "apply" ]; then
    echo "Applying test config to actual config..."
    cp "$TEST_CONFIG" "$CONFIG_FILE"
    echo "✓ Config applied"
fi

rm -f "$TEST_CONFIG"

echo "=== Debug Complete ==="