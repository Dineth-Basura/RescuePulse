function escapeHTML(value) { return String(value).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;", "'":"&#39;"}[c])); }
// Minimal client-side calls to the Ballerina backend under same origin
async function predictSample() {
  const payload = { rainMm: 12.3, windKph: 10, tempC: 29, humidityPct: 70, soilSatPct: 50 };
  const res = await fetch('/ai/predict', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  return await res.json();
}

function initUI() {
  // Wire control panel buttons if present
  const out = document.getElementById('control-output');
  function renderKV(label, value){
    label = escapeHTML(label); value = escapeHTML(value);
    return `<div class="flex justify-between gap-2 py-1 border-b border-white/10"><span class="text-white/70">${label}</span><span class="font-mono">${value}</span></div>`;
  }
  function renderList(title, items){
    const rows = items.map((it)=>`<li class="py-1 border-b border-white/10">${escapeHTML(typeof it==='string'?it:JSON.stringify(it))}</li>`).join('');
    return `<div class="mt-2"><div class="font-semibold mb-1">${title}</div><ul>${rows}</ul></div>`;
  }
  function renderBadge(text, color){
    const colorMap = {
      green: 'bg-green-500/20 text-green-300 border-green-500/30',
      yellow: 'bg-yellow-500/20 text-yellow-300 border-yellow-500/30',
      red: 'bg-rose-500/20 text-rose-300 border-rose-500/30',
      gray: 'bg-white/10 text-white/70 border-white/20'
    };
    const cls = colorMap[color] || colorMap.gray;
    return `<span class="px-2 py-0.5 rounded text-[10px] border ${cls}">${text}</span>`;
  }
  function renderIncidents(title, items){
    const head = `<thead class="text-white/60 border-b border-white/10"><tr><th class="py-2 text-left">ID</th><th class="py-2 text-left">Location</th><th class="py-2 text-left">Severity</th><th class="py-2 text-left">Status</th><th class="py-2 text-left">Updated</th></tr></thead>`;
    const body = items.map(it=>{
      const sevColor = it.severity === 'HIGH' || it.severity === 'CRITICAL' ? 'red' : it.severity === 'MEDIUM' ? 'yellow' : 'green';
      const stColor = it.status === 'OPEN' ? 'red' : it.status === 'ACK' ? 'yellow' : 'green';
      return `<tr class="border-b border-white/10">
        <td class="py-1 font-mono text-white/80">${escapeHTML(it.id)}</td>
        <td class="py-1">${escapeHTML(it.location)}</td>
        <td class="py-1">${renderBadge(it.severity, sevColor)}</td>
        <td class="py-1">${renderBadge(it.status, stColor)}</td>
        <td class="py-1 text-white/60">${escapeHTML(it.updatedAt || '')}</td>
      </tr>`;
    }).join('');
    return `<div class="mt-2"><div class="font-semibold mb-2">${title}</div><table class="w-full text-xs">${head}<tbody>${body}</tbody></table></div>`;
  }
  const show = (label, data) => {
    if (!out) return;
    try {
      if (data && typeof data === 'object') {
        // Heuristics per endpoint
        if (Array.isArray(data)) {
          // Detect incident-like objects and render a table
          const isIncidentArray = data.length > 0 && typeof data[0] === 'object' && data[0] !== null && 'id' in data[0] && 'location' in data[0] && 'status' in data[0];
          if (isIncidentArray) {
            out.innerHTML = renderIncidents('Incidents', data);
          } else {
            out.innerHTML = renderList(label, data);
          }
        } else if (data.users || data.locations) {
          const list = data.users || data.locations || [];
          out.innerHTML = renderList(label, list);
        } else if (data.count !== undefined && (data.avgRainMm !== undefined || data.avgWindKph !== undefined)) {
          out.innerHTML = `
            <div class="font-semibold mb-1">${label}</div>
            ${renderKV('Count', data.count)}
            ${renderKV('Avg Rain (mm)', Number(data.avgRainMm).toFixed(2))}
            ${renderKV('Avg Wind (kph)', Number(data.avgWindKph).toFixed(2))}
            ${renderKV('Avg Temp (°C)', Number(data.avgTempC).toFixed(2))}
            ${renderKV('Avg Humidity (%)', Number(data.avgHumidityPct).toFixed(2))}
            ${renderKV('Avg Soil (%)', Number(data.avgSoilSatPct).toFixed(2))}
          `;
        } else if (data.riskScore !== undefined) {
          out.innerHTML = `
            <div class="font-semibold mb-1">${label}</div>
            ${renderKV('Risk Score', Number(data.riskScore).toFixed(3))}
          `;
        } else if (data.status && data.status === 'stored' && data.count !== undefined) {
          out.innerHTML = `${renderKV('Batch Stored', data.count)}`;
        } else if (data.status && (data.status === 'stored' || data.status === 'ok' || data.status === 'deleted')) {
          out.innerHTML = `${renderKV('Status', data.status)}`;
        } else if (data.id && data.location && data.status) {
          out.innerHTML = `
            <div class="font-semibold mb-1">Incident</div>
            ${renderKV('ID', data.id)}
            ${renderKV('Location', data.location)}
            ${renderKV('Severity', data.severity)}
            ${renderKV('Status', data.status)}
          `;
        } else {
          out.innerHTML = `<div class="font-semibold mb-1">${label}</div><pre class="whitespace-pre-wrap">${escapeHTML(JSON.stringify(data, null, 2))}</pre>`;
        }
      } else if (typeof data === 'string') {
        out.innerHTML = `<div class="font-semibold mb-1">${label}</div><pre class="whitespace-pre-wrap">${escapeHTML(data)}</pre>`;
      } else {
        out.innerHTML = `<div class="font-semibold mb-1">${label}</div><pre class="whitespace-pre-wrap">${String(data)}</pre>`;
      }
    } catch (e) {
      out.innerHTML = `<div class="text-rose-400">Render error: ${e?.message || e}</div>`;
    }
  };
  const on = (id, fn, label) => { const el = document.getElementById(id); if (el) el.addEventListener('click', async (e) => { e.preventDefault(); try { const res = await fn(); show(label || id, res); } catch (err) { show('error', { message: err?.message || String(err) }); } }); };

  on('btn-data-stats', () => window.api.data.stats());
  on('btn-data-ingest', () => window.api.data.ingest({ rainMm: 12, windKph: 6, tempC: 29, humidityPct: 60, soilSatPct: 50, location: 'LOC-DEMO', timestamp: 'now' }));
  on('btn-ai-predict', () => window.api.ai.predict({ rainMm: 20, windKph: 10, tempC: 30, humidityPct: 60, soilSatPct: 50 }));
  on('btn-analytics-sum', () => window.api.analytics.summarize([{ rainMm: 10, windKph: 5, tempC: 28, humidityPct: 55, soilSatPct: 40 }]));
  on('btn-incident-create', () => window.api.incident.create({ id: '', location: 'LOC-DEMO', description: 'Test event', severity: 'LOW', status: 'OPEN', createdAt: '', updatedAt: '' }));
  on('btn-incident-list', () => window.api.incident.list(), 'Incidents');
  on('btn-notify-publish', () => window.api.notify.publish({ id: '', channel: 'in-app', target: 'team', title: 'Hello', body: 'From UI', createdAt: '' }));
  on('btn-notify-list', () => window.api.notify.list());
  on('btn-admin-users', () => window.api.admin.users());
  on('btn-admin-logs', () => window.api.admin.logs('login.txt'));
}

if (document.readyState === 'loading') {
  window.addEventListener('DOMContentLoaded', initUI);
} else {
  initUI();
}


// Lightweight JS client for backend endpoints (no extra HTML needed)
const apiBase = '';

function authHeaders() {
  try {
    const token = localStorage.getItem('rp_token') || '';
    return token ? { 'Authorization': 'Bearer ' + token } : {};
  } catch (_) { return {}; }
}

async function httpGet(path) {
  const res = await fetch(apiBase + path, { headers: { 'Accept': 'application/json', ...authHeaders() } });
  if (!res.ok) throw new Error('GET ' + path + ' failed: ' + res.status);
  const ct = res.headers.get('content-type') || '';
  if (ct.includes('application/json')) return await res.json();
  return await res.text();
}

async function httpPost(path, body) {
  const res = await fetch(apiBase + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', ...authHeaders() },
    body: JSON.stringify(body || {})
  });
  if (!res.ok) throw new Error('POST ' + path + ' failed: ' + res.status);
  return await res.json();
}

async function httpPut(path, body) {
  const res = await fetch(apiBase + path, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', ...authHeaders() },
    body: JSON.stringify(body || {})
  });
  if (!res.ok) throw new Error('PUT ' + path + ' failed: ' + res.status);
  return await res.json();
}

async function httpDelete(path) {
  const res = await fetch(apiBase + path, { method: 'DELETE', headers: { 'Accept': 'application/json', ...authHeaders() } });
  if (!res.ok) throw new Error('DELETE ' + path + ' failed: ' + res.status);
  return await res.json();
}

// Expose a single API surface on window for console or optional UI hooks
window.api = {
  // auth
  auth: {
    signup: (username, password) => httpPost('/auth/signup', { username, password }),
    login: (username, password) => httpPost('/auth/login', { username, password }),
    health: () => httpGet('/auth/health')
  },
  // ai
  ai: {
    predict: (p) => httpPost('/ai/predict', p),
    train: (rows) => httpPost('/ai/train', rows),
    health: () => httpGet('/ai/health')
  },
  // data ingest and analytics
  data: {
    ingest: (rec) => httpPost('/data/ingest', rec),
    ingestBatch: (recs) => httpPost('/data/ingestBatch', recs),
    latest: (location) => httpGet('/data/latest/' + encodeURIComponent(location)),
    locations: () => httpGet('/data/locations'),
    all: () => httpGet('/data/all'),
    stats: () => httpGet('/data/stats'),
    health: () => httpGet('/data/health')
  },
  analytics: {
    summarize: (points) => httpPost('/analytics/summarize', { points }),
    health: () => httpGet('/analytics/health')
  },
  incident: {
    create: (inc) => httpPost('/incident/create', inc),
    update: (id, inc) => httpPut('/incident/update/' + encodeURIComponent(id), inc),
    get: (id) => httpGet('/incident/' + encodeURIComponent(id)),
    list: () => httpGet('/incident/list'),
    delete: (id) => httpDelete('/incident/' + encodeURIComponent(id)),
    health: () => httpGet('/incident/health')
  },
  notify: {
    publish: (n) => httpPost('/notify/publish', n),
    list: () => httpGet('/notify/list'),
    for: (target) => httpGet('/notify/for/' + encodeURIComponent(target)),
    health: () => httpGet('/notify/health')
  },
  admin: {
    logs: (file) => httpGet('/admin/logs/' + encodeURIComponent(file)),
    users: () => httpGet('/admin/users'),
    health: () => httpGet('/admin/health')
  },
  // small helpers to demo flows entirely from JS/console
  demo: {
    async simulateFlow() {
      const loc = 'LOC-DEMO';
      await window.api.data.ingest({ rainMm: 20, windKph: 10, tempC: 30, humidityPct: 60, soilSatPct: 50, location: loc, timestamp: 'now' });
      const stats = await window.api.data.stats();
      const latest = await window.api.data.latest(loc);
      const risk = await window.api.ai.predict({ rainMm: 20, windKph: 10, tempC: 30, humidityPct: 60, soilSatPct: 50 });
      const alertNeeded = risk.riskScore >= 0.65;
      if (alertNeeded) {
        await window.api.notify.publish({ id: '', channel: 'in-app', target: 'team', title: 'High Risk', body: 'Risk=' + risk.riskScore, createdAt: '' });
      }
      return { stats, latest, risk };
    }
  }
};