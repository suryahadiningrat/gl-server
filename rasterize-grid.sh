#!/bin/bash

# Rasterize grid vector tiles to raster format for merging with drone imagery

set -e

GRID_VECTOR="/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data/grid_layer.mbtiles"
GRID_RASTER="/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data/grid_raster.mbtiles"
GRID_PNG_DIR="/tmp/grid_tiles"

echo "=== Rasterizing Grid to Match Drone Format ==="

# Check if gdal is available
if ! command -v gdal_translate >/dev/null 2>&1; then
    echo "Error: GDAL not found. Install with: brew install gdal"
    exit 1
fi

# Create temp directory for PNG tiles
mkdir -p "$GRID_PNG_DIR"

echo "Converting vector grid to GeoTIFF..."
ogr2ogr -f "GeoTIFF" /tmp/grid.tif "$GRID_VECTOR"

echo "Creating raster tiles from GeoTIFF..."
gdal2tiles.py -z 0-14 -r average /tmp/grid.tif "$GRID_PNG_DIR"

echo "Converting PNG tiles to MBTiles..."
# Use mb-util or manual SQL insert

echo "✓ Grid rasterized to $GRID_RASTER"
