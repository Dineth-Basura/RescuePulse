"use strict";
const citizenToken = localStorage.getItem('rp_token');
const citizenEl = id => document.getElementById(id);
let citizenMap = null, citizenReports = [];
let selectedPhoto = null; // {filename, mimeType, base64Data}

function citizenText(tag, text, klass) {
  const el = document.createElement(tag);
  el.textContent = text;
  if (klass) el.className = klass;
  return el;
}

function citizenMessage(msg, isError = false) {
  const el = citizenEl('citizen-message');
  el.textContent = msg;
  el.className = isError ? 'error' : 'muted';
}

async function citizenApi(path, method = 'GET', body) {
  const response = await fetch(path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${citizenToken || ''}`
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000)
  });
  const payload = await response.json();
  if (response.status === 401) {
    location.replace('/sign-in.html');
    throw new Error('Please sign in.');
  }
  if (!response.ok) throw new Error(payload.message || `Request failed (${response.status})`);
  return payload;
}

function citizenCoordinates() {
  const lat = citizenEl('citizen-latitude').value.trim();
  const lon = citizenEl('citizen-longitude').value.trim();
  if (!lat && !lon) return {};
  if (!lat || !lon) throw new Error('Enter both latitude and longitude or select on the map.');
  const latitude = Number(lat);
  const longitude = Number(lon);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
    throw new Error('Coordinates must be between -90..90 latitude and -180..180 longitude.');
  }
  return {latitude, longitude};
}

function renderPhotoPreview(file) {
  if (!file) {
    selectedPhoto = null;
    citizenEl('photo-preview-wrap').style.display = 'none';
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    alert('File size exceeds the 5MB limit.');
    citizenEl('citizen-photo').value = '';
    return;
  }
  const reader = new FileReader();
  reader.onload = ev => {
    selectedPhoto = {
      filename: file.name,
      mimeType: file.type || 'image/jpeg',
      base64Data: ev.target.result
    };
    citizenEl('photo-preview').src = ev.target.result;
    citizenEl('photo-preview-wrap').style.display = 'flex';
  };
  reader.readAsDataURL(file);
}

citizenEl('citizen-photo').onchange = e => {
  const file = e.target.files?.[0];
  renderPhotoPreview(file);
};

citizenEl('photo-clear').onclick = () => {
  citizenEl('citizen-photo').value = '';
  renderPhotoPreview(null);
};

function citizenRender() {
  const root = citizenEl('citizen-reports');
  root.replaceChildren();
  if (!citizenReports.length) {
    root.append(citizenText('p', 'No reports submitted yet. Submit an observation above to begin.', 'muted'));
  }
  for (const item of citizenReports) {
    const box = citizenText('article', '', 'rp-incident-item');
    const header = citizenText('div', '', 'incident-card-header');
    header.append(citizenText('small', `TRACKING REFERENCE: ${item.id}`));
    box.append(header);

    const title = citizenText('h3', `${item.category || 'OTHER'} · ${item.location}`);
    box.append(title);

    const statusRow = citizenText('div', '', 'rp-status-row');
    const verifyClass = (item.verificationStatus || '').toLowerCase();
    statusRow.append(
      citizenText('span', `Review: ${item.verificationStatus || 'PENDING'}`, `rp-tag ${verifyClass}`),
      document.createTextNode(' '),
      citizenText('span', `Mission: ${item.missionStatus || 'UNASSIGNED'}`, 'rp-step')
    );
    box.append(statusRow);

    box.append(citizenText('p', item.description));

    if (item.attachmentUrl) {
      const attachDiv = citizenText('div', '', 'attachment-thumb-wrap');
      attachDiv.style.margin = '8px 0';
      const authUrl = citizenToken ? `${item.attachmentUrl}?token=${encodeURIComponent(citizenToken)}` : item.attachmentUrl;
      const img = document.createElement('img');
      img.src = authUrl;
      img.alt = item.attachmentName || 'Incident photograph';
      img.style.maxHeight = '80px';
      img.style.borderRadius = '6px';
      img.style.border = '1px solid #334155';
      img.style.cursor = 'pointer';
      img.onclick = () => window.open(authUrl, '_blank');
      attachDiv.append(img);
      const cap = citizenText('small', ` Attached: ${item.attachmentName || 'Photo'} (click to view full size)`, 'muted');
      attachDiv.append(cap);
      box.append(attachDiv);
    }

    if (item.completionOutcome) {
      const outcomeBox = citizenText('div', '', 'rp-callout');
      outcomeBox.style.margin = '8px 0';
      outcomeBox.innerHTML = `<strong>Completion Outcome:</strong> ${item.completionOutcome}`;
      box.append(outcomeBox);
    }

    const meta = citizenText('small', `Reported ${new Date(item.createdAt).toLocaleString('en-LK', {timeZone: 'Asia/Colombo'})} · Overall status: ${item.status}${item.verificationReason ? ' · Review note: ' + item.verificationReason : ''}`);
    box.append(meta);

    if (typeof item.latitude === 'number' && typeof item.longitude === 'number' && citizenMap) {
      const focus = citizenText('button', 'Show on map', 'quiet');
      focus.style.marginLeft = '8px';
      focus.onclick = () => citizenMap.focus(item);
      box.append(focus);
    }
    root.append(box);
  }

  if (citizenMap) {
    const count = citizenMap.update(citizenReports);
    citizenEl('citizen-map-message').textContent = `${count} of ${citizenReports.length} personal reports have mapped coordinates. Click elsewhere on the map to set coordinates.`;
  }
}

async function citizenRefresh() {
  citizenReports = (await citizenApi('/incident/list')).sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
  citizenRender();
}

citizenEl('citizen-report-form').onsubmit = async event => {
  event.preventDefault();
  const button = citizenEl('citizen-submit');
  button.disabled = true;
  citizenMessage('Submitting report…');
  try {
    const body = Object.fromEntries(new FormData(event.target));
    body.description = body.description.trim();
    body.location = body.location.trim();
    body.affectedPeople = Number(body.affectedPeople || 0);
    body.assistanceRequested = body.assistanceRequested === 'true';
    if (body.contactInfo) body.contactInfo = body.contactInfo.trim();

    Object.assign(body, citizenCoordinates());
    if (!('latitude' in body)) {
      delete body.latitude;
      delete body.longitude;
    }

    // If photograph is attached, upload first
    if (selectedPhoto) {
      citizenMessage('Uploading photograph…');
      const uploadResult = await citizenApi('/incident/upload', 'POST', selectedPhoto);
      body.attachmentUrl = uploadResult.url;
      body.attachmentName = uploadResult.originalName || selectedPhoto.filename;
    }

    const created = await citizenApi('/incident/create', 'POST', body);
    event.target.reset();
    renderPhotoPreview(null);
    citizenMap?.clearPin();
    citizenMessage(`Report submitted for coordinator review. Your reference: ${created.id}`);
    await citizenRefresh();
  } catch (err) {
    citizenMessage(err.message, true);
  } finally {
    button.disabled = false;
  }
};

citizenEl('citizen-gps').onclick = () => {
  if (!navigator.geolocation) {
    citizenMessage('Geolocation is not supported in this browser. Select a location on the map.', true);
    return;
  }
  citizenMessage('Requesting GPS location…');
  navigator.geolocation.getCurrentPosition(
    p => {
      const lat = Number(p.coords.latitude.toFixed(6));
      const lon = Number(p.coords.longitude.toFixed(6));
      citizenEl('citizen-latitude').value = lat;
      citizenEl('citizen-longitude').value = lon;
      citizenMap?.map.setView([lat, lon], 13);
      citizenMessage(`Location captured (${lat}, ${lon}). Confirm before submitting.`);
    },
    () => citizenMessage('Location permission denied or unavailable. Click a point on the map manually.', true),
    {timeout: 10000, maximumAge: 0, enableHighAccuracy: false}
  );
};

citizenEl('citizen-clear-pin').onclick = () => {
  citizenEl('citizen-latitude').value = '';
  citizenEl('citizen-longitude').value = '';
  citizenMap?.clearPin();
};

citizenEl('citizen-refresh').onclick = () => citizenRefresh().catch(e => citizenMessage(e.message, true));

citizenEl('citizen-logout').onclick = async () => {
  try { await citizenApi('/auth/logout', 'POST', {}); } catch {}
  for (const k of ['rp_token', 'rp_user', 'rp_role']) localStorage.removeItem(k);
  location.replace('/sign-in.html');
};

(async () => {
  if (!citizenToken) {
    location.replace('/sign-in.html');
    return;
  }
  try {
    const me = await citizenApi('/auth/me');
    if (me.role === 'admin') {
      location.replace('/admin-dashboard.html');
      return;
    }
    if (me.role !== 'citizen') {
      location.replace('/user-dashboard.html');
      return;
    }
    citizenEl('citizen-username').textContent = `Signed in as ${me.username} (Citizen)`;
    citizenMap = window.RescueMap?.create('citizen-map', {
      onPick: pos => {
        citizenEl('citizen-latitude').value = pos.latitude;
        citizenEl('citizen-longitude').value = pos.longitude;
        citizenEl('citizen-map-message').textContent = `Selected coordinates: ${pos.latitude.toFixed(5)}, ${pos.longitude.toFixed(5)}`;
      }
    });
    if (!citizenMap) {
      citizenEl('citizen-map-message').textContent = 'Map unavailable. You can enter coordinates manually.';
    }
    await citizenRefresh();
  } catch (e) {
    citizenMessage(e.message, true);
  }
})();

setInterval(() => {
  if (!document.hidden && !citizenEl('citizen-submit').disabled && citizenToken) {
    citizenRefresh().catch(() => {});
  }
}, 30000);
