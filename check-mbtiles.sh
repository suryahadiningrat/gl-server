#!/bin/bash

# Script untuk mengecek status semua file .mbtiles
# dan mendiagnosis mengapa file individual tidak muncul

set -e

DATA_DIR="/Users/suryahadiningrat/Documents/projects/klhk/gl-server/data"

echo "=== MBTiles File Diagnostic ==="
echo "Checking files in: $DATA_DIR"
echo ""

# Fungsi untuk cek validitas file mbtiles
check_mbtiles_detailed() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo "=== Checking: $filename ==="
    
    # Cek apakah file ada dan readable
    if [ ! -f "$file" ]; then
        echo "❌ File does not exist"
        return 1
    fi
    
    if [ ! -r "$file" ]; then
        echo "❌ File is not readable"
        return 1
    fi
    
    # Cek ukuran file
    file_size=$(ls -lh "$file" | awk '{print $5}')
    echo "📁 File size: $file_size"
    
    # Cek apakah file adalah SQLite database
    if ! file "$file" | grep -q "SQLite"; then
        echo "❌ Not a SQLite database"
        return 1
    fi
    echo "✅ SQLite database format"
    
    # Cek integrity database
    if ! sqlite3 "$file" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
        echo "❌ Database integrity check FAILED"
        echo "   Corruption detected!"
        return 1
    fi
    echo "✅ Database integrity OK"
    
    # Cek apakah ada tabel yang diperlukan
    tables=$(sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "")
    if [ -z "$tables" ]; then
        echo "❌ No tables found in database"
        return 1
    fi
    echo "📋 Tables found: $tables"
    
    # Cek tabel tiles
    if ! echo "$tables" | grep -q "tiles"; then
        echo "❌ Missing 'tiles' table"
        return 1
    fi
    echo "✅ 'tiles' table exists"
    
    # Cek tabel metadata
    if ! echo "$tables" | grep -q "metadata"; then
        echo "❌ Missing 'metadata' table"
        return 1
    fi
    echo "✅ 'metadata' table exists"
    
    # Hitung jumlah tiles
    tile_count=$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    echo "🗂️  Total tiles: $tile_count"
    
    if [ "$tile_count" -eq 0 ]; then
        echo "⚠️  Warning: No tiles in database"
        return 1
    fi
    
    # Cek metadata
    echo "📝 Metadata:"
    sqlite3 "$file" "SELECT '  ' || name || ': ' || value FROM metadata;" 2>/dev/null || echo "  No metadata found"
    
    # Cek zoom levels
    zoom_levels=$(sqlite3 "$file" "SELECT DISTINCT zoom_level FROM tiles ORDER BY zoom_level;" 2>/dev/null || echo "")
    if [ -n "$zoom_levels" ]; then
        echo "🔍 Zoom levels: $(echo $zoom_levels | tr '\n' ' ')"
    fi
    
    echo "✅ File is VALID"
    echo ""
    return 0
}

# Cek semua file .mbtiles
valid_files=0
invalid_files=0
total_files=0

echo "Scanning all .mbtiles files..."
echo ""

for mbtiles_file in "$DATA_DIR"/*.mbtiles; do
    if [ -f "$mbtiles_file" ]; then
        total_files=$((total_files + 1))
        
        if check_mbtiles_detailed "$mbtiles_file"; then
            valid_files=$((valid_files + 1))
        else
            invalid_files=$((invalid_files + 1))
        fi
    fi
done

echo "=== SUMMARY ==="
echo "Total files checked: $total_files"
echo "Valid files: $valid_files"
echo "Invalid/Corrupt files: $invalid_files"
echo ""

if [ $invalid_files -gt 0 ]; then
    echo "⚠️  Some files are corrupt or invalid!"
    echo "   These files will not appear in the tileserver interface"
    echo "   Only valid files are included in config.json"
fi

echo ""
echo "=== Checking current config.json ==="
CONFIG_FILE="/Users/suryahadiningrat/Documents/projects/klhk/gl-server/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "Data sources in config:"
    grep -A 2 '"data"' "$CONFIG_FILE" | grep -E '^\s*"[^"]*":\s*{' | sed 's/.*"\([^"]*\)".*/  - \1/'
else
    echo "❌ config.json not found"
fi

echo ""
echo "=== Recommendations ==="
if [ $invalid_files -gt 0 ]; then
    echo "1. Remove or replace corrupt .mbtiles files"
    echo "2. Re-run generate-config-fixed.sh to update config"
    echo "3. Only valid files will be available as individual data sources"
fi

echo "4. glmap.mbtiles contains merged data from ALL valid files"
echo "5. Individual files appear as separate data sources if they are valid"