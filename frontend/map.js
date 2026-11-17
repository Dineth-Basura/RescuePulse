"use strict";
// RescuePulse 2.0 — Operational Leaflet Map
// Real incident data from authorized backend APIs. No synthetic live responder markers.
window.RescueMap = (() => {
  const severityColor = {CRITICAL: '#e94f5e', HIGH: '#f38c58', MEDIUM: '#f0c16b', LOW: '#59c7a7'};
  const categoryIcon = {
    FLOOD: '💧',
    LANDSLIDE: '⛰️',
    STORM: '🌪️',
    FIRE: '🔥',
    MEDICAL: '🏥',
    OTHER: '⚠️'
  };

  const verifiedShelters = [
    {name: 'Ratnapura Town Hall Relief Station', lat: 6.6828, lon: 80.4034, district: 'Ratnapura', capacity: 250},
    {name: 'Nivitigala Community Center Shelter', lat: 6.6025, lon: 80.4497, district: 'Ratnapura', capacity: 150},
    {name: 'Colombo Central Evacuation Center', lat: 6.9271, lon: 79.8612, district: 'Colombo', capacity: 400},
    {name: 'Kolonnawa Flood Relief Center', lat: 6.9366, lon: 79.8941, district: 'Colombo', capacity: 300},
    {name: 'Kandy Municipal Disaster Shelter', lat: 7.2906, lon: 80.6337, district: 'Kandy', capacity: 200},
    {name: 'Galle Fort Relief Center', lat: 6.0329, lon: 80.2168, district: 'Galle', capacity: 180},
    {name: 'Kalutara North Community Station', lat: 6.5854, lon: 79.9607, district: 'Kalutara', capacity: 220}
  ];

  function create(containerId, opts = {}) {
    const target = document.getElementById(containerId);
    if (!target) return null;
    if (!window.L) {
      target.textContent = 'Interactive maps require Leaflet and an internet connection. Stored incidents remain accessible in tables.';
      return null;
    }

    // Default centered on Sri Lanka
    const map = L.map(target, {zoomControl: true}).setView([7.8731, 80.7718], 7);
    const tileLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
      maxZoom: 18
    }).addTo(map);

    tileLayer.on('tileerror', () => {
      const banner = document.getElementById(containerId + '-message') || document.getElementById('map-status');
      if (banner) banner.textContent = 'Map tiles temporarily slow or unreachable. Check your network.';
    });

    const incidentGroup = L.layerGroup().addTo(map);
    const shelterGroup = L.layerGroup();
    let pin = null;

    // Build verified shelters layer
    for (const sh of verifiedShelters) {
      const icon = L.divIcon({
        className: 'custom-map-marker shelter-marker',
        html: `<div style="background:#0284c7;border:2px solid #38bdf8;width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,0.5);font-size:14px;cursor:pointer;">⛺</div>`,
        iconSize: [28, 28],
        iconAnchor: [14, 14]
      });
      const m = L.marker([sh.lat, sh.lon], {icon}).addTo(shelterGroup);
      m.bindPopup(`<strong>${sh.name}</strong><br><small>Verified District Relief Shelter (${sh.district})<br>Capacity: ~${sh.capacity} persons</small>`);
    }

    if (opts.showSheltersByDefault) {
      shelterGroup.addTo(map);
    }

    if (opts.onPick) {
      map.on('click', ev => {
        const {lat, lng} = ev.latlng;
        if (pin) {
          pin.setLatLng(ev.latlng);
        } else {
          pin = L.marker(ev.latlng).addTo(map);
        }
        opts.onPick({latitude: Number(lat.toFixed(6)), longitude: Number(lng.toFixed(6))});
      });
    }

    function toggleShelters(show) {
      if (show) {
        if (!map.hasLayer(shelterGroup)) map.addLayer(shelterGroup);
      } else {
        if (map.hasLayer(shelterGroup)) map.removeLayer(shelterGroup);
      }
    }

    function update(items, onSelect) {
      incidentGroup.clearLayers();
      let count = 0;
      for (const item of items) {
        if (typeof item.latitude !== 'number' || typeof item.longitude !== 'number' || !Number.isFinite(item.latitude) || !Number.isFinite(item.longitude)) continue;
        const color = severityColor[item.severity] || '#97a6bd';
        const symbol = categoryIcon[item.category] || '⚠️';
        const isCritical = item.severity === 'CRITICAL';
        const size = isCritical ? 34 : 28;

        const icon = L.divIcon({
          className: `custom-map-marker marker-${item.severity.toLowerCase()}`,
          html: `<div style="background:#1e293b;border:2px solid ${color};width:${size}px;height:${size}px;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 0 10px ${color}88;font-size:${isCritical ? '16px' : '13px'};cursor:pointer;">${symbol}</div>`,
          iconSize: [size, size],
          iconAnchor: [size / 2, size / 2]
        });

        const marker = L.marker([item.latitude, item.longitude], {icon}).addTo(incidentGroup);

        const popupContent = document.createElement('div');
        popupContent.style.minWidth = '180px';
        popupContent.style.fontFamily = 'inherit';
        popupContent.innerHTML = `
          <strong style="color:${color}">${item.category || 'INCIDENT'} · ${item.severity || 'UNKNOWN'}</strong>
          <div style="font-size:12px;margin:4px 0;">${item.location || ''}</div>
          <p style="font-size:11px;color:#475569;margin:4px 0 8px;">${(item.description || '').slice(0, 100)}</p>
          <div style="font-size:10px;margin-bottom:6px;">Status: <strong>${item.status}</strong> | Mission: <strong>${item.missionStatus || 'UNASSIGNED'}</strong></div>
        `;
        const selectBtn = document.createElement('button');
        selectBtn.textContent = 'View incident details';
        selectBtn.style.padding = '4px 8px';
        selectBtn.style.fontSize = '11px';
        selectBtn.style.cursor = 'pointer';
        selectBtn.style.borderRadius = '4px';
        selectBtn.style.border = '1px solid #334155';
        selectBtn.style.background = '#0f172a';
        selectBtn.style.color = '#e2e8f0';
        selectBtn.onclick = () => onSelect?.(item);
        popupContent.append(selectBtn);

        marker.bindPopup(popupContent);
        marker.bindTooltip(`${symbol} ${item.location} (${item.severity})`, {direction: 'top'});
        count++;
      }
      return count;
    }

    setTimeout(() => map.invalidateSize(), 150);

    return {
      map,
      update,
      toggleShelters,
      clearPin() {
        if (pin) {
          map.removeLayer(pin);
          pin = null;
        }
      },
      focus(item) {
        if (typeof item.latitude === 'number' && typeof item.longitude === 'number') {
          map.setView([item.latitude, item.longitude], 12);
        }
      },
      get pin() {
        return pin;
      }
    };
  }

  return {create};
})();
