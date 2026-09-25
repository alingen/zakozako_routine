/** Exact column vocabulary of the seven CMS tabs. */
export const DAILY_COLUMNS = [
  'scenario_id',
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
  'typing_duration_ms',
  'enabled',
  'notes',
  'screen_mode',
  'ui_variant',
  'command',
  'command_args',
] as const;

export const DAILY_CATALOG_COLUMNS = [
  'scenario_id',
  'title',
  'display_order',
  'category',
  'calendar_date',
  'calendar_month_day',
  'status',
  'enabled',
] as const;

export const ASSET_CATALOG_COLUMNS = [
  'asset_id',
  'asset_type',
  'display_name',
  'file_name',
  'status',
  'enabled',
  'notes',
] as const;

export const SCENARIO_COLUMNS = [
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
  'screen_mode',
  'ui_variant',
  'command',
  'command_args',
] as const;

export const CHOICE_COLUMNS = [
  'daily_id',
  'choice_id',
  'choice_order',
  'label',
  'next_node_id',
  'save_key',
  'save_value',
  'enabled',
  'notes',
] as const;

export const INTERACTION_COLUMNS = [
  'id',
  'text',
  'condition',
  'time_condition',
  'touch_area',
  'weight',
  'active',
] as const;

export const EVENT_COLUMNS = [
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
  'chapter_id',
  'episode_order',
  'story_category',
] as const;

export const REQUIRED_DAILY_COLUMNS = [
  'scenario_id',
  'line_order',
  'node_id',
  'speaker',
  'message_type',
  'text',
  'enabled',
] as const;

export const REQUIRED_DAILY_CATALOG_COLUMNS = DAILY_CATALOG_COLUMNS;

export const REQUIRED_ASSET_CATALOG_COLUMNS = ASSET_CATALOG_COLUMNS;

export const REQUIRED_SCENARIO_COLUMNS = [
  'scenario_id',
  'scenario_type',
  'line_order',
  'node_id',
  'speaker',
  'message_type',
  'text',
  'enabled',
] as const;

export const REQUIRED_CHOICE_COLUMNS = [
  'daily_id',
  'choice_id',
  'choice_order',
  'label',
  'enabled',
] as const;

export const REQUIRED_INTERACTION_COLUMNS = ['id', 'text', 'weight', 'active'] as const;

export const REQUIRED_EVENT_COLUMNS = [
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
] as const;

// These sets are diagnostics only. Normalization never rejects a non-empty
// value merely because it is not listed here.
export const KNOWN_SCENARIO_TYPES = new Set([
  'prologue',
  'small_event',
  'middle_event',
  'large_event',
]);
export const KNOWN_EVENT_TYPES = new Set([
  'prologue',
  'small_event',
  'middle_event',
  'large_event',
]);
export const KNOWN_MESSAGE_TYPES = new Set(['text', 'choice', 'image', 'action']);
export const KNOWN_SCREEN_MODES = new Set(['adv', 'chat', 'call']);
export const KNOWN_UI_VARIANTS = new Set([
  'audio_message',
  'beat',
  'call_connected',
  'call_end',
  'cg',
  'dialogue',
  'image_message',
  'incoming_call',
  'modal',
  'monologue',
  'narration',
  'outgoing_call',
  'recording',
  'scene_transition',
  'title_card',
  'typing',
]);
export const KNOWN_COMMANDS = new Set([
  'call_connected',
  'call_end',
  'call_start',
  'clear_background',
  'hide_cg',
  'hide_portrait',
  'play_bgm',
  'play_se',
  'play_audio',
  'portrait_hesitate',
  'record_audio',
  'scene_change',
  'show_cg',
  'show_portrait',
  'show_modal',
  'stop_bgm',
  'typing_hide',
  'typing_show',
  'wait',
]);
export const KNOWN_OPERATORS = new Set(['eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'exists']);
export const KNOWN_STORY_CATEGORIES = new Set(['main', 'sub']);
export const KNOWN_TIME_CONDITIONS = new Set(['always', 'morning', 'daytime', 'evening', 'night']);
export const KNOWN_ASSET_TYPES = new Set([
  'background',
  'portrait',
  'cg',
  'image',
  'bgm',
  'se',
  'voice',
]);

export function isBlank(value: unknown): boolean {
  return value === undefined || value === null || String(value).trim() === '';
}
