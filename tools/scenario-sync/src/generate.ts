import { mkdirSync, writeFileSync, renameSync, rmSync, existsSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type {
  NormalizedSheets,
  NormalizedScenarioRow,
  NormalizedChoiceRow,
  NormalizedEventConditionRow,
  AppMessage,
  AppChoice,
  AppEvent,
  AppEventCondition,
  AppDailyScenario,
  AppDailyBundle,
  AppEventBundle,
} from './types.js';
import { GENERATED_MARKER } from './types.js';
import { METRIC_CONDITION_KEYS, EVENT_COMPLETED_KEYS, type AppConditionFields } from './schema.js';

export interface GeneratedArtifacts {
  daily: AppDailyBundle;
  events: AppEventBundle;
}

// --- normalized -> app shape -------------------------------------------------

function mapMessage(
  row: NormalizedScenarioRow,
  choicesByGroup: Map<string, NormalizedChoiceRow[]>,
): AppMessage {
  const msg: AppMessage = {
    id: row.nodeId,
    speaker: row.speaker === 'user' ? 'user' : 'character',
    text: row.text,
  };
  if (row.messageType === 'image') {
    msg.type = 'image';
    if (row.assetId) msg.imageName = row.assetId;
  }
  if (row.messageType === 'choice' && row.choiceId) {
    const options = choicesByGroup.get(row.choiceId) ?? [];
    msg.choices = options.map(mapChoice);
  }
  if (row.nextNodeId) msg.next = row.nextNodeId;
  if (row.save) msg.saveFact = { key: row.save.key, value: row.save.value };
  if (row.minPhase !== undefined) msg.minPhase = row.minPhase;
  if (row.maxPhase !== undefined) msg.maxPhase = row.maxPhase;
  if (row.speakerName) msg.speakerName = row.speakerName;
  if (row.background) msg.background = row.background;
  if (row.portrait) msg.portrait = row.portrait;
  if (row.cg) msg.cg = row.cg;
  return msg;
}

function mapChoice(row: NormalizedChoiceRow): AppChoice {
  const choice: AppChoice = { text: row.label };
  if (row.nextNodeId) choice.next = row.nextNodeId;
  if (row.save) choice.saveFact = { key: row.save.key, value: row.save.value };
  if (row.requirement) {
    choice.requirement = {
      key: row.requirement.key,
      operator: row.requirement.operator,
      value: row.requirement.value,
    };
  }
  return choice;
}

function scenarioMessages(
  scenarioId: string,
  data: NormalizedSheets,
  choicesByGroup: Map<string, NormalizedChoiceRow[]>,
): AppMessage[] {
  return data.scenarios
    .filter((r) => r.scenarioId === scenarioId)
    .sort((a, b) => a.lineOrder - b.lineOrder)
    .map((r) => mapMessage(r, choicesByGroup));
}

function buildEventCondition(rows: NormalizedEventConditionRow[]): AppEventCondition {
  const metrics: Partial<AppConditionFields> = {};
  const completed = new Set<string>();

  for (const row of rows) {
    if (EVENT_COMPLETED_KEYS.has(row.conditionKey)) {
      completed.add(row.threshold);
      continue;
    }
    const field = METRIC_CONDITION_KEYS[row.conditionKey];
    if (!field) continue; // validate() already reported this
    const base = Number.parseInt(row.threshold, 10);
    const value = row.operator === 'gt' ? base + 1 : base;
    metrics[field] = Math.max(metrics[field] ?? 0, value);
  }

  const cond: AppEventCondition = {};
  if (metrics.minTrust !== undefined) cond.minTrust = metrics.minTrust;
  if (metrics.minStreakDays !== undefined) cond.minStreakDays = metrics.minStreakDays;
  if (metrics.minBlockedProtectedCount !== undefined)
    cond.minBlockedProtectedCount = metrics.minBlockedProtectedCount;
  if (metrics.minMasteredCount !== undefined) cond.minMasteredCount = metrics.minMasteredCount;
  if (metrics.minRelationshipPhase !== undefined)
    cond.minRelationshipPhase = metrics.minRelationshipPhase;
  if (completed.size > 0) cond.requiredCompletedEventIds = [...completed].sort();
  return cond;
}

export function generate(data: NormalizedSheets): GeneratedArtifacts {
  const choicesByGroup = new Map<string, NormalizedChoiceRow[]>();
  for (const row of data.choices) {
    if (!choicesByGroup.has(row.choiceId)) choicesByGroup.set(row.choiceId, []);
    choicesByGroup.get(row.choiceId)!.push(row);
  }
  for (const options of choicesByGroup.values()) {
    options.sort((a, b) => a.choiceOrder - b.choiceOrder);
  }

  // --- daily ---
  const dailyIds = [
    ...new Set(data.scenarios.filter((r) => r.scenarioType === 'daily').map((r) => r.scenarioId)),
  ].sort();
  const scenarios: AppDailyScenario[] = dailyIds.map((scenarioId, idx) => ({
    scenarioId,
    dayIndex: idx + 1,
    messages: scenarioMessages(scenarioId, data, choicesByGroup),
  }));

  // --- events ---
  const eventGroups = new Map<string, NormalizedEventConditionRow[]>();
  for (const row of data.events) {
    if (!eventGroups.has(row.eventId)) eventGroups.set(row.eventId, []);
    eventGroups.get(row.eventId)!.push(row);
  }
  const events: AppEvent[] = [...eventGroups.entries()]
    .map(([eventId, rows]) => {
      const head = rows[0]!;
      const event: AppEvent = {
        eventId,
        eventType: head.eventType === 'large_event' ? 'big' : 'small',
        title: head.title,
        priority: head.priority,
        repeatable: head.repeatable,
        cooldownDays: head.cooldownDays,
        unlockConditions: buildEventCondition(rows),
        messages: scenarioMessages(head.entryScenarioId, data, choicesByGroup),
      };
      if (head.background) event.background = head.background;
      if (head.advancesToPhase !== undefined) event.advancesToPhase = head.advancesToPhase;
      return event;
    })
    .sort((a, b) => a.priority - b.priority || a.eventId.localeCompare(b.eventId));

  return {
    daily: { _generated: GENERATED_MARKER, scenarios },
    events: { _generated: GENERATED_MARKER, events },
  };
}

// --- serialization + atomic write -----------------------------------------

/** Deterministic pretty JSON: object keys are already inserted in canonical order. */
export function serialize(value: unknown): string {
  return JSON.stringify(value, null, 2) + '\n';
}

export interface WritePlan {
  path: string;
  next: string;
  previous: string | null;
  changed: boolean;
}

export function planWrite(path: string, content: string): WritePlan {
  const previous = existsSync(path) ? readFileSync(path, 'utf8') : null;
  return { path, next: content, previous, changed: previous !== content };
}

/**
 * Write all files atomically: every file goes to a `.tmp` sibling first, and
 * only once all of them succeed are they renamed into place. A failure part-way
 * leaves the existing good files untouched.
 */
export function commitWrites(plans: WritePlan[]): void {
  const temps: string[] = [];
  try {
    for (const plan of plans) {
      mkdirSync(dirname(plan.path), { recursive: true });
      const tmp = `${plan.path}.tmp`;
      writeFileSync(tmp, plan.next, 'utf8');
      temps.push(tmp);
    }
    for (const tmp of temps) {
      renameSync(tmp, tmp.replace(/\.tmp$/, ''));
    }
  } catch (err) {
    for (const tmp of temps) {
      try {
        if (existsSync(tmp)) rmSync(tmp);
      } catch {
        /* best effort cleanup */
      }
    }
    throw err;
  }
}
