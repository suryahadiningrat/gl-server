#!/bin/sh

# Script generate-config.sh untuk server Ubuntu - sh compatible
# Mengatasi masalah file trails corrupt dan JSON format

set -e

# Environment - deteksi otomatis path yang ada
if [ -n "$DATA_DIR" ]; then
    echo "Using provided DATA_DIR: $DATA_DIR"
elif [ -d "/app/data/tileserver" ]; then
    DATA_DIR="/app/data/tileserver"
elif [ -d "/app/data" ]; then
    DATA_DIR="/app/data"
else
    echo "Error: Data directory not found"
    echo "Tried: /app/data/tileserver, /app/data"
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-/app/config.json}"
STYLE_DIR="${STYLE_DIR:-/app/styles/default}"
STYLE_FILE="${STYLE_FILE:-$STYLE_DIR/style.json}"
GLMAP_FILE="${GLMAP_FILE:-$DATA_DIR/glmap.mbtiles}"
TEMP_CONFIG="${TEMP_CONFIG:-/tmp/config_temp.json}"

echo "=== Generate Config Script (Server Compatible) ==="
echo "Data directory: $DATA_DIR"
echo "Config file: $CONFIG_FILE"

# Create directories
mkdir -p "$STYLE_DIR"
mkdir -p "$DATA_DIR"

# Create style if not exists
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
fi

# Simple validation function 
is_valid_mbtiles() {
    local file="$1"
    
    # Check if readable
    [ -r "$file" ] || return 1
    
    # Check if has tiles table (simple check)
    sqlite3 "$file" ".tables" 2>/dev/null | grep -q "tiles" || return 1
    
    # Check if not empty
    tiles=$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    [ "$tiles" -gt 0 ] || return 1
    
    return 0
}

# Check data directory
if [ ! -d "$DATA_DIR" ]; then
    echo "Error: Data directory does not exist: $DATA_DIR"
    exit 1
fi

echo "Scanning files in: $DATA_DIR"
ls -la "$DATA_DIR"/*.mbtiles 2>/dev/null || echo "No .mbtiles files found"

# Remove old glmap
[ -f "$GLMAP_FILE" ] && rm -f "$GLMAP_FILE"

# Find valid files (no arrays, just count and track in temp file)
TEMP_VALID_LIST="/tmp/valid_mbtiles.txt"
TEMP_VALID_SUMMARY="/tmp/valid_files_summary.txt"
rm -f "$TEMP_VALID_LIST" "$TEMP_VALID_SUMMARY"

echo ""
echo "Processing files..."
VALID_COUNT=0

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    [ -f "$mbtiles_file" ] || continue
    
    filename=$(basename "$mbtiles_file")
    
    # Skip glmap
    [ "$filename" = "glmap.mbtiles" ] && continue
    
    # Skip trails files (they are corrupt)
    case "$filename" in
        *_trails*)
            echo "  - Skipping: $filename (trails - known corrupt)"
            continue
            ;;
    esac
    
    echo "Checking: $filename"
    
    if is_valid_mbtiles "$mbtiles_file"; then
        tile_count=$(sqlite3 "$mbtiles_file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
        echo "  ✓ Valid: $filename ($tile_count tiles)"
        echo "$mbtiles_file" >> "$TEMP_VALID_LIST"
        echo "$mbtiles_file" >> "$TEMP_VALID_SUMMARY"
        VALID_COUNT=$((VALID_COUNT + 1))
    else
        echo "  - Invalid: $filename"
    fi
done

echo "Found $VALID_COUNT valid files"

# Create glmap if we have valid files
if [ "$VALID_COUNT" -gt 0 ]; then
    echo "Creating merged glmap.mbtiles..."
    
    # Create database
    sqlite3 "$GLMAP_FILE" "
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        INSERT INTO metadata (name, value) VALUES ('name', 'GL Map');
        INSERT INTO metadata (name, value) VALUES ('type', 'baselayer');
        INSERT INTO metadata (name, value) VALUES ('format', 'jpg');
    "
    
    # Merge files
    while IFS= read -r mbtiles_file; do
        filename=$(basename "$mbtiles_file")
        echo "Merging: $filename"
        
        sqlite3 "$GLMAP_FILE" "
            ATTACH DATABASE '$mbtiles_file' AS source;
            INSERT OR IGNORE INTO tiles SELECT * FROM source.tiles;
            DETACH DATABASE source;
        " 2>/dev/null && echo "  ✓ Merged" || echo "  ✗ Failed"
        
    done < "$TEMP_VALID_LIST"
    
    total=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    echo "Total tiles in glmap: $total"
else
    echo "No valid files, creating empty glmap"
    sqlite3 "$GLMAP_FILE" "
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
    "
fi

# Generate config.json
echo ""
echo "Generating config.json..."

# Create basic config structure
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

# Add individual files
if [ -f "$TEMP_VALID_LIST" ] && [ "$VALID_COUNT" -gt 0 ]; then
    while IFS= read -r mbtiles_file; do
        filename=$(basename "$mbtiles_file")
        basename_only=$(basename "$mbtiles_file" .mbtiles)
        
        echo "    ," >> "$TEMP_CONFIG"
        echo "    \"$basename_only\": {" >> "$TEMP_CONFIG"
        echo "      \"mbtiles\": \"data/$filename\"" >> "$TEMP_CONFIG" 
        echo "    }" >> "$TEMP_CONFIG"
        
    done < "$TEMP_VALID_LIST"
fi

# Close config
echo "  }" >> "$TEMP_CONFIG"
echo "}" >> "$TEMP_CONFIG"

# Validate JSON
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool "$TEMP_CONFIG" >/dev/null 2>&1; then
        echo "✓ JSON valid"
    else
        echo "✗ JSON invalid!"
        cat "$TEMP_CONFIG"
        exit 1
    fi
else
    echo "Python3 not available, skipping JSON validation"
fi

# Apply config
cp "$TEMP_CONFIG" "$CONFIG_FILE"
echo "✓ Config applied: $CONFIG_FILE"

# Show config
echo ""
echo "=== Generated Config ==="
if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$CONFIG_FILE" 2>/dev/null || cat "$CONFIG_FILE"
else
    cat "$CONFIG_FILE"
fi
echo "=== End Config ==="

# Restart container
echo ""
if command -v docker >/dev/null 2>&1; then
    echo "Restarting tileserver container..."
    docker restart tileserver-zurich && echo "✓ Container restarted" || echo "✗ Restart failed"
else
    echo "Docker not available - please restart container manually"
fi

# Update PostgreSQL database
echo ""
echo "=== Updating PostgreSQL Database ==="

# Database credentials
DBHOST="172.26.11.153"
DBUSER="pg"
DBPASS="~nagha2025yasha@~"
DBNAME="postgres"
DBPORT="5432"

echo "Database: $DBUSER@$DBHOST:$DBPORT/$DBNAME"

# Check if database update should be skipped
if [ "$SKIP_DB_UPDATE" = "true" ]; then
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
    if [ "$DB_UPDATE_AVAILABLE" = "true" ] && [ -f "$TEMP_VALID_LIST" ]; then
        echo ""
        echo "Processing coordinates for database update..."
        
        # Process individual files
        while IFS= read -r mbtiles_file; do
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
            
        done < "$TEMP_VALID_LIST"
        
        # Also process glmap if it exists
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
        echo "Database update skipped (dependencies not available or no files to process)"
    fi
fi

# Summary
echo ""
echo "=== Summary ==="
echo "✓ Valid files processed: $VALID_COUNT"
echo "✓ Config datasets: $((VALID_COUNT + 1)) (including glmap)"
echo "✓ Database coordinates updated"
echo "✓ Script completed successfully"

echo ""
echo "Your tileserver should now show:"
echo "  - glmap (merged tiles)"
if [ -f "$TEMP_VALID_SUMMARY" ]; then
    while IFS= read -r mbtiles_file; do
        echo "  - $(basename "$mbtiles_file" .mbtiles)"
    done < "$TEMP_VALID_SUMMARY"
fi

# Final cleanup
rm -f "$TEMP_CONFIG" "$TEMP_VALID_LIST" "$TEMP_VALID_SUMMARY"