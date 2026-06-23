// Drives the FS25 dedicated-server web portal over HTTP.
//
//   node start-game.mjs          -> log in, read the settings form, POST "Start"
//   node start-game.mjs --stop   -> log in, POST "Stop"
//
// The dedicatedServer.exe only exposes a web UI; there is no CLI to start the
// actual game session, so we replicate what clicking "Start" in the browser does:
// log in, read every field currently on the settings form, and submit them back
// unchanged plus the start (or stop) button. Reading all fields generically keeps
// this working across game versions that add/rename settings.
import http from 'http';

// The portal binds to the container network IP, not loopback; start.sh exports it.
const HOST = `${process.env.WEB_HOST || '127.0.0.1'}:${process.env.WEB_PORT || '7999'}`;
const USERNAME = process.env.WEB_USERNAME || 'admin';
const PASSWORD = process.env.WEB_PASSWORD || 'changeme';
const STOP = process.argv.includes('--stop');

function encode(data) {
  return Object.entries(data)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v).replace(/%20/g, '+')}`)
    .join('&');
}

function request(method, data = {}, cookie = '') {
  let path = '/index.html?lang=en';
  const headers = { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'fs25-egg/1.0' };
  if (cookie) headers['Cookie'] = cookie;
  const body = encode(data);
  if (method === 'POST') headers['Content-Length'] = Buffer.byteLength(body);
  if (method === 'GET' && body) path += '&' + body;

  return new Promise((resolve, reject) => {
    const req = http.request(`http://${HOST}${path}`, { method, headers }, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: buf }));
    });
    req.on('error', reject);
    if (method === 'POST') req.write(body);
    req.end();
  });
}

// Log in: POST credentials, the SessionID cookie is returned on this response.
async function login() {
  const res = await request('POST', { username: USERNAME, password: PASSWORD, login: 'Login' });
  for (const c of res.headers['set-cookie'] || []) {
    const m = /(SessionID=[^;]+)/i.exec(c);
    if (m) return m[1];
  }
  throw new Error('login failed (no SessionID cookie) — check WEB_USERNAME/WEB_PASSWORD');
}

// Read every settings field so we can resubmit the form as-is.
function scrapeForm(html) {
  const params = {};

  // Text/hidden/password/number inputs -> keep name=value.
  // Checkboxes -> "on" if checked, else "off" (FS expects explicit crossplay state).
  const inputRe = /<input\b[^>]*>/gi;
  let m;
  while ((m = inputRe.exec(html))) {
    const tag = m[0];
    const name = (/name="([^"]*)"/i.exec(tag) || [])[1];
    const type = ((/type="([^"]*)"/i.exec(tag) || [])[1] || 'text').toLowerCase();
    if (!name) continue;
    if (type === 'submit' || type === 'button') continue;
    if (type === 'checkbox') {
      params[name] = /\bchecked\b/i.test(tag) ? 'on' : 'off';
    } else {
      params[name] = (/value="([^"]*)"/i.exec(tag) || [, ''])[1];
    }
  }

  // Selects -> the selected option value (fallback: first option).
  const selectRe = /<select\b[^>]*name="([^"]*)"[^>]*>([\s\S]*?)<\/select>/gi;
  while ((m = selectRe.exec(html))) {
    const name = m[1];
    const block = m[2];
    const sel = /<option\s+value="([^"]*)"[^>]*\bselected\b/i.exec(block);
    const first = /<option\s+value="([^"]*)"/i.exec(block);
    if (sel) params[name] = sel[1];
    else if (first) params[name] = first[1];
  }

  return params;
}

async function run() {
  const cookie = await login();
  const page = await request('GET', {}, cookie);

  if (STOP) {
    await request('POST', { stop_server: 'Stop' }, cookie);
    console.log('[fs25] Game session stop requested.');
    return;
  }

  const params = scrapeForm(page.body);
  if (!('game_name' in params)) throw new Error('settings form not found (not logged in?)');
  delete params.save_settings; // do not trigger the "Save" button
  params.start_server = 'Start';

  await request('POST', params, cookie);
  console.log('[fs25] Game session start requested.');
}

run().catch((e) => {
  console.error('[fs25] web portal call failed:', e.message);
  process.exit(1);
});
