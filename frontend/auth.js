"use strict";

const form = document.getElementById('auth-form');

if (form) {
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const button = form.querySelector('button[type="submit"]');
    const message = document.getElementById('auth-message');
    if (button) button.disabled = true;
    if (message) {
      message.textContent = 'Authenticating…';
      message.className = 'muted';
    }
    try {
      const body = Object.fromEntries(new FormData(form));
      const response = await fetch(`/auth/${form.dataset.action}`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(15000)
      });
      const data = await response.json();
      if (!response.ok || data.status !== 'ok') throw new Error(data.message || 'Unable to complete request.');
      if (form.dataset.action === 'signup') {
        if (message) message.textContent = 'Account created. Opening sign in…';
        location.assign('/sign-in.html');
      } else {
        localStorage.setItem('rp_token', data.token);
        localStorage.setItem('rp_role', data.role);
        localStorage.setItem('rp_user', data.username);
        location.assign(data.role === 'admin' ? '/admin-dashboard.html' : data.role === 'citizen' ? '/citizen.html' : '/user-dashboard.html');
      }
    } catch (error) {
      if (message) {
        message.textContent = error.message || 'Connection failed. Check that Ballerina is running.';
        message.className = 'error';
      }
    } finally {
      if (button) button.disabled = false;
    }
  });
}

if (form && form.dataset.action === 'signup') {
  fetch('/auth/registration')
    .then(response => response.json())
    .then(settings => {
      if (!settings.enabled) {
        const btn = form.querySelector('button[type="submit"]');
        if (btn) btn.disabled = true;
        const msg = document.getElementById('auth-message');
        if (msg) msg.textContent = 'Public registration is closed. Contact your administrator for an account.';
      }
    })
    .catch(() => {});
}

// Choreo Identity Platform (OpenID Connect PKCE Flow)
function base64url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function randomString(length = 48) {
  const array = new Uint8Array(length);
  crypto.getRandomValues(array);
  return base64url(array);
}

async function sha256(plain) {
  const encoder = new TextEncoder();
  const data = encoder.encode(plain);
  return await crypto.subtle.digest('SHA-256', data);
}

const choreoBtn = document.getElementById('choreo-login-btn');
const choreoStatus = document.getElementById('choreo-status');

if (choreoBtn || choreoStatus) {
  // Check if Choreo is configured in backend
  fetch('/auth/choreo/config')
    .then(r => r.json())
    .then(config => {
      if (config.enabled) {
        const badge = document.getElementById('choreo-badge');
        if (badge) badge.textContent = `Choreo SSO Active (${config.organization})`;
      } else {
        if (choreoStatus) {
          choreoStatus.textContent = 'Choreo Identity: Configure choreoClientId and choreoBaseUrl in Config.toml to activate.';
        }
      }
    })
    .catch(() => {
      if (choreoStatus) choreoStatus.textContent = 'Identity configuration unavailable.';
    });
}

if (choreoBtn) {
  choreoBtn.onclick = async () => {
    try {
      choreoBtn.disabled = true;
      choreoBtn.textContent = 'Preparing secure SSO redirect…';
      const config = await (await fetch('/auth/choreo/config')).json();
      if (!config.enabled) {
        alert('Choreo Identity Platform application is prepared, but Client ID and Base URL have not been entered in Config.toml yet.');
        choreoBtn.disabled = false;
        choreoBtn.innerHTML = '<span>🌐</span> Sign in with Choreo Identity';
        return;
      }
      const codeVerifier = randomString(64);
      const challengeBuffer = await sha256(codeVerifier);
      const codeChallenge = base64url(challengeBuffer);
      const state = randomString(32);
      const nonce = randomString(32);

      sessionStorage.setItem('choreo_verifier', codeVerifier);
      sessionStorage.setItem('choreo_state', state);
      sessionStorage.setItem('choreo_nonce', nonce);

      const authUrl = new URL(`${config.baseUrl}/oauth2/authorize`);
      authUrl.searchParams.set('response_type', 'code');
      authUrl.searchParams.set('client_id', config.clientId);
      authUrl.searchParams.set('scope', config.scope || 'openid profile');
      authUrl.searchParams.set('redirect_uri', config.redirectUri || 'http://localhost:8080/');
      authUrl.searchParams.set('state', state);
      authUrl.searchParams.set('code_challenge', codeChallenge);
      authUrl.searchParams.set('code_challenge_method', 'S256');
      authUrl.searchParams.set('nonce', nonce);

      location.assign(authUrl.toString());
    } catch (e) {
      alert('Could not start Choreo login: ' + e.message);
      choreoBtn.disabled = false;
      choreoBtn.innerHTML = '<span>🌐</span> Sign in with Choreo Identity';
    }
  };
}

// OAuth Callback Handler (handles redirect back from Choreo at / or sign-in)
(async () => {
  const params = new URLSearchParams(window.location.search);
  const code = params.get('code');
  const state = params.get('state');

  if (code && state) {
    const expectedState = sessionStorage.getItem('choreo_state');
    const verifier = sessionStorage.getItem('choreo_verifier');
    sessionStorage.removeItem('choreo_state');
    sessionStorage.removeItem('choreo_verifier');

    if (!expectedState || state !== expectedState) {
      console.warn('OAuth state mismatch or expired.');
      return;
    }

    // Show friendly overlay banner
    const notice = document.createElement('div');
    notice.style.position = 'fixed';
    notice.style.top = '20px';
    notice.style.left = '50%';
    notice.style.transform = 'translateX(-50%)';
    notice.style.background = '#1e3a8a';
    notice.style.color = '#ffffff';
    notice.style.padding = '12px 24px';
    notice.style.borderRadius = '8px';
    notice.style.boxShadow = '0 10px 30px rgba(0,0,0,0.5)';
    notice.style.zIndex = '9999';
    notice.style.fontSize = '14px';
    notice.innerHTML = '<span style="display:inline-block;animation:spin 1s linear infinite;margin-right:8px;">⏳</span> Completing Choreo Enterprise authentication…';
    document.body.appendChild(notice);

    try {
      // Exchange with backend
      const res = await fetch('/auth/choreo/login', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({idToken: code, username: 'choreo-citizen'})
      });
      const data = await res.json();
      if (res.ok && data.status === 'ok') {
        localStorage.setItem('rp_token', data.token);
        localStorage.setItem('rp_role', data.role);
        localStorage.setItem('rp_user', data.username);
        // Clean URL
        window.history.replaceState({}, document.title, window.location.pathname);
        location.assign(data.role === 'admin' ? '/admin-dashboard.html' : data.role === 'citizen' ? '/citizen.html' : '/user-dashboard.html');
      } else {
        notice.style.background = '#991b1b';
        notice.textContent = data.message || 'Choreo authentication failed.';
        setTimeout(() => notice.remove(), 4000);
      }
    } catch (e) {
      console.error('Choreo exchange error:', e);
      notice.style.background = '#991b1b';
      notice.textContent = 'Connection error during authentication.';
      setTimeout(() => notice.remove(), 4000);
    }
  }
})();
