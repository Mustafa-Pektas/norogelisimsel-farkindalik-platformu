const test = require('node:test');
const assert = require('node:assert/strict');
const { main, parseArgs, summarize, classify } = require('../rag_stress_test');

test('Stres testi yerel kipte gerçek uç noktaları sahte sağlayıcıyla başarıyla çalıştırır', async () => {
  const result = await main(['--mode', 'local', '--requests', '8', '--concurrency', '1', '--latency-ms', '0-5'], { log: false });
  assert.equal(result.summary.overall.total, 8);
  assert.equal(result.summary.overall.success, 8);
  assert.deepEqual(Object.keys(result.summary.groups).sort(), ['compare-A', 'compare-B', 'compare-C', 'compare-D', 'input']);
  for (const record of result.records) assert.ok(Number.isFinite(record.measurement.retrievalDurationMs));
  assert.equal(result.fakeProvider.calls, 8);
});

test('Kapasite 1 iken eşzamanlı istekler sağlayıcıya gitmeden kapasite reddi alır', async () => {
  const result = await main(['--mode', 'local', '--requests', '6', '--concurrency', '3', '--capacity', '1',
    '--latency-ms', '200-200', '--endpoints', 'input'], { log: false });
  assert.ok(result.summary.overall.outcomes.capacity_rejected >= 1);
  assert.equal(result.fakeProvider.peakActive, 1);
});

test('Sağlayıcı hataları sınıflandırılır; remote kip ücret üst sınırı olmadan çalışmaz', () => {
  assert.equal(classify({ status: 502, body: { providerError: { httpStatus: 429, category: 'quota_or_rate_limit' } } }), 'provider_quota');
  assert.equal(classify({ status: 429, body: { code: 'local_capacity_exceeded' } }), 'capacity_rejected');
  assert.equal(classify({ transportError: 'client_timeout' }), 'client_timeout');
  assert.throws(() => parseArgs(['--mode', 'remote', '--server', 'https://example.invalid']), /max-requests/);
  assert.throws(() => parseArgs(['--mode', 'remote', '--server', 'https://example.invalid', '--requests', '9', '--max-requests', '8']), /aşıyor/);
  assert.equal(summarize([], 1).overall.total, 0);
});
