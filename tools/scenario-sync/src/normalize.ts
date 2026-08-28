import type {
  RawRow,
  RawSheets,
  NormalizedSheets,
  NormalizedScenarioRow,
  NormalizedChoiceRow,
  NormalizedEventConditionRow,
  ScenarioType,
  MessageType,
  Speaker,
  EventType,
  CompareOperator,
} from './types.js';
import { IssueBag } from './issues.js';
import {
  SCENARIO_COLUMNS,
  CHOICE_COLUMNS,
  EVENT_COLUMNS,
  SCENARIO_TYPES,
  MESSAGE_TYPES,
  SPEAKERS,
  EVENT_TYPES,
  COMPARE_OPERATORS,
  isBlank,
} from './schema.js';

export interface NormalizeResult {
  data: NormalizedSheets;
  issues: IssueBag;
}

const str = (row: RawRow, col: string): string => String(row[col] ?? '').trim();

function enumOrError<T extends string>(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  column: string,
  allowed: readonly T[],
  { required = true }: { required?: boolean } = {},
): T | undefined {
  const raw = str(row, column);
  if (isBlank(raw)) {
    if (required) {
      bag.error('missing_required', `必須列 ${column} が空です`, {
        at: { sheet, row: row.__row, column },
        fix: `${allowed.join(' / ')} のいずれかを入力`,
      });
    }
    return undefined;
  }
  if (!(allowed as readonly string[]).includes(raw)) {
    bag.error('bad_enum', `${column} に許可されていない値`, {
      at: { sheet, row: row.__row, column },
      value: raw,
      fix: `${allowed.join(' / ')} のいずれかにする`,
    });
    return undefined;
  }
  return raw as T;
}

function intOrError(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  column: string,
  { required = true }: { required?: boolean } = {},
): number | undefined {
  const raw = str(row, column);
  if (isBlank(raw)) {
    if (required) {
      bag.error('missing_required', `必須列 ${column} が空です`, {
        at: { sheet, row: row.__row, column },
        fix: '整数を入力',
      });
    }
    return undefined;
  }
  if (!/^-?\d+$/.test(raw)) {
    bag.error('bad_number', `${column} が整数ではありません`, {
      at: { sheet, row: row.__row, column },
      value: raw,
      fix: '数字のみ(小数・記号なし)にする',
    });
    return undefined;
  }
  return Number.parseInt(raw, 10);
}

function boolOrDefault(
  bag: IssueBag,
  sheet: string,
  row: RawRow,
  column: string,
  fallback: boolean,
): boolean {
  const raw = str(row, column).toLowerCase();
  if (isBlank(raw)) return fallback;
  if (['true', '1', 'yes'].includes(raw)) return true;
  if (['false', '0', 'no'].includes(raw)) return false;
  bag.error('bad_bool', `${column} が真偽値ではありません`, {
    at: { sheet, row: row.__row, column },
    value: raw,
    fix: 'TRUE または FALSE にする',
  });
  return fallback;
}

/** enabled defaults to TRUE when blank. FALSE rows are dropped from output. */
function isEnabled(bag: IssueBag, sheet: string, row: RawRow): boolean {
  return boolOrDefault(bag, sheet, row, 'enabled', true);
}

function undef(v: string): string | undefined {
  return isBlank(v) ? undefined : v;
}

function warnUnknownColumns(
  bag: IssueBag,
  sheet: string,
  rows: RawRow[],
  known: readonly string[],
): void {
  if (rows.length === 0) return;
  const seen = new Set<string>();
  for (const key of Object.keys(rows[0] ?? {})) {
    if (key === '__row' || known.includes(key)) continue;
    if (seen.has(key)) continue;
    seen.add(key);
    bag.warning('unknown_column', `未知の列 ${key} は無視されます`, {
      at: { sheet, row: 1, column: key },
      fix: '列名の綴りを確認するか、テンプレートに合わせる',
    });
  }
}

function requireHeaders(
  bag: IssueBag,
  sheet: string,
  rows: RawRow[],
  required: readonly string[],
): void {
  if (rows.length === 0) return;
  const header = Object.keys(rows[0] ?? {});
  for (const col of required) {
    if (!header.includes(col)) {
      bag.error('missing_column', `シート ${sheet} に必須列 ${col} がありません`, {
        at: { sheet, row: 1, column: col },
        fix: `ヘッダー行に ${col} 列を追加`,
      });
    }
  }
}

function normalizeScenarios(bag: IssueBag, rows: RawRow[]): NormalizedScenarioRow[] {
  const sheet = 'scenarios';
  const known = [...SCENARIO_COLUMNS.required, ...SCENARIO_COLUMNS.optional];
  requireHeaders(bag, sheet, rows, SCENARIO_COLUMNS.required);
  warnUnknownColumns(bag, sheet, rows, known);

  const out: NormalizedScenarioRow[] = [];
  for (const row of rows) {
    if (!isEnabled(bag, sheet, row)) continue;

    const scenarioId = str(row, 'scenario_id');
    const nodeId = str(row, 'node_id');
    if (isBlank(scenarioId)) {
      bag.error('missing_required', '必須列 scenario_id が空です', {
        at: { sheet, row: row.__row, column: 'scenario_id' },
      });
    }
    if (isBlank(nodeId)) {
      bag.error('missing_required', '必須列 node_id が空です', {
        at: { sheet, row: row.__row, column: 'node_id' },
      });
    }

    const scenarioType = enumOrError<ScenarioType>(
      bag,
      sheet,
      row,
      'scenario_type',
      SCENARIO_TYPES,
    );
    const messageType = enumOrError<MessageType>(bag, sheet, row, 'message_type', MESSAGE_TYPES);
    const speaker = enumOrError<Speaker>(bag, sheet, row, 'speaker', SPEAKERS);
    const lineOrder = intOrError(bag, sheet, row, 'line_order');

    const saveKey = str(row, 'save_key');
    const saveValue = str(row, 'save_value');
    if (isBlank(saveKey) !== isBlank(saveValue)) {
      bag.error('incomplete_pair', 'save_key と save_value は両方揃えて指定してください', {
        at: {
          sheet,
          row: row.__row,
          column: isBlank(saveKey) ? 'save_key' : 'save_value',
        },
      });
    }

    const minPhase = intOrError(bag, sheet, row, 'min_phase', {
      required: false,
    });
    const maxPhase = intOrError(bag, sheet, row, 'max_phase', {
      required: false,
    });

    if (
      scenarioId === '' ||
      nodeId === '' ||
      !scenarioType ||
      !messageType ||
      !speaker ||
      lineOrder === undefined
    ) {
      continue; // structural cell errors already reported
    }

    out.push({
      __row: row.__row,
      scenarioId,
      scenarioType,
      lineOrder,
      nodeId,
      speaker,
      messageType,
      text: String(row['text'] ?? ''),
      choiceId: undef(str(row, 'choice_id')),
      nextNodeId: undef(str(row, 'next_node_id')),
      save: isBlank(saveKey) ? undefined : { key: saveKey, value: saveValue },
      assetId: undef(str(row, 'asset_id')),
      minPhase: minPhase ?? undefined,
      maxPhase: maxPhase ?? undefined,
      speakerName: undef(str(row, 'speaker_name')),
      background: undef(str(row, 'background')),
      portrait: undef(str(row, 'portrait')),
      cg: undef(str(row, 'cg')),
      notes: undef(str(row, 'notes')),
    });
  }
  return out;
}

function normalizeChoices(bag: IssueBag, rows: RawRow[]): NormalizedChoiceRow[] {
  const sheet = 'choices';
  const known = [...CHOICE_COLUMNS.required, ...CHOICE_COLUMNS.optional];
  requireHeaders(bag, sheet, rows, CHOICE_COLUMNS.required);
  warnUnknownColumns(bag, sheet, rows, known);

  const out: NormalizedChoiceRow[] = [];
  for (const row of rows) {
    if (!isEnabled(bag, sheet, row)) continue;

    const choiceId = str(row, 'choice_id');
    const label = String(row['label'] ?? '').trim();
    if (isBlank(choiceId)) {
      bag.error('missing_required', '必須列 choice_id が空です', {
        at: { sheet, row: row.__row, column: 'choice_id' },
      });
    }
    if (isBlank(label)) {
      bag.error('missing_required', '必須列 label が空です', {
        at: { sheet, row: row.__row, column: 'label' },
      });
    }
    const choiceOrder = intOrError(bag, sheet, row, 'choice_order');

    const saveKey = str(row, 'save_key');
    const saveValue = str(row, 'save_value');
    if (isBlank(saveKey) !== isBlank(saveValue)) {
      bag.error('incomplete_pair', 'save_key と save_value は両方揃えて指定してください', {
        at: {
          sheet,
          row: row.__row,
          column: isBlank(saveKey) ? 'save_key' : 'save_value',
        },
      });
    }

    const reqKey = str(row, 'required_key');
    const reqValue = str(row, 'required_value');
    let reqOp: CompareOperator | undefined;
    if (!isBlank(str(row, 'required_operator'))) {
      reqOp = enumOrError<CompareOperator>(
        bag,
        sheet,
        row,
        'required_operator',
        COMPARE_OPERATORS,
        {
          required: false,
        },
      );
    }
    let requirement: NormalizedChoiceRow['requirement'];
    if (!isBlank(reqKey)) {
      const operator: CompareOperator = reqOp ?? 'exists';
      if (operator !== 'exists' && isBlank(reqValue)) {
        bag.error(
          'incomplete_pair',
          'required_operator が exists 以外なら required_value が必要です',
          {
            at: { sheet, row: row.__row, column: 'required_value' },
          },
        );
      }
      requirement = { key: reqKey, operator, value: reqValue };
    } else if (!isBlank(reqValue) || reqOp) {
      bag.warning('orphan_requirement', 'required_key が無いので条件は無視されます', {
        at: { sheet, row: row.__row, column: 'required_key' },
      });
    }

    if (choiceId === '' || label === '' || choiceOrder === undefined) continue;

    out.push({
      __row: row.__row,
      choiceId,
      choiceOrder,
      label,
      nextNodeId: undef(str(row, 'next_node_id')),
      save: isBlank(saveKey) ? undefined : { key: saveKey, value: saveValue },
      requirement,
      notes: undef(str(row, 'notes')),
    });
  }
  return out;
}

function normalizeEvents(bag: IssueBag, rows: RawRow[]): NormalizedEventConditionRow[] {
  const sheet = 'events';
  const known = [...EVENT_COLUMNS.required, ...EVENT_COLUMNS.optional];
  requireHeaders(bag, sheet, rows, EVENT_COLUMNS.required);
  warnUnknownColumns(bag, sheet, rows, known);

  const out: NormalizedEventConditionRow[] = [];
  for (const row of rows) {
    if (!isEnabled(bag, sheet, row)) continue;

    const eventId = str(row, 'event_id');
    const title = String(row['title'] ?? '').trim();
    const entryScenarioId = str(row, 'entry_scenario_id');
    if (isBlank(eventId)) {
      bag.error('missing_required', '必須列 event_id が空です', {
        at: { sheet, row: row.__row, column: 'event_id' },
      });
    }
    if (isBlank(title)) {
      bag.error('missing_required', '必須列 title が空です', {
        at: { sheet, row: row.__row, column: 'title' },
      });
    }
    if (isBlank(entryScenarioId)) {
      bag.error('missing_required', '必須列 entry_scenario_id が空です', {
        at: { sheet, row: row.__row, column: 'entry_scenario_id' },
      });
    }

    const eventType = enumOrError<EventType>(bag, sheet, row, 'event_type', EVENT_TYPES);
    // condition_type is a free-form grouping label; require it non-empty but do
    // not restrict its values (the real mapping keys off condition_key).
    const conditionType = str(row, 'condition_type');
    if (isBlank(conditionType)) {
      bag.error('missing_required', '必須列 condition_type が空です', {
        at: { sheet, row: row.__row, column: 'condition_type' },
      });
    }
    const operator = enumOrError<CompareOperator>(bag, sheet, row, 'operator', COMPARE_OPERATORS);
    const priority = intOrError(bag, sheet, row, 'priority');
    const conditionKey = str(row, 'condition_key');
    const threshold = str(row, 'threshold');
    if (isBlank(conditionKey)) {
      bag.error('missing_required', '必須列 condition_key が空です', {
        at: { sheet, row: row.__row, column: 'condition_key' },
      });
    }
    if (isBlank(threshold)) {
      bag.error('missing_required', '必須列 threshold が空です', {
        at: { sheet, row: row.__row, column: 'threshold' },
      });
    }

    const repeatable = boolOrDefault(bag, sheet, row, 'repeatable', false);
    const cooldownDays = intOrError(bag, sheet, row, 'cooldown_days', { required: false }) ?? 0;
    const advancesToPhase = intOrError(bag, sheet, row, 'advances_to_phase', {
      required: false,
    });

    if (
      eventId === '' ||
      title === '' ||
      entryScenarioId === '' ||
      !eventType ||
      conditionType === '' ||
      !operator ||
      priority === undefined ||
      conditionKey === '' ||
      threshold === ''
    ) {
      continue;
    }

    out.push({
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
      background: undef(str(row, 'background')),
      advancesToPhase: advancesToPhase ?? undefined,
      notes: undef(str(row, 'notes')),
    });
  }
  return out;
}

export function normalize(raw: RawSheets): NormalizeResult {
  const issues = new IssueBag();
  const data: NormalizedSheets = {
    scenarios: normalizeScenarios(issues, raw.scenarios),
    choices: normalizeChoices(issues, raw.choices),
    events: normalizeEvents(issues, raw.events),
  };
  return { data, issues };
}
