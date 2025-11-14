# Frontend Integration - Leaflet Vector Tile Plugin

Karena konversi ke raster PNG memerlukan dependencies yang kompleks, solusi tercepat adalah menggunakan **Leaflet Vector Tile Plugin** yang bisa render vector tiles (PBF) dari grid_layer.

## 🚀 Quick Solution: Install Leaflet.VectorGrid

### 1. Install Plugin

```bash
npm install leaflet.vectorgrid
```

Atau via CDN:

```html
<script src="https://unpkg.com/leaflet.vectorgrid@latest/dist/Leaflet.VectorGrid.bundled.js"></script>
```

### 2. Use in Your Application

```javascript
import L from 'leaflet';
import 'leaflet.vectorgrid';

// Initialize map
const map = L.map('map').setView([-0.469, 117.172], 5);

// Add base map (optional)
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors'
}).addTo(map);

// Add grid layer (vector tiles rendered as raster)
const gridLayer = L.vectorGrid.protobuf(
    'https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf',
    {
        rendererFactory: L.canvas.tile,
        vectorTileLayerStyles: {
            'grid_layer': function(properties, zoom) {
                return {
                    fill: true,
                    fillColor: '#90EE90',  // Light green
                    fillOpacity: 0.5,
                    stroke: true,
                    color: '#228B22',      // Dark green
                    weight: 1
                };
            }
        },
        interactive: true,
        minZoom: 0,
        maxZoom: 14,
        getFeatureId: function(f) {
            return f.properties.id;
        }
    }
).addTo(map);

// Add drone layer (raster tiles)
const droneLayer = L.tileLayer(
    'https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg',
    {
        minZoom: 16,
        maxZoom: 22,
        attribution: 'Drone Imagery'
    }
).addTo(map);

// Optional: Layer control
L.control.layers(
    {}, // Base layers
    {
        'Grid 36 HA': gridLayer,
        'Drone Imagery': droneLayer
    }
).addTo(map);

// Optional: Add click event on grid
gridLayer.on('click', function(e) {
    if (e.layer.properties) {
        console.log('Grid clicked:', e.layer.properties);
        L.popup()
            .setLatLng(e.latlng)
            .setContent('Grid ID: ' + (e.layer.properties.id || 'N/A'))
            .openOn(map);
    }
});
```

### 3. Advanced Styling

```javascript
// Dynamic styling based on zoom level
const gridLayer = L.vectorGrid.protobuf(
    'https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf',
    {
        vectorTileLayerStyles: {
            'grid_layer': function(properties, zoom) {
                // More detail at higher zoom
                const opacity = zoom < 8 ? 0.3 : 0.6;
                const weight = zoom < 8 ? 0.5 : 1.5;
                
                return {
                    fill: true,
                    fillColor: '#90EE90',
                    fillOpacity: opacity,
                    stroke: true,
                    color: '#228B22',
                    weight: weight
                };
            }
        },
        minZoom: 0,
        maxZoom: 14
    }
).addTo(map);
```

### 4. React Example

```jsx
import React, { useEffect } from 'react';
import L from 'leaflet';
import 'leaflet.vectorgrid';
import 'leaflet/dist/leaflet.css';

function MapComponent() {
    useEffect(() => {
        // Initialize map
        const map = L.map('map').setView([-0.469, 117.172], 5);
        
        // Grid layer
        L.vectorGrid.protobuf(
            'https://glserver.ptnaghayasha.com/data/grid_layer/{z}/{x}/{y}.pbf',
            {
                vectorTileLayerStyles: {
                    'grid_layer': {
                        fill: true,
                        fillColor: '#90EE90',
                        fillOpacity: 0.5,
                        stroke: true,
                        color: '#228B22',
                        weight: 1
                    }
                },
                minZoom: 0,
                maxZoom: 14
            }
        ).addTo(map);
        
        // Drone layer
        L.tileLayer(
            'https://glserver.ptnaghayasha.com/data/glmap/{z}/{x}/{y}.jpg',
            {
                minZoom: 16,
                maxZoom: 22
            }
        ).addTo(map);
        
        return () => map.remove();
    }, []);
    
    return <div id="map" style={{ height: '100vh', width: '100%' }} />;
}

export default MapComponent;
```

## ✅ Advantages of This Approach

1. **No Conversion Needed** - Use existing vector tiles directly
2. **Smaller File Size** - Vector tiles (73MB) vs raster would be ~500MB+
3. **Better Quality** - Vector graphics scale perfectly at any zoom
4. **Interactive** - Can add click events, tooltips, etc.
5. **Fast Loading** - Vector tiles load and render quickly

## 📦 Package.json

```json
{
  "dependencies": {
    "leaflet": "^1.9.4",
    "leaflet.vectorgrid": "^1.3.0"
  }
}
```

## 🎨 Custom Styling Options

```javascript
// Green grid (current)
fillColor: '#90EE90', color: '#228B22'

// Blue grid
fillColor: '#ADD8E6', color: '#0066cc'

// Red grid
fillColor: '#FFB6C1', color: '#DC143C'

// Yellow grid
fillColor: '#FFFFE0', color: '#FFD700'

// Transparent with thick border
fillColor: 'transparent', fillOpacity: 0, color: '#228B22', weight: 2
```

## 🔧 Troubleshooting

### Grid not rendering?
- Check browser console for errors
- Verify PBF tiles loading: Open DevTools → Network tab
- Check zoom level (grid only shows zoom 0-14)

### Performance issues?
- Reduce fillOpacity for faster rendering
- Use `rendererFactory: L.canvas.tile` for better performance
- Limit maxZoom to avoid generating unnecessary tiles

### Wrong colors?
- Verify `source-layer` name is `'grid_layer'`
- Check vectorTileLayerStyles key matches source-layer name

## 📝 Summary

**This is the BEST solution because:**
- ✅ No complex conversion process
- ✅ Works with your existing grid_layer.mbtiles
- ✅ Only requires one npm package
- ✅ Renders beautifully in browser
- ✅ Much smaller file size
- ✅ Interactive features available

Just install `leaflet.vectorgrid` and use the code above! 🚀
