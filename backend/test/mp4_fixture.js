// Testler için en küçük ISO-BMFF (MP4) dosyası: ftyp + moov/mvhd (+ mdat). Gerçek görüntü içermez.
function box(type, body) {
  const head = Buffer.alloc(8); head.writeUInt32BE(8 + body.length, 0); head.write(type, 4, 'latin1');
  return Buffer.concat([head, body]);
}
function mvhd(version, timescale, duration) {
  if (version === 0) {
    const b = Buffer.alloc(100); b.writeUInt8(0, 0); b.writeUInt32BE(timescale, 12); b.writeUInt32BE(duration, 16); return box('mvhd', b);
  }
  const b = Buffer.alloc(112); b.writeUInt8(1, 0); b.writeUInt32BE(timescale, 20); b.writeBigUInt64BE(BigInt(duration), 24); return box('mvhd', b);
}
function mp4({ seconds, version = 0, moovLast = false, timescale = 600 } = {}) {
  const ftyp = box('ftyp', Buffer.from('isom\0\0\0\0isomiso2', 'latin1'));
  const moov = box('moov', Buffer.concat([mvhd(version, timescale, Math.round(seconds * timescale)), box('trak', Buffer.alloc(16))]));
  const mdat = box('mdat', Buffer.alloc(64));
  return Buffer.concat(moovLast ? [ftyp, mdat, moov] : [ftyp, moov, mdat]);
}
module.exports = { box, mvhd, mp4 };
