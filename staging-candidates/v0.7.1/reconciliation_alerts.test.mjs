import test from 'node:test';
import assert from 'node:assert/strict';
import {
  alertErrorCode,
  dispatchAlertBatch,
  buildAlertSignature,
  deliverAlert,
  validateAlertWebhookUrl,
  verifyAlertSignature,
} from '../dispatch-st8-reconciliation-alerts.mjs';

const secret = 'test-only-webhook-secret-with-more-than-32-bytes';
const alert = {
  id: 7,
  event_key: 'st8-recon:issue:run',
  event_type: 'ISSUE_OPENED',
  payload: { event: 'st8.reconciliation.issue_opened', severity: 'WARNING', created_at: '2026-11-23T00:00:00Z' },
  attempt_count: 1,
};

test('alert webhook requires HTTPS and blocks URL credentials/fragments', () => {
  const allowlist = ['alerts.example.com'];
  assert.equal(validateAlertWebhookUrl('https://alerts.example.com/hooks/st8', allowlist), 'https://alerts.example.com/hooks/st8');
  assert.throws(() => validateAlertWebhookUrl('https://alerts.example.com/hooks/st8'), /ALLOWLIST_REQUIRED/);
  assert.throws(() => validateAlertWebhookUrl('https://other.example.com/hooks', allowlist), /HOST_NOT_ALLOWED/);
  assert.throws(() => validateAlertWebhookUrl('http://alerts.example.com/hooks', allowlist), /MUST_BE_HTTPS/);
  assert.throws(() => validateAlertWebhookUrl('https://user:pass@alerts.example.com/hooks', allowlist), /MUST_BE_HTTPS/);
  assert.throws(() => validateAlertWebhookUrl('https://alerts.example.com/hooks#secret', allowlist), /MUST_BE_HTTPS/);
  assert.throws(() => validateAlertWebhookUrl('https://127.0.0.1/hooks', ['127.0.0.1']), /HOST_NOT_ALLOWED/);
  assert.throws(() => validateAlertWebhookUrl('https://alerts.example.com:8443/hooks', allowlist), /MUST_BE_HTTPS/);
  assert.throws(() => validateAlertWebhookUrl('https://alerts.example.com/hooks', ['*.example.com']), /HOST_NOT_ALLOWED/);
});

test('HMAC signature is over timestamp and exact request body', () => {
  const body = JSON.stringify({ id: 7, event_key: alert.event_key });
  const timestamp = '1795392000';
  const signature = buildAlertSignature(secret, timestamp, body);
  assert.match(signature, /^[0-9a-f]{64}$/);
  assert.equal(verifyAlertSignature(secret, timestamp, body, signature), true);
  assert.equal(verifyAlertSignature(secret, timestamp, `${body} `, signature), false);
  assert.equal(verifyAlertSignature(secret, timestamp, body, 'invalid'), false);
  assert.throws(() => buildAlertSignature('short', timestamp, body), /TOO_SHORT/);
});

test('dispatcher sends idempotency and HMAC headers, does not follow redirects or print response body', async () => {
  let captured;
  const result = await deliverAlert(alert, {
    webhookUrl: 'https://alerts.example.com/hooks/st8',
    allowedHosts: ['alerts.example.com'],
    webhookSecret: secret,
    now: () => 1_795_392_000_000,
    fetchImpl: async (url, options) => {
      captured = { url, options };
      return new Response('ok', { status: 202 });
    },
  });
  assert.deepEqual(result, { success: true });
  assert.equal(captured.options.redirect, 'error');
  assert.equal(captured.options.headers['x-asix-alert-idempotency-key'], alert.event_key);
  assert.match(captured.options.headers['x-asix-alert-signature'], /^sha256=[0-9a-f]{64}$/);
  assert.equal(captured.options.headers.authorization, undefined);
});

test('dispatcher classifies retryable and terminal HTTP responses', async () => {
  const run = (status) => deliverAlert(alert, {
    webhookUrl: 'https://alerts.example.com/hooks/st8', allowedHosts: ['alerts.example.com'], webhookSecret: secret,
    fetchImpl: async () => new Response('private response text', { status }),
  });
  assert.deepEqual(await run(429), { success: false, error_code: 'ALERT_HTTP_429' });
  assert.deepEqual(await run(503), { success: false, error_code: 'ALERT_HTTP_5XX' });
  assert.deepEqual(await run(400), { success: false, error_code: 'ALERT_WEBHOOK_REJECTED' });
  assert.equal(alertErrorCode(new Error('socket closed')), 'ALERT_NETWORK_ERROR');
});

test('alert worker claims one item at a time and finishes each lease before claiming the next', async () => {
  const events = [];
  const queue = [
    { id: 11, event_key: 'a', payload: {}, attempt_count: 1 },
    { id: 12, event_key: 'b', payload: {}, attempt_count: 1 },
  ];
  const summary = await dispatchAlertBatch({
    workerId: 'worker-test',
    limit: 5,
    rpcCall: async (name, args) => {
      events.push(`${name}:${args.p_limit ?? args.p_alert_id}`);
      if (name === 'st8_claim_reconciliation_alerts') return { alerts: queue.length ? [queue.shift()] : [] };
      return { status: 'ok' };
    },
    deliver: async (item) => {
      events.push(`deliver:${item.id}`);
      return { success: item.id === 11, error_code: item.id === 11 ? undefined : 'ALERT_HTTP_5XX' };
    },
  });
  assert.deepEqual(summary, { status: 'ok', claimed: 2, delivered: 1, failed: 1 });
  assert.deepEqual(events, [
    'st8_claim_reconciliation_alerts:1', 'deliver:11', 'st8_finish_reconciliation_alert:11',
    'st8_claim_reconciliation_alerts:1', 'deliver:12', 'st8_finish_reconciliation_alert:12',
    'st8_claim_reconciliation_alerts:1',
  ]);
});
