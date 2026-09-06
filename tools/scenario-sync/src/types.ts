/** A JSON value parsed from scenarios.command_args without losing nested data. */
export type JsonValue =
  string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

/** Spreadsheet cells are kept as source values until normalization. */
export type RawCell = string | number | boolean | null;

export interface RawRow {
  /** One-based row number in the Google Sheets UI. */
  __row: number;
  [column: string]: RawCell | number;
}

export interface RawSheets {
  scenarios: RawRow[];
  choices: RawRow[];
  events: RawRow[];
}

export interface SheetSnapshot {
  fetchedAt: string;
  sheetId: string;
  source: 'api' | 'public-xlsx' | 'snapshot';
  tabs: {
    scenarios: string[][];
    choices: string[][];
    events: string[][];
  };
}

// ---------------------------------------------------------------------------
// Normalized sheet rows. Values such as speaker, messageType, screenMode,
// uiVariant and command intentionally remain open strings: the CMS is the
// authority, and a newly-added value must not be discarded by generation.
// ---------------------------------------------------------------------------

export interface NormalizedScenarioRow {
  __row: number;
  scenarioId: string;
  scenarioType: string;
  lineOrder: number;
  nodeId: string;
  speaker: string;
  messageType: string;
  text: string;
  choiceId?: string;
  nextNodeId?: string;
  saveKey?: string;
  saveValue?: string;
  assetId?: string;
  minPhase?: number;
  maxPhase?: number;
  speakerName?: string;
  typingDurationMs?: number;
  background?: string;
  portrait?: string;
  cg?: string;
  enabled: boolean;
  notes?: string;
  screenMode?: string;
  uiVariant?: string;
  command?: string;
  commandArgs?: JsonValue;
}

export interface NormalizedChoiceRow {
  __row: number;
  choiceId: string;
  choiceOrder: number;
  label: string;
  nextNodeId?: string;
  saveKey?: string;
  saveValue?: string;
  requiredKey?: string;
  requiredOperator?: string;
  requiredValue?: string;
  enabled: boolean;
  notes?: string;
}

export interface NormalizedEventRow {
  __row: number;
  eventId: string;
  eventType: string;
  title: string;
  entryScenarioId: string;
  priority: number;
  repeatable: boolean;
  cooldownDays: number;
  conditionType: string;
  conditionKey: string;
  operator: string;
  threshold: string;
  background?: string;
  advancesToPhase?: number;
  enabled: boolean;
  notes?: string;
  chapterId?: string;
  episodeOrder?: number;
  storyCategory?: string;
}

export interface NormalizedSheets {
  scenarios: NormalizedScenarioRow[];
  choices: NormalizedChoiceRow[];
  events: NormalizedEventRow[];
}

// ---------------------------------------------------------------------------
// App-facing generated JSON. This mirrors the three CMS tabs without flattening
// choices into nodes or event conditions into hard-coded Swift properties.
// ---------------------------------------------------------------------------

export type StoryNode = Omit<NormalizedScenarioRow, '__row' | 'scenarioId' | 'scenarioType'>;

export interface StoryScenario {
  scenarioId: string;
  scenarioType: string;
  nodes: StoryNode[];
}

export type StoryChoice = Omit<NormalizedChoiceRow, '__row' | 'choiceId'>;

export interface StoryChoiceGroup {
  choiceId: string;
  choices: StoryChoice[];
}

export interface StoryEventCondition {
  conditionType: string;
  conditionKey: string;
  operator: string;
  threshold: string;
}

export interface StoryEvent {
  eventId: string;
  eventType: string;
  title: string;
  entryScenarioId: string;
  priority: number;
  repeatable: boolean;
  cooldownDays: number;
  background?: string;
  advancesToPhase?: number;
  enabled: boolean;
  notes?: string;
  chapterId?: string;
  episodeOrder?: number;
  storyCategory?: string;
  /** Multiple rows with the same eventId are evaluated as AND. */
  conditions: StoryEventCondition[];
}

export const GENERATED_MARKER =
  'AUTO-GENERATED FROM GOOGLE SHEETS — DO NOT EDIT BY HAND. ' +
  'Run: npm --prefix tools/scenario-sync run sync:write';

export interface StoryContentBundle {
  _generated: string;
  scenarios: StoryScenario[];
  choiceGroups: StoryChoiceGroup[];
  events: StoryEvent[];
}
