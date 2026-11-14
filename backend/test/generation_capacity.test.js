const test = require('node:test');
const assert = require('node:assert/strict');
const { createGenerationCapacity } = require('../generation_capacity');
const { main } = require('../rag_stress_test');

test('Kuyruk kapalıyken (varsayılan) dolu kapasite anında reddedilir', async () => {
  const pool = createGenerationCapacity('1');
  const first = await pool.acquire();
  assert.equal(first.reason, 'granted');
  const second = await pool.acquire();
  assert.equal(second.release, null); assert.equal(second.reason, 'queue_full');
  first.release();
  assert.equal((await pool.acquire()).reason, 'granted');
});

test('Kuyruk FIFO sırayla yer verir; kuyruk dolunca reddeder', async () => {
  const pool = createGenerationCapacity('1', { queueMax: '2', queueWaitMs: '5000' });
  const first = await pool.acquire();
  const order = [];
  const a = pool.acquire().then(r => { order.push('a'); return r; });
  const b = pool.acquire().then(r => { order.push('b'); return r; });
  const full = await pool.acquire();
  assert.equal(full.reason, 'queue_full');
  assert.equal(pool.snapshot().waiting, 2);
  assert.equal(pool.tryAcquire(), null, 'bekleyenler varken sıra atlanamaz');
  first.release();
  const ra = await a; assert.equal(ra.reason, 'granted'); assert.ok(ra.waitedMs >= 0);
  ra.release();
  const rb = await b; assert.equal(rb.reason, 'granted');
  assert.deepEqual(order, ['a', 'b']);
  rb.release();
  assert.equal(pool.snapshot().active, 0);
});

test('Bekleme süresi dolan istek reddedilir; ayrılan istemcinin yeri başkasına geçer', async () => {
  const pool = createGenerationCapacity('1', { queueMax: '3', queueWaitMs: '40' });
  const holder = await pool.acquire();
  assert.equal((await pool.acquire()).reason, 'queue_timeout');
  const controller = new AbortController();
  const leaving = pool.acquire({ signal: controller.signal });
  const staying = pool.acquire();
  controller.abort();
  assert.equal((await leaving).reason, 'aborted');
  holder.release();
  const next = await staying;
  assert.equal(next.reason, 'granted');
  next.release();
  const snap = pool.snapshot();
  assert.equal(snap.active, 0); assert.equal(snap.rejectedTimeout, 1); assert.equal(snap.abandoned, 1);
});

test('Geçersiz kuyruk ayarları başlatmayı durdurur', () => {
  for (const queueMax of ['-1', 'x', '1.5', '']) assert.throws(() => createGenerationCapacity('1', { queueMax }), /GENERATION_QUEUE_MAX/);
  for (const queueWaitMs of ['0', 'x', '']) assert.throws(() => createGenerationCapacity('1', { queueWaitMs }), /GENERATION_QUEUE_WAIT_MS/);
});

test('Uçtan uca: kapasite 1 + kuyruk ile eşzamanlı istekler reddedilmeden sırayla işlenir', async () => {
  const result = await main(['--mode', 'local', '--requests', '6', '--concurrency', '3', '--capacity', '1',
    '--queue-max', '4', '--latency-ms', '30-30', '--endpoints', 'input'], { log: false });
  assert.equal(result.summary.overall.success, 6);
  assert.equal(result.fakeProvider.peakActive, 1);
  assert.ok(result.records.some(r => r.measurement.queueWaitMs > 0));
});
