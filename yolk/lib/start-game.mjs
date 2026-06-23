// Drives the FS25 dedicated-server web portal over HTTP.
//
//   node start-game.mjs          -> log in, read the start form, POST "Start"
//   node start-game.mjs --stop   -> log in, POST "Stop"
//
// The dedicatedServer.exe only exposes a web UI; there is no CLI to start the
// actual game session, so we replicate what clicking "Start" in the browser does.
// Logic adapted from wine-gameservers/arch-fs25server (start_game.mjs).
import http from 'http';
import assert from 'assert';

const HOST = `127.0.0.1:${process.env.WEB_PORT || '7999'}`;
const USERNAME = process.env.WEB_USERNAME || 'admin';
const PASSWORD = process.env.WEB_PASSWORD || 'changeme';
const STOP = process.argv.includes('--stop');

function request(method, data = {}, cookie = '') {
  let path = '/index.html?lang=en';
  const headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'User-Agent': 'fs25-egg/1.0',
  };
  if (cookie) headers['Cookie'] = cookie;

  const body = Object.entries(data)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');

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

async function login() {
  const res = await request('GET');
  const cookies = res.headers['set-cookie'] || [];
  let session = null;
  for (const c of cookies) {
    const m = /(SessionID=[^;]+)/i.exec(c);
    if (m) { session = m[1]; break; }
  }
  assert(session, 'No session cookie returned by web portal');
  await request('POST', { username: USERNAME, password: PASSWORD, login: 'Login' }, session);
  return session;
}

const START_FIELDS = [
  'game_name', 'admin_password', 'game_password', 'savegame', 'server_port',
  'max_player', 'mp_language', 'auto_save_interval', 'stats_interval', 'pause_game_if_empty',
];

function scrape(html) {
  const out = {};
  const inputRe = /<input type="[^"]*" name="([^"]*)" value="([^"]*)"/gis;
  const selectRe = /<select name\s*=\s*"([^"]*)".*?<option value="([^"]*)" selected="selected"/gis;
  let m;
  while ((m = inputRe.exec(html))) if (START_FIELDS.includes(m[1])) out[m[1]] = m[2];
  while ((m = selectRe.exec(html))) if (START_FIELDS.includes(m[1])) out[m[1]] = m[2];
  return out;
}

async function start() {
  const session = await login();
  const page = await request('GET', {}, session);
  const fields = scrape(page.body);
  for (const f of START_FIELDS) {
    if (typeof fields[f] === 'undefined') throw new Error(`Start form missing field: ${f}`);
  }
  fields.crossplay_allowed = /name="crossplay_allowed" checked/.test(page.body) ? 'on' : 'off';
  fields.start_server = 'Start';
  await request('POST', fields, session);
  console.log('[fs25] Game session start requested.');
}

async function stop() {
  const session = await login();
  await request('POST', { stop_server: 'Stop' }, session);
  console.log('[fs25] Game session stop requested.');
}

(STOP ? stop() : start()).catch((e) => {
  console.error('[fs25] web portal call failed:', e.message);
  process.exit(1);
});
