# Frontend Integration Guide - 2-Layer XYZ Architecture

## 📊 Architecture Overview

Your tileserver now serves **2 separate XYZ layers**:

1. **grid_layer** - Base grid overview (zoom 0-14)
   - Format: Vector tiles (PBF)
   - File: `grid_layer.mbtiles` (68,731 tiles)
   
2. **glmap** - Drone imagery overlay (zoom 16-22)
   - Format: Raster tiles (JPG)
   - File: `glmap.mbtiles` (217,035 tiles)

## 🌐 XYZ URLs

```
Grid Layer:  https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf
Drone Layer: https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg
```

## 📱 Implementation Options

### Option 1: Leaflet with 2 Raster Layers (Simple)

**Note**: This treats vector grid as raster (not ideal but works)

```javascript
const map = L.map('map').setView([-2.75, 105.75], 10);

// Base layer - Grid
const gridLayer = L.tileLayer(
  'https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf',
  {
    minZoom: 0,
    maxZoom: 14,
    attribution: 'Grid 36 HA'
  }
);

// Overlay layer - Drone imagery
const droneLayer = L.tileLayer(
  'https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg',
  {
    minZoom: 16,
    maxZoom: 22,
    attribution: 'Drone Imagery'
  }
);

// Add both layers
gridLayer.addTo(map);
droneLayer.addTo(map);

// Optional: Layer control
L.control.layers(
  { 'OpenStreetMap': L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png') },
  { 'Grid': gridLayer, 'Drone': droneLayer }
).addTo(map);
```

### Option 2: Mapbox GL JS (Recommended for Vector Tiles)

**Note**: Properly renders vector grid tiles

```javascript
mapboxgl.accessToken = 'YOUR_MAPBOX_TOKEN'; // or use free map
const map = new mapboxgl.Map({
  container: 'map',
  style: 'mapbox://styles/mapbox/streets-v11',
  center: [105.75, -2.75],
  zoom: 10
});

map.on('load', () => {
  // Add vector grid layer
  map.addSource('grid', {
    type: 'vector',
    tiles: ['https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf'],
    minzoom: 0,
    maxzoom: 14
  });

  map.addLayer({
    id: 'grid-fill',
    type: 'fill',
    source: 'grid',
    'source-layer': 'grid_layer',
    minzoom: 0,
    maxzoom: 14,
    paint: {
      'fill-color': 'rgba(255, 192, 203, 0.3)',
      'fill-outline-color': '#0066cc'
    }
  });

  map.addLayer({
    id: 'grid-line',
    type: 'line',
    source: 'grid',
    'source-layer': 'grid_layer',
    minzoom: 0,
    maxzoom: 14,
    paint: {
      'line-color': '#0066cc',
      'line-width': 1
    }
  });

  // Add raster drone layer
  map.addSource('drone', {
    type: 'raster',
    tiles: ['https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg'],
    tileSize: 256,
    minzoom: 16,
    maxzoom: 22
  });

  map.addLayer({
    id: 'drone-raster',
    type: 'raster',
    source: 'drone',
    paint: {
      'raster-opacity': 1
    }
  });
});
```

### Option 3: From Upload Dialog (As Shown in Screenshot)

Based on your screenshot showing "Upload Data Layer" dialog:

1. **Add Grid Layer**:
   - Select "XYZ Tiles"
   - URL: `https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf`
   - Name: Grid 36 HA
   - Min Zoom: 0
   - Max Zoom: 14

2. **Add Drone Layer**:
   - Select "XYZ Tiles"
   - URL: `https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg`
   - Name: Drone Imagery
   - Min Zoom: 16
   - Max Zoom: 22

## 🎯 Zoom Behavior

| Zoom Level | Visible Layer | Description |
|------------|---------------|-------------|
| 0-14       | Grid only     | Pink grid overview |
| 15         | Transition    | Neither layer (gap) |
| 16-22      | Drone only    | High-res imagery |

### Fix Zoom Gap (Optional)

To avoid empty zoom 15:

```javascript
// Option A: Extend grid to zoom 15
gridLayer.options.maxZoom = 15;

// Option B: Extend drone to zoom 15
droneLayer.options.minZoom = 15;
```

## 🔧 Troubleshooting

### Grid not showing?
- Vector tiles (PBF) require proper renderer
- Use Mapbox GL JS or similar vector tile library
- Leaflet treats PBF as raster (may not render correctly)

### Drone not showing?
- Check zoom level (only visible at zoom 16+)
- Verify URL is accessible
- Check browser console for tile loading errors

### Both layers at same time?
- This is expected at overlapping zoom levels
- Adjust minZoom/maxZoom to control visibility
- Grid (0-14), Drone (16-22) = no overlap by default

## 📦 Server Configuration

Your `config.json` contains:

```json
{
  "data": {
    "grid_layer": {
      "mbtiles": "data/grid_layer.mbtiles"
    },
    "glmap": {
      "mbtiles": "data/glmap.mbtiles"
    },
    ...
  }
}
```

Both datasets are available via tileserver-gl at:
- Grid: `/data/grid_layer/{z}/{x}/{y}.pbf`
- Drone: `/data/glmap/{z}/{x}/{y}.jpg`

## 🚀 Deployment Checklist

- [ ] Upload `grid_layer.mbtiles` to server (73 MB)
- [ ] Upload `glmap.mbtiles` to server (999 MB, drone only)
- [ ] Upload `config.json` to server
- [ ] Restart tileserver-gl container
- [ ] Test grid URL in browser
- [ ] Test drone URL in browser
- [ ] Integrate both URLs in frontend
- [ ] Test zoom levels 0-14 (grid), 16-22 (drone)

## 📝 Notes

- Grid and drone are **completely separate files**
- No format mixing (vector/raster conflict resolved)
- Incremental updates only affect drone layer
- Grid remains static (73 MB, optimized)
- Total: ~1 GB for both layers
