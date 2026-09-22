import { gridToRows } from '../src/fetch.js';
import {
  ASSET_CATALOG_COLUMNS,
  CHOICE_COLUMNS,
  DAILY_CATALOG_COLUMNS,
  DAILY_COLUMNS,
  EVENT_COLUMNS,
  INTERACTION_COLUMNS,
  SCENARIO_COLUMNS,
} from '../src/schema.js';
import type { RawSheets } from '../src/types.js';

type Values = Record<string, string | number | boolean | undefined>;

export function sheets(options: {
  scenarios?: Values[];
  catalogs?: Values[];
  assets?: Values[];
  choices?: Values[];
  interactions?: Values[];
  events?: Values[];
  titleRows?: number;
}): RawSheets {
  const scenarioRows = options.scenarios ?? [];
  const dailyRows = scenarioRows.filter((row) => (row.scenario_type ?? 'daily') === 'daily');
  const eventScenarioRows = scenarioRows.filter(
    (row) => (row.scenario_type ?? 'daily') !== 'daily',
  );
  const defaultCatalogs = [...new Set(dailyRows.map((row) => String(row.scenario_id)))].map(
    (scenarioId, index) => {
      const rows = dailyRows.filter((row) => String(row.scenario_id) === scenarioId);
      const metadata = rows.find(
        (row) => row.calendar_date !== undefined || row.calendar_month_day !== undefined,
      );
      return dailyCatalog({
        scenario_id: scenarioId,
        display_order: index + 1,
        calendar_date: metadata?.calendar_date,
        calendar_month_day: metadata?.calendar_month_day,
      });
    },
  );
  return {
    daily: gridToRows(grid(DAILY_COLUMNS, dailyRows, options.titleRows ?? 0), 'scenario_id'),
    dailyCatalog: gridToRows(
      grid(DAILY_CATALOG_COLUMNS, options.catalogs ?? defaultCatalogs, options.titleRows ?? 0),
      'scenario_id',
    ),
    assetCatalog: gridToRows(
      grid(
        ASSET_CATALOG_COLUMNS,
        options.assets ?? [],
        options.titleRows ?? 0,
      ),
      'asset_id',
    ),
    scenarios: gridToRows(
      grid(SCENARIO_COLUMNS, eventScenarioRows, options.titleRows ?? 0),
      'scenario_id',
    ),
    choices: gridToRows(
      grid(CHOICE_COLUMNS, options.choices ?? [], options.titleRows ?? 0),
      'choice_id',
    ),
    interactions: gridToRows(
      grid(INTERACTION_COLUMNS, options.interactions ?? [], options.titleRows ?? 0),
      'id',
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

export function dailyCatalog(values: Values = {}): Values {
  return {
    scenario_id: 'daily_test',
    title: 'Test daily',
    display_order: 1,
    category: 'test',
    status: '公開可能',
    enabled: true,
    ...values,
  };
}

export function assetCatalog(values: Values = {}): Values {
  return {
    asset_id: 'asset_test',
    asset_type: 'image',
    display_name: 'Test asset',
    file_name: 'asset_test',
    status: '公開可能',
    enabled: true,
    ...values,
  };
}

export function choice(values: Values = {}): Values {
  return {
    daily_id: 'daily_test',
    choice_id: 'test_choice',
    choice_order: 1,
    label: 'choose',
    ...values,
  };
}

export function interaction(values: Values = {}): Values {
  return {
    id: 'interaction_test',
    text: 'test comment',
    weight: 1,
    active: true,
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
