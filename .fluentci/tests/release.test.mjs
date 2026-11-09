import test from 'node:test';
import assert from 'node:assert/strict';
import { macosRelease } from '../ci/output/Main/index.js';

function fixture(os = 'darwin') {
  const calls = [];
  let command = [];
  const unquote = token => token.slice(1, -1).replaceAll("'\\''", "'");
  globalThis.Memory = { fromString: value => ({ offset: value }), find: value => ({ readString: () => value }) };
  globalThis.Host = { getFunctions: () => new Proxy({}, { get: (_, name) => value => {
    calls.push([name, value]);
    if (name === 'pipeline' || name === 'file') return JSON.stringify({ id: 'fixture' });
    if (name === 'get_os') return os;
    if (name === 'with_exec') command = JSON.parse(value).map(unquote);
    if (name === 'sha256') return 'a'.repeat(64);
    if (name === 'stdout') {
      if (command[0] === 'pwd') return '/release source';
      if (command[0] === 'mktemp') return '/tmp/fresh-stage';
      if (command[0] === 'dirname') return '/release source/dist';
      return '';
    }
    if (name === 'execute_plan') return JSON.stringify({ outcome: 'succeeded', tasks: [{ id: 'write', status: 'succeeded', exit_code: 0, error: null, duration_ms: 0, stdout: '', stderr: '', cache: { outcome: 'disabled', key: null, reason: '' }, wait_reason: null }] });
    return '';
  } }) };
  return calls;
}
const commands = calls => calls.filter(([name]) => name === 'with_exec').map(([, value]) => JSON.parse(value).map(token => token.slice(1, -1).replaceAll("'\\''", "'")));

test('builds CLI and driver for both architectures with locked dependencies', () => {
  const calls = fixture(); macosRelease({ source: '/release source', version: 'v0.1.0' })();
  const builds = commands(calls).filter(c => c[0] === 'cargo');
  assert.equal(builds.length, 4);
  for (const target of ['aarch64-apple-darwin', 'x86_64-apple-darwin']) {
    assert.ok(builds.some(c => c.includes(target) && c.includes('--bin') && c.includes('snapcaster')));
    assert.ok(builds.some(c => c.includes(target) && c.includes('-p') && c.includes('snapcaster-driver')));
  }
  assert.ok(builds.every(c => c.includes('--locked') && c.includes('--release')));
});

test('packages verified universal binaries, signed driver and installer payload with stable asset names', () => {
  const calls = fixture(); macosRelease({ source: '.', version: 'v0.1.0' })();
  const args = commands(calls);
  assert.equal(args.filter(c => c[0] === 'lipo' && c.includes('-create')).length, 2);
  assert.equal(args.filter(c => c[0] === 'lipo' && c.includes('-verify_arch') && c.includes('arm64') && c.includes('x86_64')).length, 2);
  assert.ok(args.some(c => c[0] === 'codesign' && c.includes('--force') && c.at(-1).endsWith('SnapcasterAudio.driver')));
  assert.ok(args.some(c => c[0] === 'codesign' && c.includes('--verify')));
  assert.ok(args.some(c => c[0] === 'cp' && c.includes('/release source/scripts/install-prebuilt.sh') && c.includes('/tmp/fresh-stage/staging/install.sh')));
  assert.ok(args.some(c => c[0] === 'cp' && c.includes('/release source/dist/com.tsirysndr.snapcaster.plist')));
  assert.ok(args.some(c => c[0] === 'tar' && c.includes('/release source/dist/snapcaster-v0.1.0-macos-universal.tar.gz')));
  const operations = calls.filter(([name]) => name === 'execute_plan').map(([, value]) => JSON.parse(value).plan.tasks[0].file_operation);
  assert.ok(operations.some(op => op.path === 'snapcaster-v0.1.0-macos-universal.tar.gz.sha256' && op.text.endsWith('  snapcaster-v0.1.0-macos-universal.tar.gz\n')));
  assert.ok(args.every(c => !['bash', 'sh'].includes(c[0])));
});

test('rejects unsafe versions and unsupported hosts before building', () => {
  let calls = fixture();
  assert.throws(() => macosRelease({ source: '.', version: '../bad' })(), /Invalid release/);
  assert.equal(calls.length, 0);
  calls = fixture('linux');
  assert.throws(() => macosRelease({ source: '.', version: 'v0.1.0' })(), /require macOS/);
  assert.equal(commands(calls).length, 0);
});
