import { gridToRows } from '../src/fetch.js';
import { CHOICE_COLUMNS, EVENT_COLUMNS, SCENARIO_COLUMNS } from '../src/schema.js';
import type { RawSheets } from '../src/types.js';

type Values = Record<string, string | number | boolean | undefined>;

export function sheets(options: {
  scenarios?: Values[];
  choices?: Values[];
  events?: Values[];
  titleRows?: number;
}): RawSheets {
  return {
    scenarios: gridToRows(
      grid(SCENARIO_COLUMNS, options.scenarios ?? [], options.titleRows ?? 0),
      'scenario_id',
    ),
    choices: gridToRows(
      grid(CHOICE_COLUMNS, options.choices ?? [], options.titleRows ?? 0),
      'choice_id',
    ),
    events: gridToRows(
      grid(EVENT_COLUMNS, options.events ?? [], options.titleRows ?? 0),
      'event_id',
    ),
  };
}

function grid(columns: readonly string[], rows: Values[], titleRows: number): string[][] {
  return [
    ...Array.from({ length: titleRows }, (_, index) => [`CMS title ${index + 1}`]),
    [...columns],
    ...rows.map((values) => columns.map((column) => String(values[column] ?? ''))),
  ];
}

export function scenario(values: Values = {}): Values {
  return {
    scenario_id: 'daily_test',
    scenario_type: 'daily',
    line_order: 1,
    node_id: 'test_01',
    speaker: 'character',
    message_type: 'text',
    text: 'test',
    ...values,
  };
}

export function choice(values: Values = {}): Values {
  return {
    choice_id: 'test_choice',
    choice_order: 1,
    label: 'choose',
    ...values,
  };
}

export function event(values: Values = {}): Values {
  return {
    event_id: 'event_test',
    event_type: 'small_event',
    title: 'Test event',
    entry_scenario_id: 'small_test',
    priority: 1,
    repeatable: false,
    cooldown_days: 0,
    condition_type: 'streak',
    condition_key: 'continuous_days',
    operator: 'eq',
    threshold: 1,
    ...values,
  };
}
