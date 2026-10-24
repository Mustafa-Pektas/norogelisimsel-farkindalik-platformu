// Kaynak: 223bc7d validateFSMContinuity/hasTokenOverlap. Yalnız metinsel deney ölçütü.
// Boş durumların includes('') ile başarılı sayılması düzeltildi; klinik Δt/80% eşiği alınmadı.
function validateFSMContinuity(scenes) {
  const details = [];
  for (let i = 0; i < scenes.length - 1; i++) {
    const end = (scenes[i].endState || '').trim().toLowerCase();
    const start = (scenes[i + 1].startState || '').trim().toLowerCase();
    const isExact = end.length > 0 && end === start;
    const tokens = value => new Set(value.split(/\s+/).filter(word => word.length > 3));
    const a = tokens(end), b = tokens(start);
    const common = [...a].filter(word => b.has(word)).length;
    const isClose = !isExact && end.length > 0 && start.length > 0 &&
      (end.includes(start) || start.includes(end) || common >= 3);
    details.push({ transition: `${i + 1} -> ${i + 2}`, passed: isExact || isClose, isExact });
  }
  const matchedCount = details.filter(d => d.passed).length;
  return { matchedCount, totalTransitions: details.length,
    matchRate: details.length ? matchedCount / details.length : null, details,
    meaning: 'Metinsel ardışık durum benzerliği; anlamsal, klinik veya video doğruluğu değildir.' };
}
module.exports = { validateFSMContinuity };
