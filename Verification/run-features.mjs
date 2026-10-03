// Produce untouched Swift copies, both integer-model configurations, full
// generated Dafny, stage logs, and a small timing report in a fresh run folder.
// A passing runner means the expected successes AND failures were observed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { createHash } from 'node:crypto';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const verifier = process.env.LEMMASWIFT_BIN ?? path.resolve(project,
  '../LemmaSwift-case-study-toolchain/tools/.build/debug/lemmaswift');
fs.accessSync(verifier, fs.constants.X_OK);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const verifierHash = sha256(fs.readFileSync(verifier));
const resultsRoot = path.join(project, 'Verification/results');
fs.mkdirSync(resultsRoot, { recursive: true });
const results = fs.mkdtempSync(path.join(resultsRoot, 'features.'));
const selected = new Set(process.argv.slice(2));
const cases = [
  ['Algebraic', 'pass'],
  ['AlgebraicFalse', 'proof-failure', /postcondition|could not be proved/],
  ['RecursiveNontermination', 'proof-failure', /decreases|termination/],
  ['Optionals', 'pass'],
  ['OptionalUnsafe', 'proof-failure', /assertion might not hold|destructor|precondition/],
  ['OptionalMap', 'translation-failure', /Only compiler-bound free-function calls|Unsupported|not supported/],
  ['Arithmetic', 'pass'],
  ['ArithmeticUnbounded', 'model-dependent', /assertion might not hold|precondition/],
  ['ArithmeticZeroDivision', 'proof-failure', /assertion might not hold|precondition/],
  ['ArithmeticFalse', 'proof-failure', /postcondition|could not be proved/],
  ['TalkTimerCore', 'translation-failure', /No verification model for type 'String'/],
].filter(([name]) => selected.size === 0 || selected.has(name));
for (const name of selected) {
  if (!cases.some(([candidate]) => candidate === name)) throw new Error(`Unknown case: ${name}`);
}

function run(command, args, directory, log) {
  const start = performance.now();
  const result = spawnSync(command, args, {
    cwd: directory, encoding: 'utf8', timeout: 240000, maxBuffer: 16 * 1024 * 1024,
  });
  const seconds = (performance.now() - start) / 1000;
  const text = (result.stdout ?? '') + (result.stderr ?? '');
  fs.writeFileSync(log, text + (result.error ? `\n${result.error}\n` : ''));
  if (result.error) throw result.error;
  if (result.signal) throw new Error(`Command stopped by ${result.signal}: ${command}`);
  return { status: result.status, seconds, text };
}

const environment = [
  ['swift', ['--version']], ['dafny', ['--version']], [verifier, ['version']],
].map(([command, args]) => {
  const result = run(command, args, results, path.join(results, path.basename(command) + '.log'));
  if (result.status !== 0) throw new Error(`Cannot query ${command}`);
  return result.text.trim();
});
fs.writeFileSync(path.join(results, 'environment.txt'), environment.join('\n')
  + `\nverifier=${verifier}\nverifierSHA256=${verifierHash}\n`);
const rows = [];
const failures = [];
console.log(`Evidence: ${results}`);
for (const [name, expectation, pattern] of cases) {
  const original = name === 'TalkTimerCore'
    ? path.join(project, 'Sources/TalkTimerCore/Domain.swift')
    : path.join(project, `Verification/Features/${name}.swift`);
  // Snapshot once: both modes receive byte-identical input, even if another
  // process edits the original while this experiment is running.
  const sourceBytes = fs.readFileSync(original);
  const sourceSHA256 = sha256(sourceBytes);
  for (const model of ['swiftChecked', 'mathematical']) {
    const directory = path.join(results, name, model);
    const sourceRoot = path.join(directory, 'Source');
    fs.mkdirSync(sourceRoot, { recursive: true });
    const source = path.join(sourceRoot, `${name}.swift`);
    fs.writeFileSync(source, sourceBytes);
    const config = path.join(directory, 'lemmaswift.toml');
    fs.writeFileSync(config, `version = 1\n\n[[modules]]\nname = "FeatureProbe"\nsourceRoot = "Source"\nproofRoot = "Proofs"\nintegerModel = ${JSON.stringify(model)}\n`);
    const typecheck = run('swiftc', ['-typecheck', source], directory, path.join(directory, 'swift.log'));
    if (typecheck.status !== 0) throw new Error(`Swift rejected ${name}: ${typecheck.text}`);
    const emission = run(verifier, ['check', '--config', config, '--emit-only'], directory,
      path.join(directory, 'translation.log'));
    let verification;
    if (emission.status === 0) {
      verification = run('dafny', ['verify', '--verification-time-limit', '30',
        path.join(directory, 'Proofs/dfyconfig.toml')], directory, path.join(directory, 'dafny.log'));
    }
    const summary = verification?.text.match(/Dafny program verifier finished with (\d+) verified, (\d+) errors?/);
    // A parse/resolution failure or missing verifier summary is not evidence
    // that Dafny discharged or refuted the intended obligations.
    const actual = emission.status !== 0 ? 'translation-failure'
      : !summary ? 'backend-failure'
      : verification.status !== 0 ? 'proof-failure' : 'pass';
    const expected = expectation === 'model-dependent'
      ? (model === 'mathematical' ? 'pass' : 'proof-failure') : expectation;
    const transcript = emission.text + (verification?.text ?? '');
    const matched = actual === expected && (expected === 'pass' || !pattern || pattern.test(transcript));
    if (!matched) failures.push(`${name}/${model}: expected ${expected}, got ${actual}; see logs`);
    const artifact = path.join(directory, `Proofs/${name}.dfy`);
    const text = fs.existsSync(artifact) ? fs.readFileSync(artifact, 'utf8') : '';
    const row = { name, model, sourceSHA256, expected, actual, matched,
      swiftSeconds: typecheck.seconds, translationSeconds: emission.seconds,
      dafnySeconds: verification?.seconds ?? null,
      verified: summary ? Number(summary[1]) : null, errors: summary ? Number(summary[2]) : null,
      generatedBytes: Buffer.byteLength(text), generatedLines: text ? text.split('\n').length - 1 : 0,
      artifact: text ? path.relative(results, artifact) : null };
    rows.push(row);
    fs.writeFileSync(path.join(results, 'results.json'), JSON.stringify({ results, completed: false, rows, failures }, null, 2) + '\n');
    console.log(`${name} / ${model}: ${actual}; emit ${emission.seconds.toFixed(2)}s, Dafny ${verification ? verification.seconds.toFixed(2) + 's' : 'n/a'}${matched ? '' : ' [UNEXPECTED]'}`);
  }
}
const keys = ['name', 'model', 'expected', 'actual', 'matched', 'translationSeconds', 'dafnySeconds', 'verified', 'errors', 'generatedLines'];
fs.writeFileSync(path.join(results, 'results.json'), JSON.stringify({ results, completed: true, rows, failures }, null, 2) + '\n');
fs.writeFileSync(path.join(results, 'results.tsv'), [keys.join('\t'), ...rows.map(row =>
  keys.map(key => row[key] ?? '').join('\t'))].join('\n') + '\n');
if (failures.length) {
  console.error(failures.join('\n'));
  process.exitCode = 1;
} else {
  console.log('All expected feature outcomes reproduced. This does not prove the complete app.');
}
