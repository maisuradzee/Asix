#!/usr/bin/env node
/**
 * Staging-only dispatcher for the durable ST8 reconciliation alert outbox.
 * The receiver must deduplicate x-asix-alert-idempotency-key and verify HMAC.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

function required(name, env = process.env) {
  const value = env[name]?.trim();
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}

export function validateAlertWebhookUrl(value, allowedHosts = []) {
  let url;
  try { url = new URL(value); } catch { throw new Error('INVALID_ALERT_WEBHOOK_URL'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.hash || (url.port && url.port !== '443')) {
    throw new Error('ALERT_WEBHOOK_MUST_BE_HTTPS');
  }
  const hostname = url.hostname.toLowerCase();
  if (!Array.isArray(allowedHosts) || allowedHosts.length === 0) throw new Error('ALERT_WEBHOOK_HOST_ALLOWLIST_REQUIRED');
  if (isIP(hostname.replace(/^\[|\]$/g, '')) || hostname === 'localhost' || hostname.endsWith('.localhost')
      || hostname.endsWith('.local') || hostname.endsWith('.internal')) {
    throw new Error('ALERT_WEBHOOK_HOST_NOT_ALLOWED');
  }
  const normalized = allowedHosts.map((item) => String(item).trim().toLowerCase()).filter(Boolean);
  if (normalized.some((item) => item.includes('*') || item.includes('/') || item.includes(':'))
      || !normalized.includes(hostname)) {
    throw new Error('ALERT_WEBHOOK_HOST_NOT_ALLOWED');
  }
  return url.toString();
}

export function buildAlertSignature(secret, timestamp, body) {
  if (typeof secret !== 'string' || Buffer.byteLength(secret) < 32) throw new Error('ALERT_WEBHOOK_SECRET_TOO_SHORT');
  if (!/^\d{10}$/.test(String(timestamp))) throw new Error('INVALID_ALERT_TIMESTAMP');
  return createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
}

export function alertErrorCode(error) {
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return 'ALERT_TIMEOUT';
  if (error instanceof Error && error.message === 'ALERT_WEBHOOK_REJECTED') return 'ALERT_WEBHOOK_REJECTED';
  return 'ALERT_NETWORK_ERROR';
}

export function verifyAlertSignature(secret, timestamp, body, signatureHex) {
  if (!/^[0-9a-f]{64}$/.test(signatureHex ?? '')) return false;
  const expected = Buffer.from(buildAlertSignature(secret, timestamp, body), 'hex');
  const actual = Buffer.from(signatureHex, 'hex');
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

function serviceCredential(env) {
  if (Object.hasOwn(env, 'SUPABASE_SECRET_KEYS')) {
    let parsed;
    try { parsed = JSON.parse(String(env.SUPABASE_SECRET_KEYS ?? '').trim()); } catch { throw new Error('INVALID_SUPABASE_SECRET_KEYS_MAP'); }
    const value = typeof parsed?.default === 'string' ? parsed.default.trim() : '';
    if (!value || (!value.startsWith('sb_secret_') && value.split('.').length !== 3)) throw new Error('INVALID_SUPABASE_SECRET_KEY_FORMAT');
    return { value, legacyJwt: !value.startsWith('sb_secret_') };
  }
  const value = String(env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();
  if (!value || (!value.startsWith('sb_secret_') && value.split('.').length !== 3)) throw new Error('INVALID_SUPABASE_SECRET_KEY_FORMAT');
  return { value, legacyJwt: !value.startsWith('sb_secret_') };
}

function supabaseHeaders(credential) {
  const headers = { apikey: credential.value, 'content-type': 'application/json' };
  if (credential.legacyJwt) headers.authorization = `Bearer ${credential.value}`;
  return headers;
}

async function rpc(projectUrl, projectRef, credential, name, args) {
  if (new URL(projectUrl).hostname !== `${projectRef}.supabase.co`) throw new Error('STAGING_PROJECT_REF_MISMATCH');
  const response = await fetch(`${projectUrl.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: supabaseHeaders(credential),
    body: JSON.stringify(args),
    redirect: 'error',
    signal: AbortSignal.timeout(30_000),
  });
  const data = await response.json().catch(() => null);
  if (!response.ok || !data || data.status !== 'ok') throw new Error(`ALERT_OUTBOX_RPC_${name.toUpperCase()}_FAILED_${response.status}`);
  return data;
}

export async function dispatchAlertBatch({ rpcCall, workerId, limit, deliver }) {
  if (typeof rpcCall !== 'function' || typeof deliver !== 'function'
      || typeof workerId !== 'string' || !/^[A-Za-z0-9._-]{1,100}$/.test(workerId)
      || !Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error('INVALID_ALERT_DISPATCH_BATCH');
  }
  let claimed = 0;
  let delivered = 0;
  let failed = 0;
  for (let index = 0; index < limit; index++) {
    const claim = await rpcCall('st8_claim_reconciliation_alerts', {
      p_worker_id: workerId,
      p_limit: 1,
      p_lease_seconds: 90,
    });
    const alert = Array.isArray(claim?.alerts) ? claim.alerts[0] : null;
    if (!alert) break;
    claimed++;
    const result = await deliver(alert);
    await rpcCall('st8_finish_reconciliation_alert', {
      p_alert_id: alert.id,
      p_worker_id: workerId,
      p_success: result.success === true,
      p_error_code: result.success === true ? null : result.error_code,
    });
    if (result.success === true) delivered++;
    else failed++;
  }
  return { status: 'ok', claimed, delivered, failed };
}

export async function deliverAlert(alert, { webhookUrl, webhookSecret, allowedHosts = [], fetchImpl = fetch, now = () => Date.now() }) {
  if (!alert || typeof alert.event_key !== 'string' || !alert.event_key || !alert.payload || typeof alert.payload !== 'object') {
    throw new Error('INVALID_ALERT_ENVELOPE');
  }
  const url = validateAlertWebhookUrl(webhookUrl, allowedHosts);
  const timestamp = String(Math.floor(now() / 1000));
  const body = JSON.stringify({
    id: alert.id,
    event_key: alert.event_key,
    event_type: alert.event_type,
    payload: alert.payload,
    attempt_count: alert.attempt_count,
    created_at: alert.payload.created_at ?? null,
  });
  const signature = buildAlertSignature(webhookSecret, timestamp, body);
  let response;
  try {
    response = await fetchImpl(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-asix-alert-timestamp': timestamp,
        'x-asix-alert-signature': `sha256=${signature}`,
        'x-asix-alert-idempotency-key': alert.event_key,
      },
      body,
      redirect: 'error',
      signal: AbortSignal.timeout(10_000),
    });
  } catch (error) {
    return { success: false, error_code: alertErrorCode(error) };
  }
  if (response.status >= 200 && response.status < 300) return { success: true };
  return {
    success: false,
    error_code: response.status === 429 ? 'ALERT_HTTP_429' : response.status >= 500 ? 'ALERT_HTTP_5XX' : 'ALERT_WEBHOOK_REJECTED',
  };
}

async function main() {
  const env = process.env;
  if (env.ST8_ENVIRONMENT?.trim() !== 'staging') throw new Error('STAGING_ONLY');
  const projectRef = required('ST8_STAGING_PROJECT_REF', env);
  if (projectRef !== 'liiowoclsddlywabvmcg') throw new Error('UNAPPROVED_STAGING_PROJECT');
  const projectUrl = new URL(required('SUPABASE_URL', env));
  if (projectUrl.protocol !== 'https:' || projectUrl.hostname !== `${projectRef}.supabase.co` || projectUrl.pathname !== '/'
      || projectUrl.username || projectUrl.password || projectUrl.search || projectUrl.hash) {
    throw new Error('SUPABASE_URL_MUST_MATCH_STAGING_PROJECT');
  }
  const credential = serviceCredential(env);
  const allowedHosts = required('ST8_ALERT_WEBHOOK_ALLOWED_HOSTS', env).split(',').map((host) => host.trim()).filter(Boolean);
  const webhookUrl = validateAlertWebhookUrl(required('ST8_ALERT_WEBHOOK_URL', env), allowedHosts);
  const webhookSecret = required('ST8_ALERT_WEBHOOK_SECRET', env);
  if (Buffer.byteLength(webhookSecret) < 32) throw new Error('ALERT_WEBHOOK_SECRET_TOO_SHORT');
  const workerId = required('ST8_ALERT_WORKER_ID', env);
  if (!/^[A-Za-z0-9._-]{1,100}$/.test(workerId)) throw new Error('INVALID_ALERT_WORKER_ID');
  const limit = Number(env.ST8_ALERT_BATCH_SIZE ?? '20');
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('INVALID_ALERT_BATCH_SIZE');

  // Claim one row at a time. Each 90-second lease covers one bounded
  // webhook request and its finish RPC; later alerts are not leased in advance.
  const summary = await dispatchAlertBatch({
    workerId,
    limit,
    rpcCall: (name, args) => rpc(projectUrl.origin, projectRef, credential, name, args),
    deliver: (alert) => deliverAlert(alert, { webhookUrl, webhookSecret, allowedHosts }),
  });
  console.log(JSON.stringify(summary));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(`ST8 ALERT DISPATCH ERROR: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  });
}
