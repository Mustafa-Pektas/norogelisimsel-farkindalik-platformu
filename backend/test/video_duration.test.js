const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { mp4DurationSeconds } = require('../video_duration');
const { box, mvhd, mp4 } = require('./mp4_fixture');

function tmp(t, bytes) {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'dur-')), 'v.mp4');
  fs.writeFileSync(file, bytes); t.after(() => fs.rmSync(path.dirname(file), { recursive: true })); return file;
}

test('mvhd süresi sürüm 0/1 ve moov sonda iken okunur', t => {
  assert.equal(mp4DurationSeconds(tmp(t, mp4({ seconds: 8 }))), 8);
  assert.equal(mp4DurationSeconds(tmp(t, mp4({ seconds: 45.5, version: 1, timescale: 90000 }))), 45.5);
  assert.equal(mp4DurationSeconds(tmp(t, mp4({ seconds: 31, moovLast: true }))), 31);
});

test('64 bit kutu boyutu (largesize) atlanır ve süre bulunur', t => {
  const ftyp = box('ftyp', Buffer.from('isom\0\0\0\0', 'latin1'));
  const payload = Buffer.alloc(40);
  const big = Buffer.alloc(16); big.writeUInt32BE(1, 0); big.write('mdat', 4, 'latin1'); big.writeBigUInt64BE(BigInt(16 + payload.length), 8);
  const moov = box('moov', mvhd(0, 1000, 12000));
  assert.equal(mp4DurationSeconds(tmp(t, Buffer.concat([ftyp, big, payload, moov]))), 12);
});

test('Okunamayan/eksik başlıkta null döner (karar analize kalır)', t => {
  assert.equal(mp4DurationSeconds(tmp(t, Buffer.from('mp4 olmayan içerik'))), null);
  assert.equal(mp4DurationSeconds(tmp(t, box('ftyp', Buffer.from('isom', 'latin1')))), null);
  assert.equal(mp4DurationSeconds(tmp(t, mp4({ seconds: 10 }).subarray(0, 40))), null);
  assert.equal(mp4DurationSeconds(tmp(t, box('moov', mvhd(0, 0, 100)))), null);
  assert.equal(mp4DurationSeconds(path.join(os.tmpdir(), 'olmayan-dosya-xyz.mp4')), null);
});
