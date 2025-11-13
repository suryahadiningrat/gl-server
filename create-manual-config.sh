#!/bin/bash

# Script untuk membuat config.json manual berdasarkan file yang valid
# Berdasarkan hasil check sebelumnya

set -e

CONFIG_FILE="/app/config.json"
TEMP_CONFIG="/tmp/manual_config.json"

echo "=== Manual Config Generation ==="

# Buat config dengan file yang sudah diketahui valid
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
    "1761575406079_54097_32853": {
      "mbtiles": "data/1761575406079_54097_32853.mbtiles"
    },
    "1761575459307_x54097_32853": {
      "mbtiles": "data/1761575459307_x54097_32853.mbtiles"
    },
    "1761575908071_Y54097_32853": {
      "mbtiles": "data/1761575908071_Y54097_32853.mbtiles"
    },
    "1762157419255_1761574836479_54098_32852": {
      "mbtiles": "data/1762157419255_1761574836479_54098_32852.mbtiles"
    }
  }
}
EOF

echo "Generated manual config:"
echo "========================"
cat "$TEMP_CONFIG"
echo "========================"

# Validasi JSON
if python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "✓ JSON validation: PASSED"
    
    # Stop tileserver process
    echo "Stopping tileserver-gl processes..."
    pkill -f "tileserver-gl" || true
    sleep 2
    
    # Apply config
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
    rm -f "$TEMP_CONFIG"
    
    echo "✓ Manual config applied successfully!"
    echo "Config now includes 6 valid .mbtiles files + glmap"
    
else
    echo "✗ JSON validation: FAILED"
    cat "$TEMP_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

echo "=== Manual Config Generation Complete ==="
echo ""
echo "Next steps:"
echo "1. Restart your tileserver container"
echo "2. Check the web interface - you should now see all individual files"