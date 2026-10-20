"use strict";
const $ = id => document.getElementById(id);
let current = null, account = null, incidents = [], members = [], selectedIncident = null;
let page = 1, autoRefresh = true, refreshing = false;
let aiConfigured = false, aiHandover = null, lastAssessment = null;
const pageSize = 10;
const token = localStorage.getItem('rp_token');
function message(text, error = false) { $('message').textContent = text; $('message').className = error ? 'error' : ''; $('message').hidden = false; }
async function api(path, method = 'GET', body, timeout = 12000) {
  const response = await fetch(path, {method, headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token || ''}`}, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(timeout)});
  const data = await response.json();
  if (response.status === 401) { localStorage.removeItem('rp_token'); location.replace('/sign-in.html'); throw new Error('Session expired. Please sign in.'); }
  if (!response.ok) throw new Error(data.message || `Request failed (${response.status})`);
  return data;
}
function level(score) { return score >= .65 ? 'HIGH' : score >= .4 ? 'MEDIUM' : 'LOW'; }
function node(tag, text, className) { const el = document.createElement(tag); el.textContent = text; if (className) el.className = className; return el; }
function date(value) { const parsed = new Date(value); return Number.isNaN(parsed.getTime()) ? 'Not set' : parsed.toLocaleString('en-LK', {timeZone: 'Asia/Colombo', month:'short', day:'numeric', hour:'2-digit',minute:'2-digit'}); }
function overdue(incident) { return !incident.archived && incident.status !== 'RESOLVED' && incident.dueAt && new Date(incident.dueAt).getTime() < Date.now(); }
async function busy(button, action, output) { button.disabled = true; try { await action(); } catch (error) { if (output) output.textContent = error.message; else message(error.message || 'Unable to connect. Please try again.', true); } finally { button.disabled = false; } }
function filteredIncidents() {
 const query = $('incident-search').value.trim().toLowerCase();
 return incidents.filter(item => {
  const status = $('status-filter').value, severity = $('severity-filter').value, owner = $('owner-filter').value, archive = $('archive-filter').value;
  return (status === 'ALL' || item.status === status) && (severity === 'ALL' || item.severity === severity) &&
   (archive === 'ALL' || Boolean(item.archived) === (archive === 'ARCHIVED')) &&
   (owner === 'ALL' || (owner === 'MINE' && item.assignee === account?.username) || (owner === 'REPORTED' && item.reportedBy === account?.username) || (owner === 'UNASSIGNED' && !item.assignee)) &&
   (!query || [item.id,item.location,item.description,item.assignee,item.category].join(' ').toLowerCase().includes(query));
 });
}
function renderIncidents() {
 const rows = $('incident-rows'); rows.replaceChildren(); const filtered = filteredIncidents();
 const pageCount = Math.max(1, Math.ceil(filtered.length / pageSize)); page = Math.min(page,pageCount);
 $('empty').hidden = filtered.length !== 0;
 $('empty').textContent = incidents.length ? 'No incidents match these filters.' : 'No incidents yet. Report an observation to begin.';
 for (const inc of filtered.slice((page-1)*pageSize,page*pageSize)) {
  const row = node('tr',''); const locationCell = node('td',inc.location);
  locationCell.append(node('small',`${inc.id.replace('inc-','').slice(0,8).toUpperCase()} / ${inc.category || 'OTHER'}`),node('small',inc.description)); row.append(locationCell);
  for (const value of [inc.severity,inc.status]) { const cell = node('td',''); cell.append(node('span',value === 'ACK' ? 'ACKNOWLEDGED' : value,`pill ${value.toLowerCase()}`)); row.append(cell); }
  const assigned = node('td',inc.assignee || 'Unassigned'); assigned.append(node('small',inc.dueAt ? date(inc.dueAt) : 'No deadline',overdue(inc) ? 'overdue' : '')); row.append(assigned);
  const action = node('td',''); const button = node('button','View','quiet'); button.onclick = () => busy(button, () => openIncident(inc.id)); action.append(button); row.append(action); rows.append(row);
 }
 $('incident-total').textContent = incidents.filter(i => !i.archived).length;
 $('open-count').textContent = incidents.filter(i => !i.archived && i.status !== 'RESOLVED').length;
 $('resolved-count').textContent = incidents.filter(i => !i.archived && i.status === 'RESOLVED').length;
 $('overdue-count').textContent = incidents.filter(overdue).length;
 $('board-summary').textContent = `${filtered.length} matching records`;
 $('page-label').textContent = `Page ${page} of ${pageCount}`; $('page-prev').disabled = page <= 1; $('page-next').disabled = page >= pageCount;
}
function renderNotices(notices) {
 const feed = $('notifications'); feed.replaceChildren();
 const unread = notices.filter(item => !(item.readBy || []).includes(account.username)); $('unread-count').textContent = unread.length;
 if (!notices.length) feed.append(node('p','You are all caught up.','muted'));
 for (const item of notices.slice(-20).reverse()) {
  const read = (item.readBy || []).includes(account.username); const entry = node('div','',`activity-item ${read ? 'is-read' : ''}`);
  const heading = node('div','','notification-heading'); heading.append(node('strong',item.title));
  if (!read) { const button = node('button','Mark read','text-button'); button.onclick = () => busy(button,async () => { await api(`/notify/read/${encodeURIComponent(item.id)}`,'PUT',{}); await refresh(); }); heading.append(button); }
  entry.append(heading,node('p',item.body),node('small',`${date(item.createdAt)} | ${item.target === 'team' ? 'Workspace' : 'Direct update'}`));feed.append(entry);
 }
}
function riskFromReading(p) { return Math.max(0,Math.min(1,(p.rainMm/200)*.35+(p.windKph/120)*.25+((40-p.tempC)/40)*.15+(p.humidityPct/100)*.10+(p.soilSatPct/100)*.15)); }
async function refresh() {
 if (refreshing) return; refreshing = true;
 try {
  const identity=await api('/auth/me');if(identity.role==='admin'){location.replace('/admin-dashboard.html');return;}account=identity;
  const [list,stats,notices,weather] = await Promise.all([api('/incident/list'),api('/data/stats'),api('/notify/list'),api('/data/all')]);
  incidents = list.sort((a,b) => b.updatedAt.localeCompare(a.updatedAt));renderIncidents();$('observations').textContent = stats.count;renderNotices(notices);
  if (Array.isArray(weather) && weather.length) { const high = weather.reduce((a,b) => riskFromReading(b)>riskFromReading(a)?b:a);$('highest').textContent = `${Math.round(riskFromReading(high)*100)}/100`;$('highest-location').textContent = high.location; }
  $('connection').textContent = `Connected | updated ${new Date().toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}`;
 } finally { refreshing = false; }
}
function fillMemberSelect(select, allowTeam = false) {
 select.replaceChildren(new Option(allowTeam ? 'Entire workspace' : 'Unassigned',allowTeam ? 'team' : ''));
 for (const member of members) select.append(new Option(member.username,member.username));
}
function toLocalInput(iso) { if (!iso) return ''; const d = new Date(iso); if(Number.isNaN(d.getTime()))return ''; return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16); }
async function openIncident(id) {
 const inc = await api(`/incident/${encodeURIComponent(id)}`); selectedIncident = inc;
 aiHandover = null;
 $('ai-incident-output').hidden = true; $('ai-incident-output').replaceChildren();
 $('ai-handover-draft').hidden = true; $('ai-incident').disabled = !aiConfigured;
 $('ai-incident-status').textContent = aiConfigured ? 'Ready to generate a briefing for this report.' : 'AI assistance is not configured.';
 $('detail-title').textContent = inc.location; $('detail-id').textContent = inc.id;
 $('detail-meta').textContent = `Reported by ${inc.reportedBy || 'Legacy report'} | ${date(inc.createdAt)} | ${inc.status}${inc.archived ? ' | Archived' : ''}`;
 $('detail-description').textContent = inc.description; $('detail-message').textContent = '';
 const canManage = account.role === 'admin' || inc.assignee === account.username;
 const detailForm = $('detail-form'); detailForm.hidden = !canManage || inc.archived;
 for(const key of ['location','category','severity','status','description','assignee']) detailForm.elements[key].value = inc[key] || (key === 'category' ? 'OTHER' : '');
 detailForm.elements.dueAt.value = toLocalInput(inc.dueAt);
 $('assignment-field').hidden = $('deadline-field').hidden = account.role !== 'admin';
 $('archive-incident').hidden = account.role !== 'admin' || inc.status !== 'RESOLVED';
 // Archived records still expose a separate restore action.
 $('restore-incident')?.remove();
 if (inc.archived && account.role === 'admin') { const restore = node('button','Restore incident','primary');restore.id = 'restore-incident';restore.onclick = () => busy(restore,async () => {await api(`/incident/${encodeURIComponent(inc.id)}`,'PATCH',{revision:inc.revision,archived:false});await openIncident(inc.id);await refresh();},$('detail-message'));$('detail-description').after(restore); }
 const notes = $('detail-notes');notes.replaceChildren();
 if (!inc.notes?.length) notes.append(node('p','No response notes yet.','muted'));
 for(const note of (inc.notes || []).slice().reverse()) {const entry = node('div','','activity-item');entry.append(node('strong',note.author),node('p',note.text),node('small',date(note.createdAt)));notes.append(entry);}
 const history = $('detail-history');history.replaceChildren();
 for(const event of (inc.history || []).slice(-30).reverse()) {const entry = node('div','','activity-item');entry.append(node('p',event.action),node('small',`${event.actor} | ${date(event.createdAt)}`));history.append(entry);}
 $('note-form').hidden = inc.archived;$('note-form').reset();
 if (!$('incident-dialog').open) $('incident-dialog').showModal();
}
$('detail-form').onsubmit = event => {event.preventDefault();busy(event.submitter,async () => {
 const values = Object.fromEntries(new FormData(event.target));
 if(account.role !== 'admin') {delete values.assignee;delete values.dueAt;} else {values.dueAt = values.dueAt ? new Date(values.dueAt).toISOString() : '';}
 const updated = await api(`/incident/${encodeURIComponent(selectedIncident.id)}`,'PATCH',{...values,revision:selectedIncident.revision});
 await openIncident(updated.id);await refresh();$('detail-message').textContent = 'Changes saved.';
},$('detail-message'));};
$('archive-incident').onclick = () => busy($('archive-incident'),async () => {const inc=selectedIncident;await api(`/incident/${encodeURIComponent(inc.id)}`,'PATCH',{revision:inc.revision,archived:true});$('incident-dialog').close();await refresh();message('Incident archived. Find it under Archived records.');},$('detail-message'));
$('note-form').onsubmit = event => {event.preventDefault();busy(event.submitter,async () => {const updated = await api(`/incident/${encodeURIComponent(selectedIncident.id)}/notes`,'POST',Object.fromEntries(new FormData(event.target)));await openIncident(updated.id);await refresh();},$('detail-message'));};
function renderAiBrief(target, result) {
 target.replaceChildren();
 target.append(node('h4','Summary'),node('p',result.brief.summary));
 for(const [title,key] of [['Suggested next steps','suggestedActions'],['Information to verify','missingInformation']]) {
  target.append(node('h4',title));const list=node('ul','');for(const item of result.brief[key])list.append(node('li',item));
  if(!result.brief[key].length)list.append(node('li','No additional items identified.'));target.append(list);
 }
 target.append(node('h4','Handover draft'),node('p',result.brief.handover),node('small',`${result.provider} | ${date(result.generatedAt)} | Review before using`));target.hidden=false;
}
async function loadAiStatus() {
 try { const status=await api('/assistant/status');aiConfigured=status.configured===true&&status.enabled!==false; }
 catch {aiConfigured=false;}
 $('ai-incident').disabled=!aiConfigured;$('ai-weather').disabled=!aiConfigured||!lastAssessment;
 $('ai-incident-status').textContent=aiConfigured?'Ready to generate a briefing.':'AI assistance is not configured.';
 if(!aiConfigured)$('ai-weather-status').textContent='AI assistance is unavailable. Contact your coordinator.';
}
$('ai-incident').onclick=()=>busy($('ai-incident'),async()=>{
 const source=selectedIncident;if(!source)return;
 $('ai-incident-status').textContent='Generating briefing...';$('ai-incident-output').hidden=true;$('ai-handover-draft').hidden=true;
 const result=await api(`/assistant/incidents/${encodeURIComponent(source.id)}/brief`,'POST',{},45000);
 if(!selectedIncident||selectedIncident.id!==source.id||!$('incident-dialog').open)return;
 renderAiBrief($('ai-incident-output'),result);
 if(result.sourceRevision!==selectedIncident.revision){$('ai-incident-status').textContent='The incident changed while this brief was generated. Generate a fresh briefing before using it.';aiHandover=null;return;}
 aiHandover={incidentId:source.id,revision:result.sourceRevision,text:result.brief.handover};
 $('ai-handover-draft').hidden=source.archived;$('ai-incident-status').textContent='Briefing ready. Check the suggestions before acting.';
},$('ai-incident-status'));
$('ai-handover-draft').onclick=()=>{
 if(!aiHandover||aiHandover.incidentId!==selectedIncident?.id||aiHandover.revision!==selectedIncident?.revision)return;
 $('note-form').elements.text.value=('[Gemini draft - review before posting] '+aiHandover.text).slice(0,2000);
 $('note-form').elements.text.focus();$('note-form').scrollIntoView({block:'nearest'});
};
$('ai-weather').onclick=()=>busy($('ai-weather'),async()=>{
 const source=lastAssessment;if(!source)return;$('ai-weather-status').textContent='Explaining observations...';$('ai-weather-output').hidden=true;
 const result=await api('/assistant/weather/explain','POST',{location:source.location,...source.values},45000);
 if(lastAssessment!==source)return;renderAiBrief($('ai-weather-output'),result);$('ai-weather-status').textContent='Explanation ready. This does not replace a verified forecast.';
},$('ai-weather-status'));
$('detail-close').onclick = () => $('incident-dialog').close();
const form = $('risk-form');
form.addEventListener('submit',event => {event.preventDefault();busy(event.submitter,async () => {
 const values = Object.fromEntries(new FormData(form));const location = values.location;delete values.location;for(const key of Object.keys(values))values[key]=Number(values[key]);
 const prediction = await api('/ai/predict','POST',values);await api('/data/ingest','POST',{...values,location,timestamp:new Date().toISOString()});
 current = {location,score:prediction.riskScore,values:{...values}};lastAssessment=current;const score = Math.round(current.score*100), risk=level(current.score);
 $('risk-score').textContent=score;$('risk-badge').textContent=risk;$('risk-title').textContent=`${location} | ${risk === 'MEDIUM' ? 'Moderate' : risk === 'HIGH' ? 'High' : 'Low'} risk index`;
 $('risk-detail').textContent=risk === 'HIGH' ? 'Above the review threshold. Verify conditions and create an incident if response work is needed.' : 'Below the high-risk threshold. Continue monitoring and record observed incidents.';
 $('gauge').style.background=`conic-gradient(${risk==='HIGH'?'#ff845f':risk==='MEDIUM'?'#e9c576':'#72d4b9'} ${score}%,#253245 ${score}%)`;$('create-from-risk').disabled=false;$('ai-weather').disabled=!aiConfigured;$('ai-weather-output').hidden=true;$('ai-weather-status').textContent=aiConfigured?'Ready to explain these observations.':'AI assistance is not configured.';
 if(risk==='HIGH')await api('/notify/publish','POST',{channel:'in-app',target:account.username,title:`Risk assessment: ${location}`,body:`Risk index ${score}/100 from manual observations. Verify conditions before acting.`});
 await refresh();message('Assessment saved.');
});});
$('create-from-risk').onclick=()=>busy($('create-from-risk'),async()=>{if(!current)return;const result=await api('/incident/create','POST',{location:current.location,description:`Weather assessment: risk index ${Math.round(current.score*100)}/100. Conditions require field verification.`,severity:level(current.score),category:'STORM'});current=null;await refresh();await openIncident(result.id);message('Incident created.');}).then(()=>{$('create-from-risk').disabled=!current;});
$('report-toggle').onclick=()=>{$('incident-form').hidden=!$('incident-form').hidden;};
$('incident-form').onsubmit=event=>{event.preventDefault();busy(event.submitter,async()=>{const values=Object.fromEntries(new FormData(event.target));await api('/incident/create','POST',values);event.target.reset();event.target.hidden=true;page=1;await refresh();message('Incident reported.');});};
for(const id of ['status-filter','severity-filter','owner-filter','archive-filter'])$(id).onchange=()=>{page=1;renderIncidents();};
$('incident-search').oninput=()=>{page=1;renderIncidents();};
$('page-prev').onclick=()=>{page--;renderIncidents();};$('page-next').onclick=()=>{page++;renderIncidents();};
$('refresh').onclick=()=>busy($('refresh'),refresh);
$('auto-refresh').onclick=()=>{autoRefresh=!autoRefresh;$('auto-refresh').textContent=`Auto-refresh ${autoRefresh?'on':'off'}`;$('auto-refresh').setAttribute('aria-pressed',String(autoRefresh));};
function csvCell(value) {let text=String(value??'');if(/^[=+@-]/.test(text.trimStart())||/^[\t\r]/.test(text))text="'"+text;return '"'+text.replace(/"/g,'""')+'"';}
$('export-csv').onclick=()=>{const items=filteredIncidents();if(!items.length){message('No matching records to export.');return;}const fields=['id','location','category','description','severity','status','reportedBy','assignee','dueAt','createdAt','updatedAt','archived'];const csv=[fields.join(','),...items.map(item=>fields.map(key=>csvCell(item[key])).join(','))].join('\r\n');const url=URL.createObjectURL(new Blob(['\uFEFF'+csv],{type:'text/csv;charset=utf-8'}));const link=document.createElement('a');link.href=url;link.download=`rescuepulse-incidents-${new Date().toISOString().slice(0,10)}.csv`;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);message(`Exported ${items.length} incident records.`);};
$('notification-form').onsubmit=event=>{event.preventDefault();busy(event.submitter,async()=>{await api('/notify/publish','POST',{...Object.fromEntries(new FormData(event.target)),channel:'in-app'});event.target.reset();await refresh();message('Workspace notification sent.');});};
$('account-open').onclick=()=>{$('account-identity').textContent=`${account.username} | ${account.role==='admin'?'Coordinator':'Responder'}`;$('password-message').textContent='';$('password-form').reset();$('account-dialog').showModal();};
$('account-close').onclick=()=>$('account-dialog').close();
$('password-form').onsubmit=event=>{event.preventDefault();busy(event.submitter,async()=>{const values=Object.fromEntries(new FormData(event.target));if(values.newPassword!==values.confirmPassword)throw new Error('New passwords do not match.');delete values.confirmPassword;await api('/auth/password','PUT',values);clearSession();location.assign('/sign-in.html');},$('password-message'));};
function clearSession(){['rp_token','rp_user','rp_role'].forEach(key=>localStorage.removeItem(key));}
$('logout').onclick=async()=>{try{await api('/auth/logout','POST',{});}catch{}clearSession();location.replace('/sign-in.html');};$('mobile-logout').onclick=()=>$('logout').click();
function tick(){$('clock').textContent=new Date().toLocaleString('en-LK',{timeZone:'Asia/Colombo',dateStyle:'medium',timeStyle:'short'});}tick();setInterval(tick,30000);
setInterval(()=>{if(autoRefresh&&account&&!document.hidden&&!$('incident-dialog').open&&!$('account-dialog').open&&!refreshing)refresh().catch(error=>{$('connection').textContent='Refresh unavailable';message(error.message,true);});},30000);
(async()=>{if(!token){location.replace('/sign-in.html');return;}try{account=await api('/auth/me');if(account.role==='admin'){location.replace('/admin-dashboard.html');return;}$('identity').textContent=`${account.username} | ${account.role==='admin'?'Coordinator':'Responder'}`;$('admin-link').hidden=account.role!=='admin';$('notification-form').hidden=account.role!=='admin';const directory=await api('/operations/members');members=directory.members;await loadAiStatus();fillMemberSelect($('detail-assignee'));fillMemberSelect($('notification-target'),true);await refresh();}catch(error){$('connection').textContent='Connection unavailable';message(error.message,true);}})();
