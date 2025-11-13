#!/bin/bash

# Script untuk memperbaiki config.json yang sudah corrupt
# dan membuat config.json yang valid

set -e

CONFIG_FILE="/app/config.json"
BACKUP_CONFIG="/app/config.json.backup"
TEMP_CONFIG="/tmp/config_fixed.json"

echo "=== Fix Config Script Started ==="

# Backup config lama jika ada
if [ -f "$CONFIG_FILE" ]; then
    echo "Creating backup of existing config.json..."
    cp "$CONFIG_FILE" "$BACKUP_CONFIG"
fi

# Buat config.json yang benar secara manual
echo "Creating corrected config.json..."

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
    },
    "1761574836479_54098_32852": {
      "mbtiles": "data/1761574836479_54098_32852.mbtiles"
    },
    "1761575194145_54097_32853": {
      "mbtiles": "data/1761575194145_54097_32853.mbtiles"
    },
    "1761575459307_x54097_32853": {
      "mbtiles": "data/1761575459307_x54097_32853.mbtiles"
    },
    "1761575406079_54097_32853": {
      "mbtiles": "data/1761575406079_54097_32853.mbtiles"
    },
    "1762157419255_1761574836479_54098_32852": {
      "mbtiles": "data/1762157419255_1761574836479_54098_32852.mbtiles"
    },
    "1761575908071_Y54097_32853": {
      "mbtiles": "data/1761575908071_Y54097_32853.mbtiles"
    }
  }
}
EOF

# Validasi JSON
if python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "JSON validation: PASSED"
    
    # Stop any running tileserver process
    echo "Stopping tileserver-gl processes..."
    pkill -f "tileserver-gl" || true
    sleep 2
    
    # Replace config file
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
    rm -f "$TEMP_CONFIG"
    
    echo "Config.json fixed successfully!"
else
    echo "Error: Generated JSON is still invalid!"
    cat "$TEMP_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# Show the fixed config
echo "=== Fixed config.json content ==="
cat "$CONFIG_FILE"
echo ""
echo "=== End of config.json ==="

echo "=== Fix Config Script Completed ==="
echo "Note: Corrupt .mbtiles files were excluded from config"
echo "Only valid .mbtiles files are included in the configuration"