// Tek createApp/Node süreci içindeki sağlayıcı işleri. Kuyruk veya TTL yoktur.
function createGenerationCapacity(value = '1') {
  if (typeof value !== 'string' || !/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new Error('GENERATION_MAX_CONCURRENT pozitif tam sayı olmalıdır.');
  }
  const limit = Number(value);
  let active = 0;
  return {
    tryAcquire() {
      if (active >= limit) return null;
      active++;
      let released = false;
      return () => {
        if (!released) { released = true; active--; }
      };
    },
  };
}
module.exports = { createGenerationCapacity };
