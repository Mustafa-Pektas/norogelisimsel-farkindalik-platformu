const test = require('node:test');
const assert = require('node:assert/strict');
const { backendTiming, checkTiming, pollTerminal } = require('../pilot_timing');
test('Backend defaults stay 600s/10s; client wait and explicit closing margin are distinct', () => {
  assert.deepEqual(backendTiming({}), { timeoutMs: 600000, killGraceMs: 10000 });
  const t = checkTiming({}); assert.equal(t.waitMs, 600000); assert.equal(t.closingGraceMs, 45000); assert.equal(t.totalObservationMs, 645000);
  assert.equal(checkTiming({ PILOT_D01_TIMEOUT_MS: '900000', PILOT_CHECK_WAIT_MS: '900000' }).totalObservationMs, 945000);
  assert.throws(() => checkTiming({ PILOT_D01_TIMEOUT_MS: '900000' }), /observation window/);
  for (const value of ['', '0', '-1', 'abc', '1.5']) assert.throws(() => backendTiming({ PILOT_D01_TIMEOUT_MS: value }), /Invalid/);
});
test('Mandatory boundary GET replaces stale running with actual analysis_timeout', async () => {
  let clock = 0; let calls = 0;
  const r = await pollTerminal({ now: () => clock, sleep: async ms => { clock += ms; }, timing: { waitMs: 10, totalObservationMs: 15, pollMs: 5 },
    read: async () => ++calls < 4 ? { status: 'running', code: null } : { status: 'interrupted', code: 'analysis_timeout' } });
  assert.equal(r.code, 'analysis_timeout'); assert.equal(r.finalStatus.status, 'interrupted'); assert.equal(r.finalGetPerformed, true); assert.equal(clock, 10);
});
test('Closing window observes delayed process exit; no generic job_not_completed masking', async () => {
  let clock = 0;
  const r = await pollTerminal({ now: () => clock, sleep: async ms => { clock += ms; }, timing: { waitMs: 10, totalObservationMs: 20, pollMs: 5 },
    read: async () => clock < 15 ? { status: 'running' } : { status: 'failed', code: 'cli_failed' } });
  assert.equal(r.code, 'cli_failed'); assert.equal(clock, 15); assert.equal(r.terminal, true);
});
test('No terminal status remains explicit client observation expiry, never completed', async () => {
  let clock = 0; const r = await pollTerminal({ now: () => clock, sleep: async ms => { clock += ms; },
    timing: { waitMs: 10, totalObservationMs: 20, pollMs: 5 }, read: async () => ({ status: 'running', code: null }) });
  assert.equal(clock, 20); assert.equal(r.code, 'client_observation_expired'); assert.equal(r.terminal, false);
});
