const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../server');

function fakeGenAI(phases, latency, calls) {
  const scenes = phases.map((phase, i) => ({ phase, videoPrompt: 'The child looks toward the adult.', startState: 's', endState: 'e',
    clinical: { note: 'not', atypical: false, latencySeconds: phase === 'UYARAN' && i === 2 ? latency : null } }));
  const text = JSON.stringify({ title: 't', summary: Array(70).fill('kelime').join(' '), scenes,
    assessment: { latencies: [], atypicalCriteria: [], score: '-', referralNote: '-' } });
  return { getGenerativeModel: (opts) => ({ generateContent: async (user) => { calls.push({ opts, user });
    return { response: { text: () => text, usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 20 } } }; } }) };
}

async function post(app, body) {
  const server = await new Promise(r => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/api/generate-scenario`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    return { status: res.status, body: await res.json() };
  } finally { await new Promise(r => server.close(r)); }
}

const env = { BACKEND_MODE: 'development', GEMINI_API_KEY: 'test-anahtari-uzun-degil-gercek' };

test('stimulusOnly: 11 UYARAN sahnesi kabul edilir, istem kapsamı daraltılır, Δt uyumu hesaplanır', async () => {
  const calls = [];
  const app = createApp({ env, genAI: fakeGenAI(Array(11).fill('UYARAN'), 3.4, calls) });
  const r = await post(app, { ageMonths: 21, riskProfile: 'ATİPİK', ontologyCodes: ['D01'], arm: 'D', stimulusOnly: true });
  assert.equal(r.status, 200);
  assert.equal(r.body.scenario.scenes.length, 11);
  assert.equal(r.body.metadata.stimulusOnly, true);
  assert.match(calls[0].user, /Yalnız UYARAN fazını üret: tam 11 sahne/);
  assert.equal(r.body.benchmark.deltaTCompliant, true);
  assert.deepEqual([r.body.benchmark.deltaT.expected, r.body.benchmark.deltaT.actual], ['ATIPIK', 'ATIPIK']);
});

test('stimulusOnly: TABAN/KAPANIS içeren çıktı reddedilir; bayraksız istek 26 sahne bekler', async () => {
  const mixed = [...Array(3).fill('TABAN'), ...Array(5).fill('UYARAN'), ...Array(3).fill('KAPANIS')];
  const calls = [];
  const r = await post(createApp({ env, genAI: fakeGenAI(mixed, 1.0, calls) }),
    { ageMonths: 21, riskProfile: 'TİPİK', ontologyCodes: ['D01'], arm: 'A', stimulusOnly: true });
  assert.notEqual(r.status, 200);
  const calls26 = [];
  const r26 = await post(createApp({ env, genAI: fakeGenAI(Array(11).fill('UYARAN'), 1.0, calls26) }),
    { ageMonths: 21, riskProfile: 'TİPİK', ontologyCodes: ['D01'], arm: 'A' });
  assert.notEqual(r26.status, 200, '11 sahne normal (26 sahnelik) istekte kabul edilmez');
  assert.doesNotMatch(calls26[0].user, /Yalnız UYARAN/);
});
