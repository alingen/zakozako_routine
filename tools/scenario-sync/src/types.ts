/** A JSON value parsed from scenario command_args without losing nested data. */
export type JsonValue =
  string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

/** Spreadsheet cells are kept as source values until normalization. */
export type RawCell = string | number | boolean | null;

export interface RawRow {
  /** One-based row number in the Google Sheets UI. */
  __row: number;
  [column: string]: RawCell | number;
}

/** Editing-oriented five-tab CMS, normalized into one app-facing bundle later. */
export interface RawSheets {
  daily: RawRow[];
  choices: RawRow[];
  interactions: RawRow[];
  /** Event scenario lines from the intentionally named `senarios` tab. */
  scenarios: RawRow[];
  events: RawRow[];
}

export interface SheetSnapshot {
  fetchedAt: string;
  sheetId: string;
  source: 'api' | 'public-xlsx' | 'snapshot';
  tabs: {
    daily: string[][];
    choices: string[][];
    interactions: string[][];
    senarios: string[][];
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
  sourceSheet: 'daily' | 'senarios';
  scenarioId: string;
  scenarioType: string;
  calendarDate?: string;
  calendarMonthDay?: string;
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
  dailyId: string;
  choiceId: string;
  choiceOrder: number;
  label: string;
  nextNodeId?: string;
  saveKey?: string;
  saveValue?: string;
  enabled: boolean;
  notes?: string;
}

export interface NormalizedInteractionRow {
  __row: number;
  id: string;
  text: string;
  condition?: string;
  timeCondition?: string;
  touchArea?: string;
  weight: number;
  active: boolean;
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
  daily: NormalizedScenarioRow[];
  choices: NormalizedChoiceRow[];
  interactions: NormalizedInteractionRow[];
  scenarios: NormalizedScenarioRow[];
  events: NormalizedEventRow[];
}

export function allScenarioRows(data: NormalizedSheets): NormalizedScenarioRow[] {
  return [...data.daily, ...data.scenarios];
}

// ---------------------------------------------------------------------------
// App-facing generated JSON. The five editing tabs are deliberately compiled
// into the structures the app consumes: scenarios, choice groups, interaction
// comments and events.
// ---------------------------------------------------------------------------

export type StoryNode = Omit<
  NormalizedScenarioRow,
  '__row' | 'sourceSheet' | 'scenarioId' | 'scenarioType' | 'calendarDate' | 'calendarMonthDay'
>;

export interface StoryScenario {
  scenarioId: string;
  scenarioType: string;
  calendarDate?: string;
  calendarMonthDay?: string;
  nodes: StoryNode[];
}

export type StoryChoice = Omit<NormalizedChoiceRow, '__row' | 'dailyId' | 'choiceId'>;

export interface StoryChoiceGroup {
  choiceId: string;
  choices: StoryChoice[];
}

export interface InteractionComment {
  id: string;
  text: string;
  condition?: string;
  timeCondition?: string;
  touchArea?: string;
  weight: number;
  active: boolean;
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
  interactions: InteractionComment[];
  events: StoryEvent[];
}
