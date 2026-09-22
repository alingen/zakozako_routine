import type {
  JsonValue,
  NormalizedChoiceRow,
  NormalizedDailyCatalogRow,
  NormalizedEventRow,
  NormalizedInteractionRow,
  NormalizedScenarioRow,
  NormalizedSheets,
  RawRow,
  RawSheets,
} from './types.js';
import { IssueBag } from './issues.js';
import {
  CHOICE_COLUMNS,
  DAILY_CATALOG_COLUMNS,
  DAILY_COLUMNS,
  EVENT_COLUMNS,
  INTERACTION_COLUMNS,
  REQUIRED_CHOICE_COLUMNS,
  REQUIRED_DAILY_CATALOG_COLUMNS,
  REQUIRED_DAILY_COLUMNS,
  REQUIRED_EVENT_COLUMNS,
  REQUIRED_INTERACTION_COLUMNS,
  REQUIRED_SCENARIO_COLUMNS,
  SCENARIO_COLUMNS,
  isBlank,
} from './schema.js';

export interface NormalizeResult {
  data: NormalizedSheets;
  issues: IssueBag;
}

function sourceString(row: RawRow, column: string): string {
  const value = row[column];
  return value === undefined || value === null ? '' : String(value);
}

function trimmed(row: RawRow, column: string): string {
  return sourceString(row, column).trim();
}

function optionalString(row: RawRow, column: string): string | undefined {
  const value = trimmed(row, column);
  return value === '' ? undefined : value;
}

function requiredString(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  column: string,
): string | undefined {
  const value = trimmed(row, column);
  if (value !== '') return value;
  bag.error('missing_required', `${column} is required`, {
    at: { sheet, row: row.__row, column },
  });
  return undefined;
}

function integer(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  column: string,
  required: boolean,
): number | undefined {
  const value = trimmed(row, column);
  if (value === '') {
    if (required) {
      bag.error('missing_required', `${column} is required`, {
        at: { sheet, row: row.__row, column },
      });
    }
    return undefined;
  }
  if (!/^-?\d+$/.test(value)) {
    bag.error('invalid_integer', `${column} must be an integer`, {
      at: { sheet, row: row.__row, column },
      value,
    });
    return undefined;
  }
  return Number.parseInt(value, 10);
}

function booleanValue(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  column: string,
  fallback: boolean,
): boolean {
  const value = trimmed(row, column).toLowerCase();
  if (value === '') return fallback;
  if (['true', '1', 'yes'].includes(value)) return true;
  if (['false', '0', 'no'].includes(value)) return false;
  bag.error('invalid_boolean', `${column} must be TRUE or FALSE`, {
    at: { sheet, row: row.__row, column },
    value,
  });
  return fallback;
}

function validatePair(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  first: string,
  second: string,
): void {
  const firstBlank = isBlank(row[first]);
  const secondBlank = isBlank(row[second]);
  if (firstBlank === secondBlank) return;
  bag.error('incomplete_pair', `${first} and ${second} must be supplied together`, {
    at: { sheet, row: row.__row, column: firstBlank ? first : second },
  });
}

function parseCommandArgs(
  bag: IssueBag,
  sheet: 'daily' | 'senarios',
  row: RawRow,
): JsonValue | undefined {
  const raw = trimmed(row, 'command_args');
  if (!raw) return undefined;
  try {
    const parsed = JSON.parse(raw) as JsonValue;
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      bag.error('command_args_not_object', 'command_args must be a JSON object at the top level', {
        at: { sheet, row: row.__row, column: 'command_args' },
        value: raw,
      });
    }
    return parsed;
  } catch (error) {
    bag.error('invalid_command_args', 'command_args is not valid JSON', {
      at: { sheet, row: row.__row, column: 'command_args' },
      value: raw,
      fix: error instanceof Error ? error.message : undefined,
    });
    return undefined;
  }
}

function checkColumns(
  bag: IssueBag,
  sheet: string,
  rows: RawRow[],
  known: readonly string[],
  required: readonly string[],
): void {
  if (rows.length === 0) return;
  const headers = Object.keys(rows[0] ?? {}).filter((key) => key !== '__row');
  for (const column of required) {
    if (!headers.includes(column)) {
      bag.error('missing_column', `Required column ${column} is missing`, {
        at: { sheet, row: 1, column },
      });
    }
  }
  for (const column of headers) {
    if (!known.includes(column)) {
      bag.warning('unknown_column', `Unknown column ${column} is preserved only in the sheet`, {
        at: { sheet, row: 1, column },
      });
    }
  }
}

function normalizeScenarioRows(
  bag: IssueBag,
  rows: RawRow[],
  sheet: 'daily' | 'senarios',
): NormalizedScenarioRow[] {
  const isDaily = sheet === 'daily';
  checkColumns(
    bag,
    sheet,
    rows,
    isDaily ? DAILY_COLUMNS : SCENARIO_COLUMNS,
    isDaily ? REQUIRED_DAILY_COLUMNS : REQUIRED_SCENARIO_COLUMNS,
  );
  const normalized: NormalizedScenarioRow[] = [];

  for (const row of rows) {
    const enabled = booleanValue(bag, sheet, row, 'enabled', true);
    if (!enabled) continue;

    const scenarioId = requiredString(bag, sheet, row, 'scenario_id');
    const scenarioType = isDaily ? 'daily' : requiredString(bag, sheet, row, 'scenario_type');
    const lineOrder = integer(bag, sheet, row, 'line_order', true);
    const nodeId = requiredString(bag, sheet, row, 'node_id');
    const speaker = requiredString(bag, sheet, row, 'speaker');
    const messageType = requiredString(bag, sheet, row, 'message_type');
    validatePair(bag, sheet, row, 'save_key', 'save_value');

    const minPhase = integer(bag, sheet, row, 'min_phase', false);
    const maxPhase = integer(bag, sheet, row, 'max_phase', false);
    const typingDurationMs = integer(bag, sheet, row, 'typing_duration_ms', false);
    const commandArgs = parseCommandArgs(bag, sheet, row);

    if (
      !scenarioId ||
      !scenarioType ||
      lineOrder === undefined ||
      !nodeId ||
      !speaker ||
      !messageType
    ) {
      continue;
    }

    normalized.push({
      __row: row.__row,
      sourceSheet: sheet,
      scenarioId,
      scenarioType,
      lineOrder,
      nodeId,
      speaker,
      messageType,
      text: sourceString(row, 'text'),
      choiceId: optionalString(row, 'choice_id'),
      nextNodeId: optionalString(row, 'next_node_id'),
      saveKey: optionalString(row, 'save_key'),
      saveValue: optionalString(row, 'save_value'),
      assetId: optionalString(row, 'asset_id'),
      minPhase,
      maxPhase,
      speakerName: optionalString(row, 'speaker_name'),
      typingDurationMs,
      background: optionalString(row, 'background'),
      portrait: optionalString(row, 'portrait'),
      cg: optionalString(row, 'cg'),
      enabled: true,
      notes: optionalString(row, 'notes'),
      screenMode: optionalString(row, 'screen_mode'),
      uiVariant: optionalString(row, 'ui_variant'),
      command: optionalString(row, 'command'),
      commandArgs,
    });
  }
  return normalized;
}

function isBlankCatalogPlaceholder(row: RawRow): boolean {
  const contentColumns = DAILY_CATALOG_COLUMNS.filter((column) => column !== 'enabled');
  if (contentColumns.some((column) => !isBlank(row[column]))) return false;

  const enabled = trimmed(row, 'enabled').toLowerCase();
  return enabled === '' || ['false', '0', 'no'].includes(enabled);
}

function normalizeDailyCatalog(bag: IssueBag, rows: RawRow[]): NormalizedDailyCatalogRow[] {
  const sheet = 'daily_catalog';
  checkColumns(bag, sheet, rows, DAILY_CATALOG_COLUMNS, REQUIRED_DAILY_CATALOG_COLUMNS);
  const normalized: NormalizedDailyCatalogRow[] = [];

  for (const row of rows) {
    // Google Sheets checkbox validation can materialize otherwise blank rows as
    // enabled=FALSE. They are formatting placeholders, not authored catalog rows.
    if (isBlankCatalogPlaceholder(row)) continue;

    const scenarioId = requiredString(bag, sheet, row, 'scenario_id');
    const title = requiredString(bag, sheet, row, 'title');
    const displayOrder = integer(bag, sheet, row, 'display_order', false);
    const status = requiredString(bag, sheet, row, 'status');
    const enabled = booleanValue(bag, sheet, row, 'enabled', true);

    if (!scenarioId || !title || !status) continue;
    normalized.push({
      __row: row.__row,
      scenarioId,
      title,
      displayOrder,
      category: optionalString(row, 'category'),
      calendarDate: optionalString(row, 'calendar_date'),
      calendarMonthDay: optionalString(row, 'calendar_month_day'),
      status,
      enabled,
    });
  }
  return normalized;
}

function normalizeChoices(bag: IssueBag, rows: RawRow[]): NormalizedChoiceRow[] {
  const sheet = 'choices';
  checkColumns(bag, sheet, rows, CHOICE_COLUMNS, REQUIRED_CHOICE_COLUMNS);
  const normalized: NormalizedChoiceRow[] = [];

  for (const row of rows) {
    const enabled = booleanValue(bag, sheet, row, 'enabled', true);
    if (!enabled) continue;

    const dailyId = requiredString(bag, sheet, row, 'daily_id');
    const choiceId = requiredString(bag, sheet, row, 'choice_id');
    const choiceOrder = integer(bag, sheet, row, 'choice_order', true);
    const label = requiredString(bag, sheet, row, 'label');
    validatePair(bag, sheet, row, 'save_key', 'save_value');

    if (!dailyId || !choiceId || choiceOrder === undefined || !label) continue;
    normalized.push({
      __row: row.__row,
      dailyId,
      choiceId,
      choiceOrder,
      label,
      nextNodeId: optionalString(row, 'next_node_id'),
      saveKey: optionalString(row, 'save_key'),
      saveValue: optionalString(row, 'save_value'),
      enabled: true,
      notes: optionalString(row, 'notes'),
    });
  }
  return normalized;
}

function normalizeInteractions(bag: IssueBag, rows: RawRow[]): NormalizedInteractionRow[] {
  const sheet = 'interactions';
  checkColumns(bag, sheet, rows, INTERACTION_COLUMNS, REQUIRED_INTERACTION_COLUMNS);
  const normalized: NormalizedInteractionRow[] = [];

  for (const row of rows) {
    const active = booleanValue(bag, sheet, row, 'active', true);
    if (!active) continue;
    const id = requiredString(bag, sheet, row, 'id');
    const text = requiredString(bag, sheet, row, 'text');
    const weight = integer(bag, sheet, row, 'weight', true);
    if (!id || !text || weight === undefined) continue;

    normalized.push({
      __row: row.__row,
      id,
      text,
      condition: optionalString(row, 'condition'),
      timeCondition: optionalString(row, 'time_condition'),
      touchArea: optionalString(row, 'touch_area'),
      weight,
      active: true,
    });
  }
  return normalized;
}

function normalizeEvents(bag: IssueBag, rows: RawRow[]): NormalizedEventRow[] {
  const sheet = 'events';
  checkColumns(bag, sheet, rows, EVENT_COLUMNS, REQUIRED_EVENT_COLUMNS);
  const normalized: NormalizedEventRow[] = [];

  for (const row of rows) {
    const enabled = booleanValue(bag, sheet, row, 'enabled', true);
    if (!enabled) continue;

    const eventId = requiredString(bag, sheet, row, 'event_id');
    const eventType = requiredString(bag, sheet, row, 'event_type');
    const title = requiredString(bag, sheet, row, 'title');
    const entryScenarioId = requiredString(bag, sheet, row, 'entry_scenario_id');
    const priority = integer(bag, sheet, row, 'priority', true);
    const conditionType = requiredString(bag, sheet, row, 'condition_type');
    const conditionKey = requiredString(bag, sheet, row, 'condition_key');
    const operator = requiredString(bag, sheet, row, 'operator');
    const threshold = requiredString(bag, sheet, row, 'threshold');
    const repeatable = booleanValue(bag, sheet, row, 'repeatable', false);
    const cooldownDays = integer(bag, sheet, row, 'cooldown_days', false) ?? 0;
    const advancesToPhase = integer(bag, sheet, row, 'advances_to_phase', false);
    const episodeOrder = integer(bag, sheet, row, 'episode_order', false);

    if (
      !eventId ||
      !eventType ||
      !title ||
      !entryScenarioId ||
      priority === undefined ||
      !conditionType ||
      !conditionKey ||
      !operator ||
      !threshold
    ) {
      continue;
    }

    normalized.push({
      __row: row.__row,
      eventId,
      eventType,
      title,
      entryScenarioId,
      priority,
      repeatable,
      cooldownDays,
      conditionType,
      conditionKey,
      operator,
      threshold,
      background: optionalString(row, 'background'),
      advancesToPhase,
      enabled: true,
      notes: optionalString(row, 'notes'),
      chapterId: optionalString(row, 'chapter_id'),
      episodeOrder,
      storyCategory: optionalString(row, 'story_category'),
    });
  }
  return normalized;
}

export function normalize(raw: RawSheets): NormalizeResult {
  const issues = new IssueBag();
  return {
    data: {
      daily: normalizeScenarioRows(issues, raw.daily, 'daily'),
      dailyCatalog: normalizeDailyCatalog(issues, raw.dailyCatalog),
      choices: normalizeChoices(issues, raw.choices),
      interactions: normalizeInteractions(issues, raw.interactions),
      scenarios: normalizeScenarioRows(issues, raw.scenarios, 'senarios'),
      events: normalizeEvents(issues, raw.events),
    },
    issues,
  };
}
