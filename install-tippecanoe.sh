#!/bin/bash

# Script untuk install tippecanoe di Ubuntu server
# Tippecanoe digunakan untuk convert shapefile ke vector tiles (mbtiles)

echo "=== Installing Tippecanoe for Vector Tiles ==="
echo ""

# Check if already installed
if command -v tippecanoe >/dev/null 2>&1; then
    echo "✓ Tippecanoe already installed"
    tippecanoe --version
    exit 0
fi

echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libsqlite3-dev \
    zlib1g-dev \
    git

echo ""
echo "Cloning tippecanoe repository..."
cd /tmp
git clone https://github.com/felt/tippecanoe.git
cd tippecanoe

echo ""
echo "Building tippecanoe..."
make -j$(nproc)

echo ""
echo "Installing tippecanoe..."
sudo make install

echo ""
echo "Verifying installation..."
if command -v tippecanoe >/dev/null 2>&1; then
    echo "✓ Tippecanoe installed successfully!"
    tippecanoe --version
else
    echo "✗ Installation failed"
    exit 1
fi

# Cleanup
cd /tmp
rm -rf tippecanoe

echo ""
echo "=== Installation Complete ==="
echo "You can now convert shapefiles to mbtiles vector tiles"