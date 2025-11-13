#!/bin/bash

# Script generate-config.sh yang sudah diperbaiki
# Khusus untuk Ubuntu 24.4 server dengan file trails yang corrupt
# Compatible dengan sh dan bash

set -e

# Environment variables - sesuaikan dengan server Anda
DATA_DIR="${DATA_DIR:-/app/data}"
CONFIG_FILE="/app/config.json"
STYLE_DIR="/app/styles/default"
STYLE_FILE="/app/styles/default/style.json"
GLMAP_FILE="$DATA_DIR/glmap.mbtiles"
TEMP_CONFIG="/tmp/config_temp.json"

echo "=== Generate Config Script Started (Server Fixed Version) ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"

# Create directories
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

# Create default style
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

# Validation function
validate_mbtiles() {
    local file="$1"
    
    # Check if readable
    [ -r "$file" ] || return 1
    
    # Check if has tiles table
    sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table' AND name='tiles';" 2>/dev/null | grep -q "tiles" || return 1
    
    # Check integrity
    sqlite3 "$file" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok" || return 1
    
    return 0
}

# Check data directory
if [ ! -d "$DATA_DIR" ]; then
    echo "Warning: Data directory $DATA_DIR does not exist"
    exit 1
fi

echo "Scanning for valid .mbtiles files..."
echo "Files in directory:"
ls -la "$DATA_DIR"/*.mbtiles 2>/dev/null || echo "No .mbtiles files found"

# Remove existing glmap
if [ -f "$GLMAP_FILE" ]; then
    echo "Removing existing glmap.mbtiles..."
    rm -f "$GLMAP_FILE"
fi

# Collect valid files (excluding trails and glmap)
VALID_FILES=""
MERGED_COUNT=0

echo ""
echo "Processing files for merge..."
for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    if [ -f "$mbtiles_file" ]; then
        filename=$(basename "$mbtiles_file")
        
        # Skip glmap and trails files
        if [ "$filename" = "glmap.mbtiles" ]; then
            continue
        fi
        
        case "$filename" in
            *_trails*)
                echo "  - Skipping: $filename (trails - known corrupt)"
                continue
                ;;
        esac
        
        echo "Validating: $filename"
        
        if validate_mbtiles "$mbtiles_file"; then
            tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
            if [ "$tile_count" -gt 0 ]; then
                echo "  ✓ Valid: $filename ($tile_count tiles)"
                VALID_FILES="$VALID_FILES $mbtiles_file"
                MERGED_COUNT=$((MERGED_COUNT + 1))
            else
                echo "  - Skipping: $filename (no tiles)"
            fi
        else
            echo "  - Skipping: $filename (validation failed)"
        fi
    fi
done

echo ""
echo "Found $MERGED_COUNT valid files to merge"

# Merge valid files into glmap
if [ "$MERGED_COUNT" -gt 0 ]; then
    echo "Creating glmap.mbtiles..."
    
    # Create glmap database
    sqlite3 "$GLMAP_FILE" "CREATE TABLE metadata (name text, value text);"
    sqlite3 "$GLMAP_FILE" "CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);"
    sqlite3 "$GLMAP_FILE" "CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);"
    
    # Set metadata
    sqlite3 "$GLMAP_FILE" "INSERT INTO metadata (name, value) VALUES ('name', 'GL Map');"
    sqlite3 "$GLMAP_FILE" "INSERT INTO metadata (name, value) VALUES ('type', 'baselayer');"
    sqlite3 "$GLMAP_FILE" "INSERT INTO metadata (name, value) VALUES ('version', '1.0.0');"
    sqlite3 "$GLMAP_FILE" "INSERT INTO metadata (name, value) VALUES ('description', 'Merged tiles from multiple sources');"
    sqlite3 "$GLMAP_FILE" "INSERT INTO metadata (name, value) VALUES ('format', 'jpg');"
    
    # Merge tiles
    for mbtiles_file in $VALID_FILES; do
        if [ -f "$mbtiles_file" ]; then
            filename=$(basename "$mbtiles_file")
            echo "Merging: $filename"
            
            if sqlite3 "$GLMAP_FILE" "
                ATTACH DATABASE '$mbtiles_file' AS source;
                INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
                DETACH DATABASE source;
            " 2>/dev/null; then
                echo "  ✓ Successfully merged"
            else
                echo "  ✗ Failed to merge"
            fi
        fi
    done
    
    total_tiles=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    echo "Merge complete: $total_tiles total tiles in glmap.mbtiles"
else
    echo "No valid files to merge, creating empty glmap"
    sqlite3 "$GLMAP_FILE" "CREATE TABLE metadata (name text, value text);"
    sqlite3 "$GLMAP_FILE" "CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);"
fi

# Generate config.json
echo ""
echo "Generating config.json..."

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

# Add glmap
echo '    "glmap": {' >> "$TEMP_CONFIG"
echo '      "mbtiles": "data/glmap.mbtiles"' >> "$TEMP_CONFIG"

# Add individual valid files
INDIVIDUAL_COUNT=0
for mbtiles_file in $VALID_FILES; do
    if [ -f "$mbtiles_file" ]; then
        filename=$(basename "$mbtiles_file")
        basename_only=$(basename "$mbtiles_file" .mbtiles)
        
        echo "    }," >> "$TEMP_CONFIG"
        echo "    \"$basename_only\": {" >> "$TEMP_CONFIG"
        echo "      \"mbtiles\": \"data/$filename\"" >> "$TEMP_CONFIG"
        
        INDIVIDUAL_COUNT=$((INDIVIDUAL_COUNT + 1))
    fi
done

# Close config
echo "    }" >> "$TEMP_CONFIG"
echo "  }" >> "$TEMP_CONFIG"
echo "}" >> "$TEMP_CONFIG"

# Validate JSON
if python3 -m json.tool "$TEMP_CONFIG" > /dev/null 2>&1; then
    echo "✓ JSON validation passed"
    
    # Stop tileserver processes
    pkill -f "tileserver-gl" || true
    sleep 2
    
    # Apply config
    cp "$TEMP_CONFIG" "$CONFIG_FILE"
    rm -f "$TEMP_CONFIG"
    
    echo "✓ Config.json generated successfully!"
else
    echo "✗ JSON validation failed!"
    echo "Generated config:"
    cat "$TEMP_CONFIG"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# Show generated config
echo ""
echo "=== Generated config.json ==="
python3 -m json.tool "$CONFIG_FILE"
echo "=== End config.json ==="

# Restart tileserver container
echo ""
echo "Restarting tileserver-zurich container..."
if command -v docker >/dev/null 2>&1; then
    if docker restart tileserver-zurich; then
        echo "✓ Container restarted successfully!"
    else
        echo "✗ Failed to restart container"
        exit 1
    fi
else
    echo "Docker not available, please restart container manually"
fi

# Final summary
echo ""
echo "=== Summary ==="
echo "✓ Valid files merged into glmap: $MERGED_COUNT"
echo "✓ Individual files in config: $INDIVIDUAL_COUNT"
echo "✓ Total datasets available: $((INDIVIDUAL_COUNT + 1))"
echo ""
echo "Valid files included:"
for mbtiles_file in $VALID_FILES; do
    if [ -f "$mbtiles_file" ]; then
        echo "  - $(basename "$mbtiles_file" .mbtiles)"
    fi
done

echo ""
echo "=== Script Complete ==="
echo "Your tileserver should now show all valid .mbtiles files as separate data sources"
echo "Plus the merged 'glmap' containing all tiles combined"