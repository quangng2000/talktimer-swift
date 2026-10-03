// The oracle executes the pinned TypeScript unchanged; Node strips types only.
import * as domain from './reference/domain.ts';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const referenceCommit = '2b50d690c64c644698f7ab46f071d8c5d7cd17b2';
const referenceSHA256 = createHash('sha256').update(readFileSync(new URL('./reference/domain.ts', import.meta.url))).digest('hex');
const tags = ['', 'opening', 'demo', 'repeat', 'missing'];
const sections = ['', 'Intro', 'Demo', 'Closing', 'missing'];
const entry = (section, expectedDuration, tags = []) => ({ section, expectedDuration, tags });
const lap = (timestamp, duration, section, selected, expectedDuration, tags = []) =>
  ({ timestamp, duration, section, selected, expectedDuration, tags });

function queries(laps) {
  return {
    selectedDurations: domain.selectedDurations(laps),
    selectedTotal: domain.selectedTotal(laps),
    selectedCount: domain.selectedCount(laps),
    allTags: domain.collectAllTags(laps),
    allSections: domain.collectAllSections(laps),
    runningTotals: domain.runningTotals(laps),
    tagQueries: tags.map(tag => ({ tag, sum: domain.sumByTag(laps, tag), count: domain.countByTag(laps, tag) })),
    sectionQueries: sections.map(section => ({ section, sum: domain.sumBySection(laps, section),
      count: domain.countBySection(laps, section), min: domain.minBySection(laps, section), max: domain.maxBySection(laps, section) })),
  };
}

function scenario(name, commands) {
  let history = domain.initHistory();
  const steps = [];
  for (const command of commands) {
    switch (command.op) {
      case 'doAction': history = domain.doAction(history, command.action); break;
      case 'preview': history = domain.preview(history, command.action); break;
      case 'commitFrom': history = domain.commitFrom(history, command.baseline); break;
      case 'undo': history = domain.undo(history); break;
      case 'redo': history = domain.redo(history); break;
      default: throw new Error(`Unknown test command: ${command.op}`);
    }
    if (!domain.histInv(history)) throw new Error(`Reference invariant failed in ${name}`);
    steps.push({ command, history, queries: queries(history.present.laps) });
  }
  return { name, steps };
}

const action = (type, values = {}) => ({ op: 'doAction', action: { type, ...values } });
const labels = [entry('Intro', 30, ['opening']), entry('Demo', -9, ['demo']), entry('Closing', 10)];
const directed = [
  { op: 'undo' }, { op: 'redo' },
  action('SetTime', { ms: 40 }), action('SetTime', { ms: -1 }), action('CreateLap'),
  action('SetTime', { ms: 90 }), action('CreateLap'),
  action('LabelLap', { idx: 0, name: 'Intro' }), action('SelectLap', { idx: 0 }),
  action('AdjustDuration', { idx: 1, duration: 80 }), action('AdjustDuration', { idx: 0, duration: -8 }),
  action('MoveUp', { idx: 1 }), action('MoveDown', { idx: 0 }),
  action('AddTag', { idx: 0, tag: 'repeat' }), action('AddTag', { idx: 0, tag: 'repeat' }),
  action('RemoveTag', { idx: 0, tag: 'repeat' }),
  action('SetTemplate', { labels }), action('ConsumeTemplate'),
  action('SetActiveSection', { idx: 1 }), action('ApplyActiveSection'),
  action('AdvanceTemplateAfter', { idx: 1 }),
  action('ImportLaps', { laps: [lap(-5, -7, 'Demo', true, -10, ['demo', 'demo']), lap(15, 9, 'Intro', false, 3)] }),
  action('DeleteLap', { idx: 2 }), action('DeleteLap', { idx: -1 }),
  { op: 'undo' }, { op: 'redo' },
  action('Reset'), action('Reset'),
  { op: 'preview', action: { type: 'SetTime', ms: 120 } },
  { op: 'preview', action: { type: 'CreateLap' } },
  { op: 'commitFrom', baseline: domain.init() },
  { op: 'undo' }, { op: 'redo' },
  action('SetTemplate', { labels: [] }), action('SetActiveSection', { idx: 0 }),
  action('ConsumeTemplate'), action('ApplyActiveSection'), action('AdvanceTemplateAfter', { idx: 2 }),
];

function generatedCommands(seed, count) {
  let state = seed;
  const next = limit => {
    state ^= state << 13; state ^= state >>> 17; state ^= state << 5;
    return (state >>> 0) % limit;
  };
  return Array.from({ length: count }, (_, index) => {
    const idx = next(8) - 2;
    const candidates = [
      action('SetTime', { ms: next(100_000) - 100 }), action('CreateLap'),
      action('LabelLap', { idx, name: sections[next(sections.length)] }),
      action('SelectLap', { idx }), action('DeleteLap', { idx }),
      action('AdjustDuration', { idx, duration: next(5_000) - 10 }),
      action('MoveUp', { idx }), action('MoveDown', { idx }),
      action('AddTag', { idx, tag: tags[next(tags.length)] }),
      action('RemoveTag', { idx, tag: tags[next(tags.length)] }),
      action('SetTemplate', { labels: next(2) === 0 ? labels : [] }), action('ConsumeTemplate'),
      action('SetActiveSection', { idx }), action('ApplyActiveSection'),
      action('AdvanceTemplateAfter', { idx }),
      action('ImportLaps', { laps: [lap(next(100) - 50, next(1_000) - 50,
        sections[next(sections.length)], next(2) === 0, next(100) - 50, ['demo', 'repeat'])] }),
      action('Reset'),
    ];
    // Each cycle visits every action. History operations interleave between cycles.
    if (index % 23 === 20) return { op: 'undo' };
    if (index % 23 === 21) return { op: 'redo' };
    if (index % 23 === 22) return { op: 'commitFrom', baseline: domain.init() };
    const command = candidates[index % candidates.length];
    if (index % 11 === 0) command.op = 'preview';
    return command;
  });
}

const scenarios = [scenario('all actions and history boundaries', directed),
  ...[1, 0x12345678, 0x514e, 0x7fffffff].map(seed => scenario(`seed ${seed}`, generatedCommands(seed, 128)))];
process.stdout.write(JSON.stringify({ referenceCommit, referenceSHA256, scenarios }));
