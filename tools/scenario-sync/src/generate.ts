import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type {
  NormalizedChoiceRow,
  NormalizedEventRow,
  NormalizedScenarioRow,
  NormalizedSheets,
  StoryChoice,
  StoryChoiceGroup,
  StoryContentBundle,
  StoryEvent,
  StoryEventCondition,
  StoryNode,
  StoryScenario,
} from './types.js';
import { GENERATED_MARKER } from './types.js';

export type GeneratedArtifacts = StoryContentBundle;

/** Convert normalized CMS data into the sole app-facing content bundle. */
export function generate(data: NormalizedSheets): StoryContentBundle {
  return {
    _generated: GENERATED_MARKER,
    scenarios: generateScenarios(data.scenarios),
    choiceGroups: generateChoiceGroups(data.choices),
    events: generateEvents(data.events),
  };
}

function generateScenarios(rows: NormalizedScenarioRow[]): StoryScenario[] {
  return [...groupBy(rows, (row) => row.scenarioId)]
    .map(([scenarioId, scenarioRows]) => {
      const ordered = [...scenarioRows].sort(compareScenarioRows);
      return {
        scenarioId,
        scenarioType: ordered[0]!.scenarioType,
        nodes: ordered.map(mapNode),
      };
    })
    .sort((left, right) => compareText(left.scenarioId, right.scenarioId));
}

function mapNode(row: NormalizedScenarioRow): StoryNode {
  return {
    lineOrder: row.lineOrder,
    nodeId: row.nodeId,
    speaker: row.speaker,
    messageType: row.messageType,
    text: row.text,
    choiceId: row.choiceId,
    nextNodeId: row.nextNodeId,
    saveKey: row.saveKey,
    saveValue: row.saveValue,
    assetId: row.assetId,
    minPhase: row.minPhase,
    maxPhase: row.maxPhase,
    speakerName: row.speakerName,
    typingDurationMs: row.typingDurationMs,
    background: row.background,
    portrait: row.portrait,
    cg: row.cg,
    enabled: row.enabled,
    notes: row.notes,
    screenMode: row.screenMode,
    uiVariant: row.uiVariant,
    command: row.command,
    commandArgs: row.commandArgs,
  };
}

function generateChoiceGroups(rows: NormalizedChoiceRow[]): StoryChoiceGroup[] {
  return [...groupBy(rows, (row) => row.choiceId)]
    .map(([choiceId, choices]) => ({
      choiceId,
      choices: [...choices].sort(compareChoiceRows).map(mapChoice),
    }))
    .sort((left, right) => compareText(left.choiceId, right.choiceId));
}

function mapChoice(row: NormalizedChoiceRow): StoryChoice {
  return {
    choiceOrder: row.choiceOrder,
    label: row.label,
    nextNodeId: row.nextNodeId,
    saveKey: row.saveKey,
    saveValue: row.saveValue,
    requiredKey: row.requiredKey,
    requiredOperator: row.requiredOperator,
    requiredValue: row.requiredValue,
    enabled: row.enabled,
    notes: row.notes,
  };
}

function generateEvents(rows: NormalizedEventRow[]): StoryEvent[] {
  return [...groupBy(rows, (row) => row.eventId)]
    .map(([eventId, eventRows]) => {
      const head = [...eventRows].sort((left, right) => left.__row - right.__row)[0]!;
      const conditions = eventRows.map(mapCondition).sort(compareConditions);
      return {
        eventId,
        eventType: head.eventType,
        title: head.title,
        entryScenarioId: head.entryScenarioId,
        priority: head.priority,
        repeatable: head.repeatable,
        cooldownDays: head.cooldownDays,
        background: head.background,
        advancesToPhase: head.advancesToPhase,
        enabled: head.enabled,
        notes: head.notes,
        chapterId: head.chapterId,
        episodeOrder: head.episodeOrder,
        storyCategory: head.storyCategory,
        conditions,
      };
    })
    .sort(compareEvents);
}

function mapCondition(row: NormalizedEventRow): StoryEventCondition {
  return {
    conditionType: row.conditionType,
    conditionKey: row.conditionKey,
    operator: row.operator,
    threshold: row.threshold,
  };
}

function compareScenarioRows(left: NormalizedScenarioRow, right: NormalizedScenarioRow): number {
  return left.lineOrder - right.lineOrder || compareText(left.nodeId, right.nodeId);
}

function compareChoiceRows(left: NormalizedChoiceRow, right: NormalizedChoiceRow): number {
  return (
    left.choiceOrder - right.choiceOrder ||
    compareText(left.label, right.label) ||
    compareText(left.nextNodeId ?? '', right.nextNodeId ?? '')
  );
}

function compareConditions(left: StoryEventCondition, right: StoryEventCondition): number {
  return (
    compareText(left.conditionType, right.conditionType) ||
    compareText(left.conditionKey, right.conditionKey) ||
    compareText(left.operator, right.operator) ||
    compareText(left.threshold, right.threshold)
  );
}

function compareEvents(left: StoryEvent, right: StoryEvent): number {
  return (
    compareOptionalText(left.chapterId, right.chapterId) ||
    compareOptionalNumber(left.episodeOrder, right.episodeOrder) ||
    left.priority - right.priority ||
    compareText(left.eventId, right.eventId)
  );
}

function compareOptionalText(left: string | undefined, right: string | undefined): number {
  if (left === undefined) return right === undefined ? 0 : 1;
  if (right === undefined) return -1;
  return compareText(left, right);
}

function compareOptionalNumber(left: number | undefined, right: number | undefined): number {
  if (left === undefined) return right === undefined ? 0 : 1;
  if (right === undefined) return -1;
  return left - right;
}

function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function groupBy<T>(rows: T[], key: (row: T) => string): Map<string, T[]> {
  const groups = new Map<string, T[]>();
  for (const row of rows) {
    const values = groups.get(key(row)) ?? [];
    values.push(row);
    groups.set(key(row), values);
  }
  return groups;
}

/** Deterministic, human-readable JSON with a single trailing newline. */
export function serialize(value: unknown): string {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export interface WritePlan {
  path: string;
  next: string;
  previous: string | null;
  changed: boolean;
}

/** Read-only comparison used by both --check and --write. */
export function planWrite(path: string, content: string): WritePlan {
  const previous = existsSync(path) ? readFileSync(path, 'utf8') : null;
  return { path, next: content, previous, changed: previous !== content };
}

/**
 * Commit changed artifacts using same-directory temporary files and rename.
 * With the current single bundle, readers can only observe the old or new file.
 */
export function commitWrites(plans: WritePlan[]): void {
  const changed = plans.filter((plan) => plan.changed);
  const staged = new Map<string, string>();

  try {
    for (let index = 0; index < changed.length; index += 1) {
      const plan = changed[index]!;
      mkdirSync(dirname(plan.path), { recursive: true });
      const temporaryPath = `${plan.path}.tmp-${process.pid}-${index}`;
      writeFileSync(temporaryPath, plan.next, { encoding: 'utf8', flag: 'wx' });
      staged.set(plan.path, temporaryPath);
    }
    for (const plan of changed) {
      renameSync(staged.get(plan.path)!, plan.path);
      staged.delete(plan.path);
    }
  } catch (error) {
    for (const temporaryPath of staged.values()) {
      try {
        rmSync(temporaryPath, { force: true });
      } catch {
        // Preserve the original error; cleanup is best-effort only.
      }
    }
    throw error;
  }
}
