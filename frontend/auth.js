"use strict";
const form = document.getElementById('auth-form');
form.addEventListener('submit', async event => {
 event.preventDefault(); const button = form.querySelector('button'); const message = document.getElementById('auth-message'); button.disabled = true; message.textContent = 'Please wait…';
 try {
  const body = Object.fromEntries(new FormData(form));
  const response = await fetch(`/auth/${form.dataset.action}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const data = await response.json(); if (!response.ok || data.status !== 'ok') throw new Error(data.message || 'Unable to complete request.');
  if(form.dataset.action === 'signup') { message.textContent = 'Account created. Opening sign in…'; location.assign('/sign-in.html'); }
  else { localStorage.setItem('rp_token',data.token);localStorage.setItem('rp_role',data.role);localStorage.setItem('rp_user',data.username);location.assign(data.role === 'admin' ? '/admin-dashboard.html' : '/user-dashboard.html'); }
 } catch(error) { message.textContent = error.message || 'Connection failed. Check that Ballerina is running.'; } finally { button.disabled = false; }
});

if(form.dataset.action === 'signup') {
 fetch('/auth/registration').then(response=>response.json()).then(settings=>{if(!settings.enabled){form.querySelector('button').disabled=true;document.getElementById('auth-message').textContent='Public registration is closed. Contact your administrator for an account.';}}).catch(()=>{});
}
