#!/bin/sh

# Clean glmap.mbtiles - Remove grid tiles (keep DRONE ONLY)

GLMAP_FILE="/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data/glmap.mbtiles"

if [ ! -f "$GLMAP_FILE" ]; then
    echo "Error: glmap.mbtiles not found"
    exit 1
fi

echo "Cleaning glmap.mbtiles..."
echo "Current tile count:"
sqlite3 "$GLMAP_FILE" "SELECT 'Total tiles: ' || COUNT(*) FROM tiles;"

echo ""
echo "Removing grid tiles (zoom 0-14)..."
grid_count=$(sqlite3 "$GLMAP_FILE" "SELECT COUNT(*) FROM tiles WHERE zoom_level <= 14;")
echo "Found $grid_count grid tiles to remove"

sqlite3 "$GLMAP_FILE" "DELETE FROM tiles WHERE zoom_level <= 14; VACUUM;"

echo ""
echo "Updated tile count:"
sqlite3 "$GLMAP_FILE" "SELECT 'Drone tiles: ' || COUNT(*) FROM tiles;"

echo ""
echo "Updating metadata to reflect drone-only..."
sqlite3 "$GLMAP_FILE" "
UPDATE metadata SET value = '16' WHERE name = 'minzoom';
UPDATE metadata SET value = 'jpg' WHERE name = 'format';
UPDATE metadata SET value = 'overlay' WHERE name = 'type';
UPDATE metadata SET value = 'Drone Imagery' WHERE name = 'attribution';
VACUUM;
"

echo "✓ glmap.mbtiles cleaned (DRONE ONLY)"
echo ""
echo "Next step: Run ./generate-config-incremental.sh"
