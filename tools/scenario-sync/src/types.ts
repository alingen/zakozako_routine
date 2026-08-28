/**
 * Type definitions for the scenario sync pipeline.
 *
 * Three layers:
 *  1. Raw*  — one entry per spreadsheet row, all values as strings (as fetched).
 *  2. Normalized* — trimmed / type-converted / disabled rows dropped.
 *  3. App output — the exact JSON shape the iOS app decodes (see the Swift
 *     `ConversationScript` / `ScriptMessage` / `EventDefinition` models).
 *
 * Only the App output types are hand-authored contracts that must stay in sync
 * with Swift. The Raw/Normalized types describe the sheet, which is the source
 * of truth.
 */

export type ScenarioType = 'daily' | 'small_event' | 'large_event';
export type MessageType = 'text' | 'choice' | 'system' | 'image';
export type Speaker = 'character' | 'user' | 'system';
export type CompareOperator = 'eq' | 'ne' | 'gt' | 'gte' | 'lt' | 'lte' | 'exists';
export type EventType = 'small_event' | 'large_event';
/** Free-form grouping label in the sheet (`user_state`, `streak`, `event`, …). */
export type ConditionType = string;

/** A cell location for error reporting. */
export interface CellRef {
  sheet: string;
  /** 1-based row number as seen in the Google Sheets UI (header = row 1). */
  row: number;
  column: string;
}

// ---------------------------------------------------------------------------
// Layer 1: raw rows (strings)
// ---------------------------------------------------------------------------

export interface RawRow {
  /** 1-based sheet row number (header is row 1, first data row is row 2). */
  __row: number;
  [column: string]: string | number;
}

export interface RawSheets {
  scenarios: RawRow[];
  choices: RawRow[];
  events: RawRow[];
}

// ---------------------------------------------------------------------------
// Layer 2: normalized rows
// ---------------------------------------------------------------------------

export interface NormalizedScenarioRow {
  __row: number;
  scenarioId: string;
  scenarioType: ScenarioType;
  lineOrder: number;
  nodeId: string;
  speaker: Speaker;
  messageType: MessageType;
  text: string;
  choiceId?: string;
  nextNodeId?: string;
  save?: { key: string; value: string };
  assetId?: string;
  minPhase?: number;
  maxPhase?: number;
  speakerName?: string;
  background?: string;
  portrait?: string;
  cg?: string;
  notes?: string;
}

export interface NormalizedChoiceRow {
  __row: number;
  choiceId: string;
  choiceOrder: number;
  label: string;
  nextNodeId?: string;
  save?: { key: string; value: string };
  requirement?: { key: string; operator: CompareOperator; value: string };
  notes?: string;
}

export interface NormalizedEventConditionRow {
  __row: number;
  eventId: string;
  eventType: EventType;
  title: string;
  entryScenarioId: string;
  priority: number;
  repeatable: boolean;
  cooldownDays: number;
  conditionType: ConditionType;
  conditionKey: string;
  operator: CompareOperator;
  threshold: string;
  background?: string;
  advancesToPhase?: number;
  notes?: string;
}

export interface NormalizedSheets {
  scenarios: NormalizedScenarioRow[];
  choices: NormalizedChoiceRow[];
  events: NormalizedEventConditionRow[];
}

// ---------------------------------------------------------------------------
// Layer 3: app output (must match the Swift models)
// ---------------------------------------------------------------------------

/** Matches Swift `SaveFact`. */
export interface AppSaveFact {
  key: string;
  value: string;
}

/** Matches Swift `ChoiceRequirement`. */
export interface AppChoiceRequirement {
  key: string;
  operator: CompareOperator;
  value: string;
}

/** Matches Swift `ScriptChoice`. */
export interface AppChoice {
  text: string;
  next?: string;
  saveFact?: AppSaveFact;
  requirement?: AppChoiceRequirement;
}

/** Matches Swift `ScriptMessage`. */
export interface AppMessage {
  id: string;
  speaker: 'character' | 'user';
  type?: 'text' | 'image';
  text: string;
  imageName?: string;
  choices?: AppChoice[];
  next?: string;
  saveFact?: AppSaveFact;
  minPhase?: number;
  maxPhase?: number;
  speakerName?: string;
  background?: string;
  portrait?: string;
  cg?: string;
}

/** Matches Swift `EventCondition`. */
export interface AppEventCondition {
  minTrust?: number;
  minStreakDays?: number;
  minBlockedProtectedCount?: number;
  minMasteredCount?: number;
  minRelationshipPhase?: number;
  requiredCompletedEventIds?: string[];
}

/** Matches Swift `EventDefinition` (plus metadata fields Swift safely ignores). */
export interface AppEvent {
  eventId: string;
  eventType: 'small' | 'big';
  title: string;
  priority: number;
  repeatable: boolean;
  cooldownDays: number;
  unlockConditions: AppEventCondition;
  background?: string;
  advancesToPhase?: number;
  messages: AppMessage[];
}

export interface AppDailyScenario {
  scenarioId: string;
  dayIndex: number;
  messages: AppMessage[];
}

export const GENERATED_MARKER =
  'AUTO-GENERATED FROM GOOGLE SHEETS — DO NOT EDIT BY HAND. ' +
  'Edit the spreadsheet, then run: npm --prefix tools/scenario-sync run sync';

export interface AppDailyBundle {
  _generated: string;
  scenarios: AppDailyScenario[];
}

export interface AppEventBundle {
  _generated: string;
  events: AppEvent[];
}
