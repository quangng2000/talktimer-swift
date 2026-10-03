//@ backend dafny
// Verified domain logic for Talk Timer.
// Pure-functional TypeScript with LemmaScript annotations.
// All sequence helpers are recursive (LemmaScript expects no mutation).

// ═══════════════════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════════════════

export interface Lap {
  timestamp: number;
  duration: number;
  section: string;
  selected: boolean;
  expectedDuration: number;
  tags: string[];
}

export interface TemplateEntry {
  section: string;
  expectedDuration: number;
  tags: string[];
}

export interface Model {
  currentTime: number;
  lastLapTime: number;
  laps: Lap[];
  template: TemplateEntry[];
  originalTemplate: TemplateEntry[];
  activeSection: number;
}

export type Action =
  | { type: 'SetTime'; ms: number }
  | { type: 'CreateLap' }
  | { type: 'LabelLap'; idx: number; name: string }
  | { type: 'SelectLap'; idx: number }
  | { type: 'DeleteLap'; idx: number }
  | { type: 'AdjustDuration'; idx: number; duration: number }
  | { type: 'MoveUp'; idx: number }
  | { type: 'MoveDown'; idx: number }
  | { type: 'AddTag'; idx: number; tag: string }
  | { type: 'RemoveTag'; idx: number; tag: string }
  | { type: 'SetTemplate'; labels: TemplateEntry[] }
  | { type: 'ConsumeTemplate' }
  | { type: 'SetActiveSection'; idx: number }
  | { type: 'ApplyActiveSection' }
  | { type: 'AdvanceTemplateAfter'; idx: number }
  | { type: 'ImportLaps'; laps: Lap[] }
  | { type: 'Reset' };

// ═══════════════════════════════════════════════════════════════
// Tag helpers
// ═══════════════════════════════════════════════════════════════

//@ pure
export function addTagToSeq(tags: string[], tag: string): string[] {
  //@ ensures \result.includes(tag)
  if (tags.includes(tag)) return tags;
  return [...tags, tag];
}

//@ pure
export function removeTagFromSeq(tags: string[], tag: string): string[] {
  //@ decreases tags.length
  //@ ensures !\result.includes(tag)
  if (tags.length === 0) return [];
  const rest = removeTagFromSeq(tags.slice(1), tag);
  if (tags[0] === tag) return rest;
  return [tags[0], ...rest];
}

// ═══════════════════════════════════════════════════════════════
// Lap validation
// ═══════════════════════════════════════════════════════════════

//@ pure
export function lapValid(l: Lap): boolean {
  return l.timestamp >= 0 && l.duration >= 0 && l.expectedDuration >= -1;
}

//@ pure
export function lapsValid(laps: Lap[]): boolean {
  return laps.every(lapValid);
}

//@ pure
export function clampLap(lap: Lap): Lap {
  //@ ensures \result.timestamp >= 0
  //@ ensures \result.duration >= 0
  //@ ensures \result.expectedDuration >= -1
  return {
    timestamp: lap.timestamp >= 0 ? lap.timestamp : 0,
    duration: lap.duration >= 0 ? lap.duration : 0,
    section: lap.section,
    selected: lap.selected,
    expectedDuration: lap.expectedDuration >= -1 ? lap.expectedDuration : -1,
    tags: lap.tags,
  };
}

//@ pure
export function clampLaps(laps: Lap[]): Lap[] {
  //@ decreases laps.length
  //@ ensures \result.length === laps.length
  //@ ensures lapsValid(\result)
  if (laps.length === 0) return [];
  return [clampLap(laps[0]), ...clampLaps(laps.slice(1))];
}

//@ pure
export function templateEntryToLap(entry: TemplateEntry): Lap {
  //@ ensures \result.timestamp >= 0
  //@ ensures \result.duration >= 0
  //@ ensures \result.expectedDuration === -1
  return {
    timestamp: 0,
    duration: entry.expectedDuration >= 0 ? entry.expectedDuration : 0,
    section: entry.section,
    selected: true,
    expectedDuration: -1,
    tags: entry.tags,
  };
}

//@ pure
export function templateToLaps(template: TemplateEntry[]): Lap[] {
  //@ decreases template.length
  //@ ensures \result.length === template.length
  //@ ensures lapsValid(\result)
  if (template.length === 0) return [];
  return [templateEntryToLap(template[0]), ...templateToLaps(template.slice(1))];
}

// ═══════════════════════════════════════════════════════════════
// Invariant
// ═══════════════════════════════════════════════════════════════

//@ pure
export function inv(m: Model): boolean {
  return m.currentTime >= 0
    && m.lastLapTime >= 0
    && m.lastLapTime <= m.currentTime
    && lapsValid(m.laps)
    && m.activeSection >= -1
    && (m.activeSection < 0 || m.activeSection < m.originalTemplate.length);
}

// ═══════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════

export function init(): Model {
  //@ ensures inv(\result)
  return {
    currentTime: 0,
    lastLapTime: 0,
    laps: [],
    template: [],
    originalTemplate: [],
    activeSection: -1,
  };
}

// ═══════════════════════════════════════════════════════════════
// Sequence update helpers
// ═══════════════════════════════════════════════════════════════

//@ pure
function setAt<T>(s: T[], i: number, x: T): T[] {
  //@ requires i >= 0 && i < s.length
  //@ ensures \result.length === s.length
  return [...s.slice(0, i), x, ...s.slice(i + 1)];
}

//@ pure
function removeAt<T>(s: T[], i: number): T[] {
  //@ requires i >= 0 && i < s.length
  //@ ensures \result.length === s.length - 1
  return [...s.slice(0, i), ...s.slice(i + 1)];
}

// ═══════════════════════════════════════════════════════════════
// Per-action handlers
// ═══════════════════════════════════════════════════════════════

function applySetTime(m: Model, ms: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (ms >= m.currentTime) {
    return { ...m, currentTime: ms };
  }
  return m;
}

function applyCreateLap(m: Model): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  const duration = m.currentTime - m.lastLapTime;
  const newLap: Lap = {
    timestamp: m.currentTime,
    duration: duration,
    section: '',
    selected: false,
    expectedDuration: -1,
    tags: [],
  };
  return { ...m, lastLapTime: m.currentTime, laps: [...m.laps, newLap] };
}

function applyLabelLap(m: Model, idx: number, name: string): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length) return m;
  const updated: Lap = { ...m.laps[idx], section: name };
  return { ...m, laps: setAt(m.laps, idx, updated) };
}

function applySelectLap(m: Model, idx: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length) return m;
  const updated: Lap = { ...m.laps[idx], selected: !m.laps[idx].selected };
  return { ...m, laps: setAt(m.laps, idx, updated) };
}

function applyDeleteLap(m: Model, idx: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length) return m;
  return { ...m, laps: removeAt(m.laps, idx) };
}

function applyAdjustDuration(m: Model, idx: number, duration: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length) return m;
  if (duration < 0) return m;
  const updated: Lap = { ...m.laps[idx], duration: duration };
  return { ...m, laps: setAt(m.laps, idx, updated) };
}

function applyMoveUp(m: Model, idx: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 1 || idx >= m.laps.length) return m;
  const a = m.laps[idx - 1];
  const b = m.laps[idx];
  const newLaps = setAt(setAt(m.laps, idx - 1, b), idx, a);
  return { ...m, laps: newLaps };
}

function applyMoveDown(m: Model, idx: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length - 1) return m;
  const a = m.laps[idx];
  const b = m.laps[idx + 1];
  const newLaps = setAt(setAt(m.laps, idx, b), idx + 1, a);
  return { ...m, laps: newLaps };
}

function applyAddTag(m: Model, idx: number, tag: string): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length) return m;
  const newTags = addTagToSeq(m.laps[idx].tags, tag);
  const updated: Lap = { ...m.laps[idx], tags: newTags };
  return { ...m, laps: setAt(m.laps, idx, updated) };
}

function applyRemoveTag(m: Model, idx: number, tag: string): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.laps.length) return m;
  const newTags = removeTagFromSeq(m.laps[idx].tags, tag);
  const updated: Lap = { ...m.laps[idx], tags: newTags };
  return { ...m, laps: setAt(m.laps, idx, updated) };
}

function applySetTemplate(m: Model, labels: TemplateEntry[]): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  return { ...m, template: labels, originalTemplate: labels, activeSection: -1 };
}

function applyConsumeTemplate(m: Model): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (m.template.length === 0) return m;
  if (m.laps.length === 0) return m;
  const idx = m.laps.length - 1;
  const entry = m.template[0];
  const expectedDur = entry.expectedDuration >= 0 ? entry.expectedDuration : -1;
  const updated: Lap = {
    ...m.laps[idx],
    section: entry.section,
    selected: true,
    expectedDuration: expectedDur,
    tags: entry.tags,
  };
  return { ...m, laps: setAt(m.laps, idx, updated), template: m.template.slice(1) };
}

function applySetActiveSection(m: Model, idx: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < -1) return m;
  if (idx >= 0 && idx >= m.originalTemplate.length) return m;
  return { ...m, activeSection: idx };
}

function applyApplyActiveSection(m: Model): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (m.activeSection < 0) return m;
  if (m.activeSection >= m.originalTemplate.length) return m;
  if (m.laps.length === 0) return m;
  const lapIdx = m.laps.length - 1;
  const entry = m.originalTemplate[m.activeSection];
  const expectedDur = entry.expectedDuration >= 0 ? entry.expectedDuration : -1;
  const updated: Lap = {
    ...m.laps[lapIdx],
    section: entry.section,
    selected: true,
    expectedDuration: expectedDur,
    tags: entry.tags,
  };
  return { ...m, laps: setAt(m.laps, lapIdx, updated) };
}

function applyAdvanceTemplateAfter(m: Model, idx: number): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (idx < 0 || idx >= m.originalTemplate.length) return m;
  const newTemplate = m.originalTemplate.slice(idx + 1);
  return { ...m, template: newTemplate, activeSection: -1 };
}

function applyImportLaps(m: Model, laps: Lap[]): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  const validLaps = clampLaps(laps);
  return { ...m, laps: [...m.laps, ...validLaps] };
}

function applyReset(m: Model): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  if (m.originalTemplate.length > 0) {
    return {
      currentTime: m.currentTime,
      lastLapTime: m.currentTime,
      laps: templateToLaps(m.originalTemplate),
      template: [],
      originalTemplate: [],
      activeSection: -1,
    };
  }
  return {
    currentTime: m.currentTime,
    lastLapTime: m.currentTime,
    laps: [],
    template: [],
    originalTemplate: [],
    activeSection: -1,
  };
}

// ═══════════════════════════════════════════════════════════════
// Apply (top-level state machine)
// ═══════════════════════════════════════════════════════════════

export function apply(m: Model, a: Action): Model {
  //@ requires inv(m)
  //@ ensures inv(\result)
  switch (a.type) {
    case 'SetTime': return applySetTime(m, a.ms);
    case 'CreateLap': return applyCreateLap(m);
    case 'LabelLap': return applyLabelLap(m, a.idx, a.name);
    case 'SelectLap': return applySelectLap(m, a.idx);
    case 'DeleteLap': return applyDeleteLap(m, a.idx);
    case 'AdjustDuration': return applyAdjustDuration(m, a.idx, a.duration);
    case 'MoveUp': return applyMoveUp(m, a.idx);
    case 'MoveDown': return applyMoveDown(m, a.idx);
    case 'AddTag': return applyAddTag(m, a.idx, a.tag);
    case 'RemoveTag': return applyRemoveTag(m, a.idx, a.tag);
    case 'SetTemplate': return applySetTemplate(m, a.labels);
    case 'ConsumeTemplate': return applyConsumeTemplate(m);
    case 'SetActiveSection': return applySetActiveSection(m, a.idx);
    case 'ApplyActiveSection': return applyApplyActiveSection(m);
    case 'AdvanceTemplateAfter': return applyAdvanceTemplateAfter(m, a.idx);
    case 'ImportLaps': return applyImportLaps(m, a.laps);
    case 'Reset': return applyReset(m);
  }
}

// ═══════════════════════════════════════════════════════════════
// Selected aggregation
// ═══════════════════════════════════════════════════════════════

//@ pure
export function sumFrom(s: number[], i: number): number {
  //@ type i nat
  //@ requires i <= s.length
  //@ decreases s.length - i
  if (i >= s.length) return 0;
  return s[i] + sumFrom(s, i + 1);
}

//@ pure
export function selectedDurations(laps: Lap[]): number[] {
  //@ decreases laps.length
  if (laps.length === 0) return [];
  const rest = selectedDurations(laps.slice(1));
  if (laps[0].selected) return [laps[0].duration, ...rest];
  return rest;
}

export function selectedTotal(laps: Lap[]): number {
  return sumFrom(selectedDurations(laps), 0);
}

export function selectedCount(laps: Lap[]): number {
  //@ ensures \result >= 0
  return selectedDurations(laps).length;
}

// ═══════════════════════════════════════════════════════════════
// Tag aggregation
// ═══════════════════════════════════════════════════════════════

//@ pure
export function lapHasTag(lap: Lap, tag: string): boolean {
  return lap.tags.includes(tag);
}

//@ pure
export function sumByTag(laps: Lap[], tag: string): number {
  //@ decreases laps.length
  if (laps.length === 0) return 0;
  const rest = sumByTag(laps.slice(1), tag);
  if (laps[0].selected && lapHasTag(laps[0], tag)) {
    return laps[0].duration + rest;
  }
  return rest;
}

//@ pure
export function countByTag(laps: Lap[], tag: string): number {
  //@ decreases laps.length
  //@ ensures \result >= 0
  if (laps.length === 0) return 0;
  const rest = countByTag(laps.slice(1), tag);
  if (laps[0].selected && lapHasTag(laps[0], tag)) {
    return 1 + rest;
  }
  return rest;
}

//@ pure
function addUniqueTags(seen: string[], tags: string[]): string[] {
  //@ decreases tags.length
  if (tags.length === 0) return seen;
  if (seen.includes(tags[0])) return addUniqueTags(seen, tags.slice(1));
  return addUniqueTags([...seen, tags[0]], tags.slice(1));
}

//@ pure
function collectAllTagsHelper(laps: Lap[], seen: string[]): string[] {
  //@ decreases laps.length
  if (laps.length === 0) return seen;
  const newTags = laps[0].selected ? laps[0].tags : [];
  const updatedSeen = addUniqueTags(seen, newTags);
  return collectAllTagsHelper(laps.slice(1), updatedSeen);
}

export function collectAllTags(laps: Lap[]): string[] {
  return collectAllTagsHelper(laps, []);
}

// ═══════════════════════════════════════════════════════════════
// Section aggregation
// ═══════════════════════════════════════════════════════════════

//@ pure
export function sumBySection(laps: Lap[], section: string): number {
  //@ decreases laps.length
  if (laps.length === 0) return 0;
  const rest = sumBySection(laps.slice(1), section);
  if (laps[0].selected && laps[0].section === section) {
    return laps[0].duration + rest;
  }
  return rest;
}

//@ pure
export function countBySection(laps: Lap[], section: string): number {
  //@ decreases laps.length
  //@ ensures \result >= 0
  if (laps.length === 0) return 0;
  const rest = countBySection(laps.slice(1), section);
  if (laps[0].selected && laps[0].section === section) {
    return 1 + rest;
  }
  return rest;
}

//@ pure
function minBySectionHelper(laps: Lap[], section: string, currentMin: number): number {
  //@ decreases laps.length
  //@ requires lapsValid(laps)
  //@ requires currentMin >= -1
  //@ ensures \result >= -1
  if (laps.length === 0) return currentMin;
  if (laps[0].selected && laps[0].section === section) {
    const newMin = currentMin === -1
      ? laps[0].duration
      : (laps[0].duration < currentMin ? laps[0].duration : currentMin);
    return minBySectionHelper(laps.slice(1), section, newMin);
  }
  return minBySectionHelper(laps.slice(1), section, currentMin);
}

export function minBySection(laps: Lap[], section: string): number {
  //@ requires lapsValid(laps)
  //@ ensures \result >= -1
  return minBySectionHelper(laps, section, -1);
}

//@ pure
function maxBySectionHelper(laps: Lap[], section: string, currentMax: number): number {
  //@ decreases laps.length
  //@ requires lapsValid(laps)
  //@ requires currentMax >= -1
  //@ ensures \result >= -1
  if (laps.length === 0) return currentMax;
  if (laps[0].selected && laps[0].section === section) {
    const newMax = laps[0].duration > currentMax ? laps[0].duration : currentMax;
    return maxBySectionHelper(laps.slice(1), section, newMax);
  }
  return maxBySectionHelper(laps.slice(1), section, currentMax);
}

export function maxBySection(laps: Lap[], section: string): number {
  //@ requires lapsValid(laps)
  //@ ensures \result >= -1
  return maxBySectionHelper(laps, section, -1);
}

//@ pure
function collectAllSectionsHelper(laps: Lap[], seen: string[]): string[] {
  //@ decreases laps.length
  if (laps.length === 0) return seen;
  if (laps[0].selected && laps[0].section !== '') {
    const section = laps[0].section;
    const updatedSeen = seen.includes(section) ? seen : [...seen, section];
    return collectAllSectionsHelper(laps.slice(1), updatedSeen);
  }
  return collectAllSectionsHelper(laps.slice(1), seen);
}

export function collectAllSections(laps: Lap[]): string[] {
  return collectAllSectionsHelper(laps, []);
}

// ═══════════════════════════════════════════════════════════════
// Running totals
// ═══════════════════════════════════════════════════════════════

//@ pure
function runningTotalsHelper(laps: Lap[], acc: number): number[] {
  //@ decreases laps.length
  //@ ensures \result.length === laps.length
  if (laps.length === 0) return [];
  const newAcc = laps[0].selected ? acc + laps[0].duration : acc;
  return [acc, ...runningTotalsHelper(laps.slice(1), newAcc)];
}

export function runningTotals(laps: Lap[]): number[] {
  //@ ensures \result.length === laps.length
  return runningTotalsHelper(laps, 0);
}

// ═══════════════════════════════════════════════════════════════
// History (Kernel-pattern; mirrors Replay.dfy)
// ═══════════════════════════════════════════════════════════════

export interface History {
  past: Model[];
  present: Model;
  future: Model[];
}

//@ pure
export function histInv(h: History): boolean {
  return h.past.every(inv) && inv(h.present) && h.future.every(inv);
}

export function initHistory(): History {
  //@ ensures histInv(\result)
  return { past: [], present: init(), future: [] };
}

export function doAction(h: History, a: Action): History {
  //@ requires histInv(h)
  //@ ensures histInv(\result)
  return { past: [...h.past, h.present], present: apply(h.present, a), future: [] };
}

export function preview(h: History, a: Action): History {
  //@ requires histInv(h)
  //@ ensures histInv(\result)
  return { past: h.past, present: apply(h.present, a), future: h.future };
}

export function commitFrom(h: History, baseline: Model): History {
  //@ requires histInv(h)
  //@ requires inv(baseline)
  //@ ensures histInv(\result)
  return { past: [...h.past, baseline], present: h.present, future: [] };
}

export function undo(h: History): History {
  //@ requires histInv(h)
  //@ ensures histInv(\result)
  if (h.past.length === 0) return h;
  const i = h.past.length - 1;
  return { past: h.past.slice(0, i), present: h.past[i], future: [h.present, ...h.future] };
}

export function redo(h: History): History {
  //@ requires histInv(h)
  //@ ensures histInv(\result)
  if (h.future.length === 0) return h;
  return { past: [...h.past, h.present], present: h.future[0], future: h.future.slice(1) };
}
