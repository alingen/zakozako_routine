import { existsSync, readFileSync } from 'node:fs';
import type {
  AppDailyBundle,
  AppEventBundle,
  AppDailyScenario,
  AppEvent,
  AppMessage,
  AppChoice,
} from './types.js';
import { truncate } from './issues.js';

export interface DiffLine {
  kind: 'added' | 'removed' | 'changed';
  scope: 'scenario' | 'event' | 'choice';
  id: string;
  detail: string;
  /** Marked when a human should look twice (deletions, disables, big jumps). */
  impactful?: boolean;
}

export interface DiffReport {
  lines: DiffLine[];
  counts: {
    scenario: { added: number; removed: number; changed: number };
    event: { added: number; removed: number; changed: number };
    choice: { added: number; removed: number; changed: number };
  };
  get hasChanges(): boolean;
}

function readBundle<T>(path: string): T | null {
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as T;
  } catch {
    return null;
  }
}

function messageMap(messages: AppMessage[]): Map<string, AppMessage> {
  return new Map(messages.map((m) => [m.id, m]));
}

function choiceKey(c: AppChoice, idx: number): string {
  return `#${idx}:${c.text}`;
}

function condSummary(e: AppEvent): string {
  const c = e.unlockConditions;
  const parts: string[] = [];
  if (c.minTrust !== undefined) parts.push(`信頼度>=${c.minTrust}`);
  if (c.minStreakDays !== undefined) parts.push(`継続>=${c.minStreakDays}`);
  if (c.minBlockedProtectedCount !== undefined)
    parts.push(`やらないこと>=${c.minBlockedProtectedCount}`);
  if (c.minMasteredCount !== undefined) parts.push(`卒業>=${c.minMasteredCount}`);
  if (c.minRelationshipPhase !== undefined) parts.push(`Phase>=${c.minRelationshipPhase}`);
  if (c.requiredCompletedEventIds?.length)
    parts.push(`前提:${c.requiredCompletedEventIds.join(',')}`);
  return parts.length ? parts.join(' & ') : '条件なし';
}

function diffMessages(
  scope: DiffLine['scope'],
  id: string,
  before: AppMessage[],
  after: AppMessage[],
  lines: DiffLine[],
): boolean {
  let changed = false;
  const beforeMap = messageMap(before);
  const afterMap = messageMap(after);

  for (const [nodeId, b] of beforeMap) {
    const a = afterMap.get(nodeId);
    if (!a) {
      lines.push({
        kind: 'removed',
        scope,
        id: `${id}/${nodeId}`,
        detail: `ノード削除: "${truncate(b.text)}"`,
        impactful: true,
      });
      changed = true;
      continue;
    }
    if (b.text !== a.text) {
      lines.push({
        kind: 'changed',
        scope,
        id: `${id}/${nodeId}`,
        detail: `テキスト変更\n      before: ${truncate(b.text, 200)}\n      after : ${truncate(a.text, 200)}`,
      });
      changed = true;
    }
    if ((b.next ?? '') !== (a.next ?? '')) {
      lines.push({
        kind: 'changed',
        scope,
        id: `${id}/${nodeId}`,
        detail: `遷移先: ${b.next ?? '(次の行)'} → ${a.next ?? '(次の行)'}`,
      });
      changed = true;
    }
    if (JSON.stringify(b.saveFact) !== JSON.stringify(a.saveFact)) {
      lines.push({
        kind: 'changed',
        scope,
        id: `${id}/${nodeId}`,
        detail: `保存値: ${fmt(b.saveFact)} → ${fmt(a.saveFact)}`,
      });
      changed = true;
    }
    if ((b.minPhase ?? '') !== (a.minPhase ?? '') || (b.maxPhase ?? '') !== (a.maxPhase ?? '')) {
      lines.push({
        kind: 'changed',
        scope,
        id: `${id}/${nodeId}`,
        detail: `表示フェーズ条件: ${b.minPhase ?? '-'}..${b.maxPhase ?? '-'} → ${a.minPhase ?? '-'}..${a.maxPhase ?? '-'}`,
      });
      changed = true;
    }
    changed =
      diffChoices(scope, `${id}/${nodeId}`, b.choices ?? [], a.choices ?? [], lines) || changed;
  }
  for (const [nodeId, a] of afterMap) {
    if (!beforeMap.has(nodeId)) {
      lines.push({
        kind: 'added',
        scope,
        id: `${id}/${nodeId}`,
        detail: `ノード追加: "${truncate(a.text)}"`,
      });
      changed = true;
    }
  }
  return changed;
}

function diffChoices(
  scope: DiffLine['scope'],
  id: string,
  before: AppChoice[],
  after: AppChoice[],
  lines: DiffLine[],
): boolean {
  let changed = false;
  const beforeKeys = before.map(choiceKey);
  const afterKeys = after.map(choiceKey);
  before.forEach((c, i) => {
    if (!afterKeys.includes(choiceKey(c, i))) {
      lines.push({
        kind: 'removed',
        scope: 'choice',
        id: `${id}[${i}]`,
        detail: `選択肢削除: "${c.text}"`,
        impactful: true,
      });
      changed = true;
    }
  });
  after.forEach((c, i) => {
    const b = before[i];
    if (!beforeKeys.includes(choiceKey(c, i))) {
      lines.push({
        kind: 'added',
        scope: 'choice',
        id: `${id}[${i}]`,
        detail: `選択肢追加: "${c.text}"`,
      });
      changed = true;
      return;
    }
    if (b && (b.next ?? '') !== (c.next ?? '')) {
      lines.push({
        kind: 'changed',
        scope: 'choice',
        id: `${id}[${i}]`,
        detail: `遷移先: ${b.next ?? '(次)'} → ${c.next ?? '(次)'}`,
      });
      changed = true;
    }
    if (b && JSON.stringify(b.saveFact) !== JSON.stringify(c.saveFact)) {
      lines.push({
        kind: 'changed',
        scope: 'choice',
        id: `${id}[${i}]`,
        detail: `保存値: ${fmt(b.saveFact)} → ${fmt(c.saveFact)}`,
      });
      changed = true;
    }
  });
  return changed;
}

function fmt(v: unknown): string {
  return v === undefined ? '(なし)' : JSON.stringify(v);
}

export function diff(
  dailyPath: string,
  eventsPath: string,
  next: { daily: AppDailyBundle; events: AppEventBundle },
): DiffReport {
  const prevDaily = readBundle<AppDailyBundle>(dailyPath);
  const prevEvents = readBundle<AppEventBundle>(eventsPath);
  const lines: DiffLine[] = [];
  const counts = {
    scenario: { added: 0, removed: 0, changed: 0 },
    event: { added: 0, removed: 0, changed: 0 },
    choice: { added: 0, removed: 0, changed: 0 },
  };

  // scenarios
  const prevScn = new Map<string, AppDailyScenario>(
    (prevDaily?.scenarios ?? []).map((s) => [s.scenarioId, s]),
  );
  const nextScn = new Map<string, AppDailyScenario>(
    next.daily.scenarios.map((s) => [s.scenarioId, s]),
  );
  for (const [id, b] of prevScn) {
    if (!nextScn.has(id)) {
      lines.push({
        kind: 'removed',
        scope: 'scenario',
        id,
        detail: `シナリオ削除 (Day${b.dayIndex})`,
        impactful: true,
      });
      counts.scenario.removed++;
    }
  }
  for (const [id, a] of nextScn) {
    const b = prevScn.get(id);
    if (!b) {
      lines.push({
        kind: 'added',
        scope: 'scenario',
        id,
        detail: `シナリオ追加 (Day${a.dayIndex}, ${a.messages.length}メッセージ)`,
      });
      counts.scenario.added++;
      continue;
    }
    const before = lines.length;
    const changed = diffMessages('scenario', id, b.messages, a.messages, lines);
    if (b.dayIndex !== a.dayIndex) {
      lines.push({
        kind: 'changed',
        scope: 'scenario',
        id,
        detail: `Day番号: ${b.dayIndex} → ${a.dayIndex}`,
        impactful: true,
      });
    }
    if (changed || b.dayIndex !== a.dayIndex) counts.scenario.changed++;
    countByScope(lines.slice(before), counts);
  }

  // events
  const prevEv = new Map<string, AppEvent>((prevEvents?.events ?? []).map((e) => [e.eventId, e]));
  const nextEv = new Map<string, AppEvent>(next.events.events.map((e) => [e.eventId, e]));
  for (const [id, b] of prevEv) {
    if (!nextEv.has(id)) {
      lines.push({
        kind: 'removed',
        scope: 'event',
        id,
        detail: `イベント削除 "${b.title}"`,
        impactful: true,
      });
      counts.event.removed++;
    }
  }
  for (const [id, a] of nextEv) {
    const b = prevEv.get(id);
    if (!b) {
      lines.push({
        kind: 'added',
        scope: 'event',
        id,
        detail: `イベント追加 "${a.title}" [${condSummary(a)}]`,
      });
      counts.event.added++;
      continue;
    }
    let changed = false;
    if (b.title !== a.title) {
      lines.push({
        kind: 'changed',
        scope: 'event',
        id,
        detail: `タイトル: "${b.title}" → "${a.title}"`,
      });
      changed = true;
    }
    if (condSummary(b) !== condSummary(a)) {
      lines.push({
        kind: 'changed',
        scope: 'event',
        id,
        detail: `解放条件: [${condSummary(b)}] → [${condSummary(a)}]`,
        impactful: true,
      });
      changed = true;
    }
    if ((b.advancesToPhase ?? -1) !== (a.advancesToPhase ?? -1)) {
      lines.push({
        kind: 'changed',
        scope: 'event',
        id,
        detail: `関係フェーズ前進: ${b.advancesToPhase ?? 'なし'} → ${a.advancesToPhase ?? 'なし'}`,
        impactful: true,
      });
      changed = true;
    }
    if (b.eventType !== a.eventType) {
      lines.push({
        kind: 'changed',
        scope: 'event',
        id,
        detail: `種別: ${b.eventType} → ${a.eventType}`,
        impactful: true,
      });
      changed = true;
    }
    const before = lines.length;
    changed = diffMessages('event', id, b.messages, a.messages, lines) || changed;
    if (changed) counts.event.changed++;
    countByScope(lines.slice(before), counts);
  }

  return {
    lines,
    counts,
    get hasChanges() {
      return this.lines.length > 0;
    },
  };
}

function countByScope(lines: DiffLine[], counts: DiffReport['counts']): void {
  for (const l of lines) {
    if (l.scope === 'choice') {
      if (l.kind === 'added') counts.choice.added++;
      else if (l.kind === 'removed') counts.choice.removed++;
      else counts.choice.changed++;
    }
  }
}

export function renderDiff(report: DiffReport): string {
  if (!report.hasChanges) return '差分なし（生成物は最新です）。';
  const c = report.counts;
  const head =
    `変更サマリー:\n` +
    `  シナリオ: +${c.scenario.added} / ~${c.scenario.changed} / -${c.scenario.removed}\n` +
    `  イベント: +${c.event.added} / ~${c.event.changed} / -${c.event.removed}\n` +
    `  選択肢  : +${c.choice.added} / ~${c.choice.changed} / -${c.choice.removed}`;

  const impactful = report.lines.filter((l) => l.impactful);
  const warn = impactful.length
    ? `\n\n⚠️  影響の大きい変更:\n` +
      impactful.map((l) => `  - [${l.scope}] ${l.id}: ${l.detail}`).join('\n')
    : '';

  const detail =
    `\n\n詳細:\n` +
    report.lines
      .map((l) => {
        const mark = l.kind === 'added' ? '+' : l.kind === 'removed' ? '-' : '~';
        return `  ${mark} [${l.scope}] ${l.id}: ${l.detail}`;
      })
      .join('\n');

  return head + warn + detail;
}
