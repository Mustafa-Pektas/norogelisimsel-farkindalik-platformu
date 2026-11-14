// Tek createApp/Node süreci içindeki sağlayıcı işleri.
// Varsayılan (queueMax=0): kuyruk yoktur; kapasite doluysa istek anında reddedilir (eski davranış).
// queueMax>0: kapasite doluysa istek FIFO bekleme kuyruğuna girer; kuyruk doluysa, bekleme süresi
// (queueWaitMs) aşılırsa veya istemci ayrılırsa (signal) yine sağlayıcıya gönderilmeden reddedilir.
// Otomatik tekrar (retry) yoktur.
function positiveInt(value, name, { allowZero = false } = {}) {
  if (typeof value !== 'string' || !(allowZero ? /^\d+$/ : /^[1-9]\d*$/).test(value) || !Number.isSafeInteger(Number(value))) {
    throw new Error(`${name} ${allowZero ? 'sıfır veya pozitif' : 'pozitif'} tam sayı olmalıdır.`);
  }
  return Number(value);
}

function createGenerationCapacity(value = '1', { queueMax = '0', queueWaitMs = '60000' } = {}) {
  const limit = positiveInt(value, 'GENERATION_MAX_CONCURRENT');
  const maxQueue = positiveInt(queueMax, 'GENERATION_QUEUE_MAX', { allowZero: true });
  const waitMs = positiveInt(queueWaitMs, 'GENERATION_QUEUE_WAIT_MS');
  let active = 0;
  const queue = [];
  const stats = { granted: 0, queued: 0, rejectedFull: 0, rejectedTimeout: 0, abandoned: 0, peakQueue: 0 };

  function makeRelease() {
    let released = false;
    return () => {
      if (released) return;
      released = true;
      active--;
      // Boşalan yeri sıradaki bekleyene devret (FIFO)
      while (queue.length && active < limit) {
        const waiter = queue.shift();
        if (waiter.settled) continue;
        active++;
        waiter.grant(makeRelease());
      }
    };
  }

  return {
    limit, maxQueue, waitMs,
    tryAcquire() {
      if (active >= limit || queue.length) return null;
      active++; stats.granted++;
      return makeRelease();
    },
    /** @returns {Promise<{release: Function|null, reason: 'granted'|'queue_full'|'queue_timeout'|'aborted', waitedMs: number}>} */
    acquire({ signal } = {}) {
      const started = Date.now();
      const done = (release, reason) => ({ release, reason, waitedMs: Date.now() - started });
      if (signal?.aborted) return Promise.resolve(done(null, 'aborted'));
      if (active < limit && !queue.length) { active++; stats.granted++; return Promise.resolve(done(makeRelease(), 'granted')); }
      if (queue.length >= maxQueue) { stats.rejectedFull++; return Promise.resolve(done(null, 'queue_full')); }
      return new Promise(resolve => {
        const waiter = { settled: false };
        const settle = (release, reason) => {
          if (waiter.settled) { release?.(); return; }
          waiter.settled = true;
          clearTimeout(timer);
          signal?.removeEventListener?.('abort', onAbort);
          const index = queue.indexOf(waiter); if (index >= 0) queue.splice(index, 1);
          resolve(done(release, reason));
        };
        waiter.grant = release => { stats.granted++; settle(release, 'granted'); };
        const onAbort = () => { stats.abandoned++; settle(null, 'aborted'); };
        const timer = setTimeout(() => { stats.rejectedTimeout++; settle(null, 'queue_timeout'); }, waitMs);
        signal?.addEventListener?.('abort', onAbort, { once: true });
        queue.push(waiter); stats.queued++; stats.peakQueue = Math.max(stats.peakQueue, queue.length);
      });
    },
    snapshot() { return { active, waiting: queue.length, limit, maxQueue, waitMs, ...stats }; },
  };
}
module.exports = { createGenerationCapacity };
