'use strict';
// MP4/MOV (ISO-BMFF) başlığından video süresini okur: moov → mvhd (timescale, duration).
// Videoyu çözmez, harici araç (ffprobe/Python) çalıştırmaz; yükleme sonrası analizden ÖNCE
// uzun videoyu milisaniyeler içinde reddetmek için kullanılır. Okunamazsa null döner
// (karar mevcut analiz doğrulamalarına bırakılır).
const fs = require('node:fs');

const CONTAINERS = new Set(['moov']);

function readBox(fd, offset, fileSize) {
  if (offset + 8 > fileSize) return null;
  const head = Buffer.alloc(16);
  fs.readSync(fd, head, 0, Math.min(16, fileSize - offset), offset);
  let size = head.readUInt32BE(0);
  const type = head.toString('latin1', 4, 8);
  let headerSize = 8;
  if (size === 1) {
    if (offset + 16 > fileSize) return null;
    const big = head.readBigUInt64BE(8);
    if (big > BigInt(Number.MAX_SAFE_INTEGER)) return null;
    size = Number(big); headerSize = 16;
  } else if (size === 0) {
    size = fileSize - offset;
  }
  if (size < headerSize || offset + size > fileSize) return null;
  return { type, offset, size, headerSize };
}

function parseMvhd(buf) {
  // buf: mvhd gövdesi (başlık hariç)
  if (buf.length < 4) return null;
  const version = buf.readUInt8(0);
  let timescale, duration;
  if (version === 1) {
    if (buf.length < 32) return null;
    timescale = buf.readUInt32BE(20);
    const d = buf.readBigUInt64BE(24);
    if (d === 0xFFFFFFFFFFFFFFFFn) return null;
    duration = Number(d);
  } else if (version === 0) {
    if (buf.length < 20) return null;
    timescale = buf.readUInt32BE(12);
    duration = buf.readUInt32BE(16);
    if (duration === 0xFFFFFFFF) return null;
  } else return null;
  if (!timescale || !Number.isFinite(duration) || duration <= 0) return null;
  return duration / timescale;
}

/** @returns {number|null} saniye cinsinden süre; okunamazsa null */
function mp4DurationSeconds(filePath) {
  let fd;
  try {
    fd = fs.openSync(filePath, 'r');
    const fileSize = fs.fstatSync(fd).size;
    const walk = (start, end, depth) => {
      let offset = start;
      while (offset + 8 <= end) {
        const box = readBox(fd, offset, end);
        if (!box) return null;
        if (box.type === 'mvhd') {
          const len = Math.min(box.size - box.headerSize, 128);
          const body = Buffer.alloc(len);
          fs.readSync(fd, body, 0, len, box.offset + box.headerSize);
          return parseMvhd(body);
        }
        if (CONTAINERS.has(box.type) && depth < 2) {
          const found = walk(box.offset + box.headerSize, box.offset + box.size, depth + 1);
          if (found !== null) return found;
        }
        offset += box.size;
      }
      return null;
    };
    return walk(0, fileSize, 0);
  } catch (_) {
    return null;
  } finally {
    if (fd !== undefined) try { fs.closeSync(fd); } catch (_) { /* yoksay */ }
  }
}

module.exports = { mp4DurationSeconds, parseMvhd };
