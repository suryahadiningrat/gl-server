#!/usr/bin/env python3

"""
Convert grid shapefile to raster PNG tiles in MBTiles format
Compatible with standard Leaflet L.tileLayer()
"""

import sqlite3
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw
import sys

try:
    import fiona
    from shapely.geometry import shape
except ImportError:
    print("Error: Required packages not installed")
    print("Install with: pip3 install fiona shapely pillow")
    sys.exit(1)

# Configuration
DATA_DIR = Path("/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data")
GRID_SHP = DATA_DIR / "GRID_DRONE_36_HA_EKSISTING_POTENSI" / "GRID_36_HA_EKSISTING_POTENSI.shp"
OUTPUT_MBTILES = DATA_DIR / "grid_layer_raster.mbtiles"

# Tile parameters
MIN_ZOOM = 0
MAX_ZOOM = 14
TILE_SIZE = 256
GRID_COLOR = (144, 238, 144, 128)  # Light green with alpha
LINE_COLOR = (34, 139, 34, 255)    # Dark green
LINE_WIDTH = 1

def deg2num(lat, lon, zoom):
    """Convert lat/lon to tile numbers"""
    lat_rad = math.radians(lat)
    n = 2.0 ** zoom
    xtile = int((lon + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return (xtile, ytile)

def num2deg(xtile, ytile, zoom):
    """Convert tile numbers to lat/lon"""
    n = 2.0 ** zoom
    lon_deg = xtile / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * ytile / n)))
    lat_deg = math.degrees(lat_rad)
    return (lat_deg, lon_deg)

def latlon_to_pixel(lat, lon, xtile, ytile, zoom):
    """Convert lat/lon to pixel position in tile"""
    # Get tile bounds
    lat_top, lon_left = num2deg(xtile, ytile, zoom)
    lat_bottom, lon_right = num2deg(xtile + 1, ytile + 1, zoom)
    
    # Calculate pixel position
    x = int((lon - lon_left) / (lon_right - lon_left) * TILE_SIZE)
    y = int((lat - lat_top) / (lat_bottom - lat_top) * TILE_SIZE)
    
    return (x, y)

def create_mbtiles_db(output_path):
    """Create MBTiles database structure"""
    if output_path.exists():
        output_path.unlink()
    
    conn = sqlite3.connect(str(output_path))
    cursor = conn.cursor()
    
    # Create tables
    cursor.execute("""
        CREATE TABLE tiles (
            zoom_level INTEGER,
            tile_column INTEGER,
            tile_row INTEGER,
            tile_data BLOB
        )
    """)
    cursor.execute("""
        CREATE UNIQUE INDEX tile_index ON tiles (
            zoom_level, tile_column, tile_row
        )
    """)
    cursor.execute("""
        CREATE TABLE metadata (name TEXT, value TEXT)
    """)
    cursor.execute("CREATE UNIQUE INDEX metadata_index ON metadata (name)")
    
    # Add metadata
    metadata = {
        'name': 'Grid 36 HA (Raster PNG)',
        'type': 'overlay',
        'version': '1.3',
        'description': 'Grid layer as raster PNG tiles for Leaflet',
        'format': 'png',
        'bounds': '95.141602,-10.941192,141.004028,5.878332',
        'center': '118.072815,-2.531430,6',
        'minzoom': str(MIN_ZOOM),
        'maxzoom': str(MAX_ZOOM),
        'attribution': 'Grid 36 HA'
    }
    
    for name, value in metadata.items():
        cursor.execute("INSERT INTO metadata (name, value) VALUES (?, ?)", (name, value))
    
    conn.commit()
    return conn

def get_tiles_for_geometry(geom_bounds, zoom):
    """Get all tiles that intersect with geometry bounds"""
    minx, miny, maxx, maxy = geom_bounds
    
    # Get tile range
    tile_minx, tile_maxy = deg2num(maxy, minx, zoom)
    tile_maxx, tile_miny = deg2num(miny, maxx, zoom)
    
    tiles = []
    for x in range(tile_minx, tile_maxx + 1):
        for y in range(tile_miny, tile_maxy + 1):
            tiles.append((x, y))
    
    return tiles

def draw_geometry_on_tile(img, geom, xtile, ytile, zoom):
    """Draw a geometry on a tile image"""
    draw = ImageDraw.Draw(img, 'RGBA')
    
    if geom.geom_type == 'Polygon':
        polygons = [geom]
    elif geom.geom_type == 'MultiPolygon':
        polygons = list(geom.geoms)
    else:
        return
    
    for polygon in polygons:
        # Convert exterior coordinates to pixel coordinates
        pixels = []
        for lon, lat in polygon.exterior.coords:
            x, y = latlon_to_pixel(lat, lon, xtile, ytile, zoom)
            if 0 <= x <= TILE_SIZE and 0 <= y <= TILE_SIZE:
                pixels.append((x, y))
        
        if len(pixels) >= 3:
            # Draw filled polygon
            draw.polygon(pixels, fill=GRID_COLOR, outline=LINE_COLOR, width=LINE_WIDTH)

def main():
    print("═" * 60)
    print("  Grid to Raster PNG Tiles Converter")
    print("═" * 60)
    print()
    
    # Check input file
    if not GRID_SHP.exists():
        print(f"✗ Error: Shapefile not found at {GRID_SHP}")
        sys.exit(1)
    
    print(f"Input:  {GRID_SHP}")
    print(f"Output: {OUTPUT_MBTILES}")
    print(f"Zoom:   {MIN_ZOOM} - {MAX_ZOOM}")
    print()
    
    # Create MBTiles database
    print("Creating MBTiles database...")
    conn = create_mbtiles_db(OUTPUT_MBTILES)
    cursor = conn.cursor()
    
    # Read shapefile
    print("Reading shapefile...")
    with fiona.open(str(GRID_SHP)) as src:
        geometries = [(shape(feature['geometry']), feature['geometry']['coordinates']) 
                     for feature in src]
    
    print(f"  Found {len(geometries)} grid polygons")
    print()
    
    # Generate tiles for each zoom level
    total_tiles = 0
    
    for zoom in range(MIN_ZOOM, MAX_ZOOM + 1):
        print(f"Processing zoom level {zoom}...")
        
        # Collect all tiles that need to be generated
        tiles_needed = set()
        for geom, _ in geometries:
            tiles = get_tiles_for_geometry(geom.bounds, zoom)
            tiles_needed.update(tiles)
        
        print(f"  Generating {len(tiles_needed)} tiles...")
        
        # Generate each tile
        for tile_idx, (xtile, ytile) in enumerate(tiles_needed):
            if (tile_idx + 1) % 100 == 0:
                print(f"    {tile_idx + 1}/{len(tiles_needed)}...", end='\r')
            
            # Create blank tile
            img = Image.new('RGBA', (TILE_SIZE, TILE_SIZE), (255, 255, 255, 0))
            
            # Draw all geometries that intersect this tile
            for geom, _ in geometries:
                # Check if geometry intersects tile bounds
                lat_top, lon_left = num2deg(xtile, ytile, zoom)
                lat_bottom, lon_right = num2deg(xtile + 1, ytile + 1, zoom)
                
                minx, miny, maxx, maxy = geom.bounds
                
                # Skip if no intersection
                if maxx < lon_left or minx > lon_right or maxy < lat_bottom or miny > lat_top:
                    continue
                
                draw_geometry_on_tile(img, geom, xtile, ytile, zoom)
            
            # Save tile if it has content (not fully transparent)
            if img.getbbox():
                # Convert to PNG bytes
                from io import BytesIO
                buffer = BytesIO()
                img.save(buffer, format='PNG', optimize=True)
                tile_data = buffer.getvalue()
                
                # Insert into database
                cursor.execute(
                    "INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)",
                    (zoom, xtile, ytile, tile_data)
                )
                total_tiles += 1
        
        print(f"  ✓ {len(tiles_needed)} tiles generated")
        conn.commit()
    
    print()
    print("Optimizing database...")
    cursor.execute("VACUUM")
    conn.commit()
    conn.close()
    
    print()
    print("═" * 60)
    print("  ✓ Conversion Complete!")
    print("═" * 60)
    print()
    print(f"Created: {OUTPUT_MBTILES}")
    print(f"Total tiles: {total_tiles}")
    print(f"Format: PNG (raster)")
    print(f"Zoom: {MIN_ZOOM} - {MAX_ZOOM}")
    print()
    print("Use in Leaflet:")
    print()
    print("L.tileLayer('https://glserver.ptnaghayasha.com/data/grid_layer_raster/{z}/{x}/{y}.png', {")
    print("    minZoom: 0,")
    print("    maxZoom: 14,")
    print("    opacity: 0.6")
    print("}).addTo(map);")
    print()

if __name__ == '__main__':
    main()
