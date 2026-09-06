/** Exact column vocabulary of the three current CMS tabs. */
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
  'typing_duration_ms',
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

export const REQUIRED_CHOICE_COLUMNS = ['choice_id', 'choice_order', 'label', 'enabled'] as const;

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
  'daily',
  'small_event',
  'middle_event',
  'large_event',
]);
export const KNOWN_EVENT_TYPES = new Set(['small_event', 'middle_event', 'large_event']);
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
  'hide_cg',
  'play_audio',
  'record_audio',
  'scene_change',
  'show_cg',
  'show_modal',
  'typing_hide',
  'typing_show',
  'wait',
]);
export const KNOWN_OPERATORS = new Set(['eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'exists']);
export const KNOWN_STORY_CATEGORIES = new Set(['main', 'sub']);

export function isBlank(value: unknown): boolean {
  return value === undefined || value === null || String(value).trim() === '';
}
