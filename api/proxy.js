const https = require('node:https');
const { URL } = require('node:url');

const MAX_BODY_BYTES = 16 * 1024;
let cachedAgent;

function getAgent() {
  if (cachedAgent) return cachedAgent;
  const ca = (process.env.WL_BACKEND_CA || '').replace(/\\n/g, '\n').trim();
  if (!ca.includes('BEGIN CERTIFICATE')) throw new Error('WL_BACKEND_CA is not configured');
  cachedAgent = new https.Agent({
    keepAlive: true,
    maxSockets: 32,
    ca,
    rejectUnauthorized: true,
    minVersion: 'TLSv1.2'
  });
  return cachedAgent;
}

module.exports = async function warriorLandApiProxy(req, res) {
  const backendUrl = process.env.WL_BACKEND_URL;
  const proxySecret = process.env.WL_PROXY_SECRET;
  const publicOrigin = process.env.WL_PUBLIC_ORIGIN;
  if (!backendUrl || !proxySecret || !publicOrigin) {
    res.status(503).json({ ok: false, error: { code: 'GATEWAY_NOT_CONFIGURED', message: 'WarriorLand gateway is not configured yet.' } });
    return;
  }

  let target;
  let origin;
  let incoming;
  try {
    target = new URL(backendUrl);
    origin = new URL(publicOrigin);
    incoming = new URL(req.url, publicOrigin);
  } catch {
    res.status(500).json({ ok: false, error: { code: 'GATEWAY_CONFIG_INVALID', message: 'Invalid gateway URL configuration.' } });
    return;
  }
  if (target.protocol !== 'https:' || origin.protocol !== 'https:' || !target.hostname || target.username || target.password) {
    res.status(500).json({ ok: false, error: { code: 'GATEWAY_CONFIG_INVALID', message: 'Gateway requires HTTPS backend and public origin URLs.' } });
    return;
  }

  const relativePath = incoming.searchParams.get('path') || '';
  const apiPath = '/' + relativePath.replace(/^\/+/, '');
  if (!/^\/v1\/[A-Za-z0-9_./-]+$/.test(apiPath) || apiPath.includes('..')) {
    res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Unknown API endpoint.' } });
    return;
  }
  incoming.searchParams.delete('path');

  const method = String(req.method || 'GET').toUpperCase();
  if (!['GET', 'POST', 'HEAD'].includes(method)) {
    res.setHeader('Allow', 'GET, POST, HEAD');
    res.status(405).json({ ok: false, error: { code: 'METHOD_NOT_ALLOWED', message: 'Method not allowed.' } });
    return;
  }
  if (method === 'POST' && Number(req.headers['content-length'] || 0) > MAX_BODY_BYTES) {
    res.status(413).json({ ok: false, error: { code: 'REQUEST_TOO_LARGE', message: 'Request body is too large.' } });
    return;
  }

  const headers = {
    host: origin.host,
    'x-forwarded-proto': 'https',
    'x-wl-proxy-key': proxySecret,
    'x-forwarded-for': String(req.headers['x-forwarded-for'] || '').slice(0, 256),
    accept: String(req.headers.accept || 'application/json').slice(0, 256)
  };
  for (const name of ['content-type', 'cookie', 'origin', 'x-wl-csrf']) {
    const value = req.headers[name];
    if (typeof value === 'string') headers[name] = value;
  }

  let agent;
  try {
    agent = getAgent();
  } catch {
    res.status(503).json({ ok: false, error: { code: 'TLS_NOT_CONFIGURED', message: 'The private TLS trust certificate is not configured.' } });
    return;
  }

  const query = incoming.searchParams.toString();
  const upstream = https.request({
    protocol: 'https:',
    hostname: target.hostname,
    port: target.port || 443,
    method,
    path: apiPath + (query ? '?' + query : ''),
    headers,
    agent,
    timeout: 25000
  }, upstreamResponse => {
    for (const name of ['content-type', 'cache-control', 'set-cookie', 'x-content-type-options', 'referrer-policy', 'x-frame-options', 'strict-transport-security', 'content-security-policy', 'permissions-policy']) {
      if (upstreamResponse.headers[name] !== undefined) res.setHeader(name, upstreamResponse.headers[name]);
    }
    res.statusCode = upstreamResponse.statusCode || 502;
    upstreamResponse.pipe(res);
  });

  upstream.on('timeout', () => upstream.destroy(new Error('Hostify API timeout')));
  upstream.on('error', error => {
    if (res.headersSent) res.destroy(error);
    else res.status(502).json({ ok: false, error: { code: 'BACKEND_UNAVAILABLE', message: 'WarriorLand server is currently unavailable.' } });
  });

  if (method === 'POST') req.pipe(upstream);
  else upstream.end();
};
