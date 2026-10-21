import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const origin = 'https://transport-crm-ij9v.onrender.com';
async function get(path, headers = {}) {
  const url = new URL(path, origin);
  assert.equal(url.origin, origin);
  const response = await fetch(url, {headers, signal: AbortSignal.timeout(30000)});
  assert.equal(response.status, 200, `${url.pathname}: HTTP ${response.status}`);
  return response;
}

let lastError;
for (let attempt = 1; attempt <= 6; attempt++) {
  try {
    const health = await (await get('/api/health')).json();
    assert.equal(health.status, 'ok');
    assert.equal(health.service, 'transport-crm');
    console.log('Public health endpoint: OK');
    lastError = undefined;
    break;
  } catch (error) {
    lastError = error;
    console.log(`Health attempt ${attempt}/6: ${error.message}`);
    if (attempt < 6) await new Promise(resolve => setTimeout(resolve, 10000));
  }
}
if (lastError) throw lastError;

const html = await (await get('/')).text();
const scripts = [...new Set([...html.matchAll(/<script[^>]+src="([^"]+\.js(?:\?[^"]*)?)"/g)].map(match => match[1].replaceAll('&amp;', '&')))];
assert.ok(scripts.length > 0, 'Next.js scripts are present');
const bundles = await Promise.all(scripts.map(async path => (await get(path)).text()));
for (const marker of ['crm_create_invoice_from_trips', 'crm_pay_driver_accruals']) {
  assert.ok(bundles.some(bundle => bundle.includes(marker)), `Deployed accounting bundle includes ${marker}`);
}
console.log('Public page and deployed accounting/payroll bundles: OK');

const clientSource = await readFile(new URL('../lib/supabase.ts', import.meta.url), 'utf8');
const key = clientSource.match(/sb_publishable_[A-Za-z0-9_-]+/)?.[0];
assert.ok(key, 'Public Supabase key exists');
const settings = await (await get('/supabase/auth/v1/settings', {apikey: key})).json();
assert.equal(typeof settings.external, 'object');
console.log('Supabase authentication proxy: OK');
