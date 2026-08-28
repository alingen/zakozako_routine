import { z } from 'zod';
import type { CompareOperator } from './types.js';

/**
 * Column contracts + enums for the three sheets.
 *
 * `main` columns come straight from the spec. `extension` columns carry app
 * features the MVP spec's column list does not cover (phase gating, VN assets).
 * Extra columns beyond these are ignored with a warning.
 */

export const SCENARIO_COLUMNS = {
  required: [
    'scenario_id',
    'scenario_type',
    'line_order',
    'node_id',
    'speaker',
    'message_type',
    'text',
    'enabled',
  ] as const,
  optional: [
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
    'notes',
  ] as const,
};

export const CHOICE_COLUMNS = {
  required: ['choice_id', 'choice_order', 'label', 'enabled'] as const,
  optional: [
    'next_node_id',
    'save_key',
    'save_value',
    'required_key',
    'required_operator',
    'required_value',
    'notes',
  ] as const,
};

export const EVENT_COLUMNS = {
  required: [
    'event_id',
    'event_type',
    'title',
    'entry_scenario_id',
    'priority',
    'condition_type',
    'condition_key',
    'operator',
    'threshold',
    'enabled',
  ] as const,
  optional: ['repeatable', 'cooldown_days', 'background', 'advances_to_phase', 'notes'] as const,
};

export const SCENARIO_TYPES = ['daily', 'small_event', 'large_event'] as const;
export const MESSAGE_TYPES = ['text', 'choice', 'system', 'image'] as const;
export const SPEAKERS = ['character', 'user', 'system'] as const;
export const EVENT_TYPES = ['small_event', 'large_event'] as const;
/** `condition_type` is a free-form grouping label in the sheet (`user_state`,
 *  `streak`, `event`, …). The actual mapping keys off `condition_key`, so this
 *  list is only used for the template dropdown — unknown values are accepted. */
export const CONDITION_TYPES = ['user_state', 'streak', 'event', 'relationship'] as const;
export const COMPARE_OPERATORS: CompareOperator[] = [
  'eq',
  'ne',
  'gt',
  'gte',
  'lt',
  'lte',
  'exists',
];

/** `condition_key` values the app can enforce, and the target `EventCondition`
 *  field. Aliases are accepted so the sheet's vocabulary can vary. */
export const METRIC_CONDITION_KEYS: Record<string, keyof AppConditionFields> = {
  trust: 'minTrust',
  trust_points: 'minTrust',
  streak_days: 'minStreakDays',
  continuous_days: 'minStreakDays',
  streak: 'minStreakDays',
  blocked_protected_count: 'minBlockedProtectedCount',
  blocked_count: 'minBlockedProtectedCount',
  mastered_count: 'minMasteredCount',
  relationship_phase: 'minRelationshipPhase',
  phase: 'minRelationshipPhase',
};
/** `condition_key` values meaning "event X is completed". Threshold = event id. */
export const EVENT_COMPLETED_KEYS = new Set(['event_completed', 'completed_event']);

export type AppConditionFields = {
  minTrust: number;
  minStreakDays: number;
  minBlockedProtectedCount: number;
  minMasteredCount: number;
  minRelationshipPhase: number;
};

// --- helpers used by normalize/validate for cell-level type conversion ---

export const boolSchema = z
  .string()
  .transform((s) => s.trim().toLowerCase())
  .pipe(z.enum(['true', 'false', '1', '0', 'yes', 'no', '']))
  .transform((s) => s === 'true' || s === '1' || s === 'yes');

export const intSchema = z
  .string()
  .transform((s) => s.trim())
  .refine((s) => /^-?\d+$/.test(s), { message: '整数ではありません' })
  .transform((s) => Number.parseInt(s, 10));

export function isBlank(value: string | number | undefined | null): boolean {
  return value === undefined || value === null || String(value).trim() === '';
}
