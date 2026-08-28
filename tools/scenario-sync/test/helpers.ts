import { gridToRows } from '../src/fetch.js';
import type { RawSheets } from '../src/types.js';

export const SCENARIO_HEADER = [
  'scenario_id',
  'scenario_type',
  'line_order',
  'node_id',
  'speaker',
  'message_type',
  'text',
  'choice_id',
  'next_node_id',
  'save_key',
  'save_value',
  'asset_id',
  'min_phase',
  'max_phase',
  'speaker_name',
  'background',
  'portrait',
  'cg',
  'enabled',
  'notes',
];

export const CHOICE_HEADER = [
  'choice_id',
  'choice_order',
  'label',
  'next_node_id',
  'save_key',
  'save_value',
  'required_key',
  'required_operator',
  'required_value',
  'enabled',
  'notes',
];

export const EVENT_HEADER = [
  'event_id',
  'event_type',
  'title',
  'entry_scenario_id',
  'priority',
  'repeatable',
  'cooldown_days',
  'condition_type',
  'condition_key',
  'operator',
  'threshold',
  'background',
  'advances_to_phase',
  'enabled',
  'notes',
];

export function sheets(opts: {
  scenarios?: string[][];
  choices?: string[][];
  events?: string[][];
  /** Prepend title rows above the header, as the real sheet has. */
  titleRows?: number;
}): RawSheets {
  const pad = (header: string[]): string[][] =>
    Array.from({ length: opts.titleRows ?? 0 }, () => ['タイトル行']).concat([header]);
  return {
    scenarios: gridToRows([...pad(SCENARIO_HEADER), ...(opts.scenarios ?? [])], 'scenario_id'),
    choices: gridToRows([...pad(CHOICE_HEADER), ...(opts.choices ?? [])], 'choice_id'),
    events: gridToRows([...pad(EVENT_HEADER), ...(opts.events ?? [])], 'event_id'),
  };
}

export function codes(issues: { code: string }[]): string[] {
  return issues.map((i) => i.code).sort();
}
