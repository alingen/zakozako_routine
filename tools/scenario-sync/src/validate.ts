import { IssueBag } from './issues.js';
import { checkReachability } from './reachability.js';
import {
  KNOWN_ASSET_TYPES,
  KNOWN_COMMANDS,
  KNOWN_EVENT_TYPES,
  KNOWN_MESSAGE_TYPES,
  KNOWN_OPERATORS,
  KNOWN_SCENARIO_TYPES,
  KNOWN_SCREEN_MODES,
  KNOWN_STORY_CATEGORIES,
  KNOWN_TIME_CONDITIONS,
  KNOWN_UI_VARIANTS,
} from './schema.js';
import type {
  JsonValue,
  NormalizedAssetCatalogRow,
  NormalizedChoiceRow,
  NormalizedDailyCatalogRow,
  NormalizedEventRow,
  NormalizedInteractionRow,
  NormalizedScenarioRow,
  NormalizedSheets,
} from './types.js';
import { allScenarioRows } from './types.js';

export interface ValidateResult {
  issues: IssueBag;
}

/** Structural and forward-compatibility checks over normalized CMS rows. */
export function validate(data: NormalizedSheets): ValidateResult {
  const issues = new IssueBag();
  const scenarioRows = allScenarioRows(data);
  const scenarios = groupScenarios(scenarioRows);
  const choices = groupChoices(data.choices);
  const assets = validateAssetCatalog(data.assetCatalog, issues);

  validateDailyCatalog(data.dailyCatalog, data.daily, issues);
  validateScenarioRows(scenarioRows, scenarios, choices, issues);
  validateAssetReferences(scenarioRows, data.events, assets, issues);
  validateChoiceRows(data.choices, data.daily, choices, issues);
  validateInteractions(data.interactions, issues);
  validateReactions(data, issues);
  validateEventRows(data.events, scenarios, issues);
  checkReachability(data, issues);

  return { issues };
}

function validateReactions(data: NormalizedSheets, issues: IssueBag): void {
  const conditionIDs = new Set<string>();
  for (const row of data.reactionConditions) {
    const at = { sheet: 'reaction_conditions', row: row.__row, column: 'condition_id' };
    if (conditionIDs.has(row.conditionId))
      issues.error('duplicate_reaction_condition', 'condition_id must be unique', { at });
    conditionIDs.add(row.conditionId);
    if (!row.active) continue;
    if (!['state', 'derived', 'event', 'calendar'].includes(row.triggerType)) {
      issues.error('invalid_reaction_trigger', 'Unsupported trigger_type', {
        at,
        value: row.triggerType,
      });
    }
    if (!['==', '!=', '>=', '<=', '>', '<', 'derived', 'between', 'event'].includes(row.operator)) {
      issues.error('invalid_reaction_operator', 'Unsupported operator', {
        at,
        value: row.operator,
      });
    }
  }
  const lineIDs = new Set<string>();
  for (const row of data.reactionLines) {
    const at = { sheet: 'reaction_lines', row: row.__row, column: 'line_id' };
    if (lineIDs.has(row.lineId))
      issues.error('duplicate_reaction_line', 'line_id must be unique', { at });
    lineIDs.add(row.lineId);
    if (!conditionIDs.has(row.conditionId))
      issues.error('missing_reaction_condition', 'Active line must reference a known condition', {
        at,
        value: row.conditionId,
      });
    if (row.weight < 0)
      issues.error('invalid_reaction_weight', 'weight must be nonnegative', { at });
    if (!['normal', 'strong'].includes(row.strength))
      issues.error('invalid_reaction_strength', 'strength must be normal or strong', { at });
  }
}

function validateAssetCatalog(
  rows: NormalizedAssetCatalogRow[],
  issues: IssueBag,
): Map<string, NormalizedAssetCatalogRow> {
  const assets = new Map<string, NormalizedAssetCatalogRow>();
  for (const row of rows) {
    const previous = assets.get(row.assetId);
    if (previous) {
      issues.error('duplicate_asset_id', `asset_id ${row.assetId} must be unique`, {
        at: { sheet: 'asset_catalog', row: row.__row, column: 'asset_id' },
        value: row.assetId,
        fix: `Also used by asset_catalog row ${previous.__row}`,
      });
    } else {
      assets.set(row.assetId, row);
    }
    warnUnknown(issues, KNOWN_ASSET_TYPES, row.assetType, 'asset_type', row.__row, 'asset_catalog');
  }
  return assets;
}

type AssetReference = {
  id: string;
  sheet: 'daily' | 'senarios' | 'events';
  row: number;
  column: string;
  expectedTypes?: ReadonlySet<string>;
};

function validateAssetReferences(
  scenarioRows: NormalizedScenarioRow[],
  eventRows: NormalizedEventRow[],
  assets: Map<string, NormalizedAssetCatalogRow>,
  issues: IssueBag,
): void {
  const references: AssetReference[] = [];
  const one = (type: string): ReadonlySet<string> => new Set([type]);
  const audioTypes = new Set(['bgm', 'se', 'voice']);

  for (const row of scenarioRows) {
    if (row.background) {
      references.push({
        id: row.background,
        sheet: row.sourceSheet,
        row: row.__row,
        column: 'background',
        expectedTypes: one('background'),
      });
    }
    if (row.portrait) {
      references.push({
        id: row.portrait,
        sheet: row.sourceSheet,
        row: row.__row,
        column: 'portrait',
        expectedTypes: one('portrait'),
      });
    }
    if (row.cg) {
      references.push({
        id: row.cg,
        sheet: row.sourceSheet,
        row: row.__row,
        column: 'cg',
        expectedTypes: one('cg'),
      });
    }
    if (row.assetId) {
      const expectedTypes = inferredAssetTypes(row, audioTypes);
      references.push({
        id: row.assetId,
        sheet: row.sourceSheet,
        row: row.__row,
        column: 'asset_id',
        expectedTypes,
      });
    }

    const args = jsonObject(row.commandArgs);
    const commandAsset = jsonString(args?.asset_id);
    if (row.command === 'play_se' && !row.assetId && !commandAsset) {
      issues.error('missing_command_asset_id', 'play_se requires an asset_id', {
        at: { sheet: row.sourceSheet, row: row.__row, column: 'command_args' },
        fix: 'Set command_args.asset_id or the row asset_id to a se asset',
      });
    }
    if (commandAsset) {
      references.push({
        id: commandAsset,
        sheet: row.sourceSheet,
        row: row.__row,
        column: 'command_args',
        expectedTypes:
          row.command === 'show_cg' || row.command === 'hide_cg'
            ? one('cg')
            : row.command === 'show_portrait'
              ? one('portrait')
              : row.command === 'play_bgm'
                ? one('bgm')
                : row.command === 'play_se'
                  ? one('se')
                  : row.command === 'play_audio' || row.command === 'record_audio'
                    ? audioTypes
                    : undefined,
      });
    }
    const commandBackground = jsonString(args?.background);
    if (commandBackground) {
      references.push({
        id: commandBackground,
        sheet: row.sourceSheet,
        row: row.__row,
        column: 'command_args',
        expectedTypes: one('background'),
      });
    }
  }

  for (const row of eventRows) {
    if (!row.background) continue;
    references.push({
      id: row.background,
      sheet: 'events',
      row: row.__row,
      column: 'background',
      expectedTypes: one('background'),
    });
  }

  const visited = new Set<string>();
  for (const reference of references) {
    const key = `${reference.sheet}\u0000${reference.row}\u0000${reference.column}\u0000${reference.id}`;
    if (visited.has(key)) continue;
    visited.add(key);

    const asset = assets.get(reference.id);
    if (!asset) {
      issues.error('dangling_asset_id', `Asset ${reference.id} does not exist in asset_catalog`, {
        at: { sheet: reference.sheet, row: reference.row, column: reference.column },
        value: reference.id,
      });
      continue;
    }
    if (!asset.enabled) {
      issues.error('disabled_asset_reference', `Asset ${reference.id} is disabled`, {
        at: { sheet: reference.sheet, row: reference.row, column: reference.column },
        value: reference.id,
        fix: `Enable asset_catalog row ${asset.__row} or remove the reference`,
      });
      continue;
    }
    if (reference.expectedTypes && !reference.expectedTypes.has(asset.assetType)) {
      issues.error(
        'asset_type_mismatch',
        `Asset ${reference.id} has type ${asset.assetType}; expected ${[
          ...reference.expectedTypes,
        ].join(' / ')}`,
        {
          at: { sheet: reference.sheet, row: reference.row, column: reference.column },
          value: reference.id,
          fix: `Update asset_catalog row ${asset.__row}`,
        },
      );
    }
  }
}

function inferredAssetTypes(
  row: NormalizedScenarioRow,
  audioTypes: ReadonlySet<string>,
): ReadonlySet<string> | undefined {
  if (row.command === 'show_cg' || row.command === 'hide_cg' || row.uiVariant === 'cg') {
    return new Set(['cg']);
  }
  if (row.command === 'show_portrait') {
    return new Set(['portrait']);
  }
  if (row.command === 'play_bgm') {
    return new Set(['bgm']);
  }
  if (row.command === 'play_se') {
    return new Set(['se']);
  }
  if (
    row.command === 'play_audio' ||
    row.command === 'record_audio' ||
    row.uiVariant === 'audio_message' ||
    row.uiVariant === 'recording'
  ) {
    return audioTypes;
  }
  if (row.messageType === 'image' || row.uiVariant === 'image_message') {
    return new Set(['image', 'cg']);
  }
  return undefined;
}

function jsonObject(value: JsonValue | undefined): Record<string, JsonValue> | undefined {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : undefined;
}

function jsonString(value: JsonValue | undefined): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function validateDailyCatalog(
  rows: NormalizedDailyCatalogRow[],
  dailyRows: NormalizedScenarioRow[],
  issues: IssueBag,
): void {
  const catalogRows = new Map<string, NormalizedDailyCatalogRow>();
  const daily = groupScenarios(dailyRows);
  const exactDates = new Map<string, string>();
  const recurringDates = new Map<string, string>();
  const displayOrders = new Map<number, string>();

  for (const row of rows) {
    const previousCatalogRow = catalogRows.get(row.scenarioId);
    if (previousCatalogRow) {
      issues.error('duplicate_daily_catalog_id', `scenario_id ${row.scenarioId} must be unique`, {
        at: { sheet: 'daily_catalog', row: row.__row, column: 'scenario_id' },
        value: row.scenarioId,
        fix: `Also used by daily_catalog row ${previousCatalogRow.__row}`,
      });
    } else {
      catalogRows.set(row.scenarioId, row);
    }

    if (!daily.has(row.scenarioId)) {
      issues.error(
        'dangling_daily_catalog_id',
        `scenario_id ${row.scenarioId} does not exist in daily`,
        {
          at: { sheet: 'daily_catalog', row: row.__row, column: 'scenario_id' },
          value: row.scenarioId,
        },
      );
    }

    const calendarDate = row.calendarDate;
    const calendarMonthDay = row.calendarMonthDay;
    if (calendarDate && calendarMonthDay) {
      issues.error(
        'daily_schedule_conflict',
        `${row.scenarioId} cannot use calendar_date and calendar_month_day together`,
        {
          at: { sheet: 'daily_catalog', row: row.__row, column: 'calendar_date' },
          value: `${calendarDate} / ${calendarMonthDay}`,
          fix: 'Keep only one date field',
        },
      );
    }

    if (row.displayOrder !== undefined && row.displayOrder <= 0) {
      issues.error('invalid_display_order', 'display_order must be greater than zero', {
        at: { sheet: 'daily_catalog', row: row.__row, column: 'display_order' },
        value: String(row.displayOrder),
      });
    }

    const isUnscheduled = !calendarDate && !calendarMonthDay;
    if (row.enabled && isUnscheduled && row.displayOrder === undefined) {
      issues.error(
        'missing_daily_display_order',
        'Enabled daily without a calendar date requires display_order',
        {
          at: { sheet: 'daily_catalog', row: row.__row, column: 'display_order' },
        },
      );
    }
    if (row.enabled && isUnscheduled && row.displayOrder !== undefined) {
      const previousScenario = displayOrders.get(row.displayOrder);
      if (previousScenario && previousScenario !== row.scenarioId) {
        issues.error(
          'duplicate_daily_display_order',
          `display_order ${row.displayOrder} is assigned more than once`,
          {
            at: { sheet: 'daily_catalog', row: row.__row, column: 'display_order' },
            value: String(row.displayOrder),
            fix: `Also used by ${previousScenario}`,
          },
        );
      } else {
        displayOrders.set(row.displayOrder, row.scenarioId);
      }
    }

    if (calendarDate) {
      if (!isValidCalendarDate(calendarDate)) {
        issues.error('invalid_calendar_date', 'calendar_date must be a real YYYY-MM-DD date', {
          at: { sheet: 'daily_catalog', row: row.__row, column: 'calendar_date' },
          value: calendarDate,
        });
      } else {
        reportDuplicateSchedule(
          exactDates,
          calendarDate,
          row.scenarioId,
          row,
          'calendar_date',
          issues,
        );
      }
    }

    if (calendarMonthDay) {
      if (!isValidCalendarMonthDay(calendarMonthDay)) {
        issues.error('invalid_calendar_month_day', 'calendar_month_day must be a real MM-DD date', {
          at: { sheet: 'daily_catalog', row: row.__row, column: 'calendar_month_day' },
          value: calendarMonthDay,
        });
      } else {
        reportDuplicateSchedule(
          recurringDates,
          calendarMonthDay,
          row.scenarioId,
          row,
          'calendar_month_day',
          issues,
        );
      }
    }
  }

  for (const [scenarioId, scenarioRows] of daily) {
    if (catalogRows.has(scenarioId)) continue;
    const firstRow = [...scenarioRows].sort((left, right) => left.lineOrder - right.lineOrder)[0]!;
    issues.error('missing_daily_catalog', `daily scenario ${scenarioId} has no catalog row`, {
      at: { sheet: 'daily', row: firstRow.__row, column: 'scenario_id' },
      value: scenarioId,
      fix: 'Add exactly one matching daily_catalog row',
    });
  }
}

function reportDuplicateSchedule(
  seen: Map<string, string>,
  key: string,
  scenarioId: string,
  row: NormalizedDailyCatalogRow,
  column: 'calendar_date' | 'calendar_month_day',
  issues: IssueBag,
): void {
  const previous = seen.get(key);
  if (previous && previous !== scenarioId) {
    issues.error('duplicate_daily_schedule', `${column} ${key} is assigned more than once`, {
      at: { sheet: 'daily_catalog', row: row.__row, column },
      value: key,
      fix: `Also used by ${previous}`,
    });
  } else {
    seen.set(key, scenarioId);
  }
}

function isValidCalendarDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  return isValidDateParts(Number(match[1]), Number(match[2]), Number(match[3]));
}

function isValidCalendarMonthDay(value: string): boolean {
  const match = /^(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  return isValidDateParts(2000, Number(match[1]), Number(match[2]));
}

function isValidDateParts(year: number, month: number, day: number): boolean {
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
  );
}

function validateScenarioRows(
  rows: NormalizedScenarioRow[],
  scenarios: Map<string, NormalizedScenarioRow[]>,
  choices: Map<string, NormalizedChoiceRow[]>,
  issues: IssueBag,
): void {
  const nodeIds = new Map<string, NormalizedScenarioRow>();

  for (const row of rows) {
    const sheet = row.sourceSheet;
    const scopedNodeId = `${row.scenarioId}\u0000${row.nodeId}`;
    const duplicateNode = nodeIds.get(scopedNodeId);
    if (duplicateNode) {
      issues.error(
        'duplicate_node_id',
        `node_id ${row.nodeId} must be unique within ${row.scenarioId}`,
        {
          at: { sheet, row: row.__row, column: 'node_id' },
          value: row.nodeId,
          fix: `Also used by ${duplicateNode.sourceSheet} row ${duplicateNode.__row}`,
        },
      );
    } else {
      nodeIds.set(scopedNodeId, row);
    }

    if (row.lineOrder <= 0) {
      issues.error('invalid_line_order', 'line_order must be greater than zero', {
        at: { sheet, row: row.__row, column: 'line_order' },
        value: String(row.lineOrder),
      });
    }

    if (row.nextNodeId) {
      const localNodes = scenarios.get(row.scenarioId) ?? [];
      if (!localNodes.some((candidate) => candidate.nodeId === row.nextNodeId)) {
        issues.error(
          'dangling_node_next',
          `next_node_id ${row.nextNodeId} does not exist in scenario ${row.scenarioId}`,
          {
            at: { sheet, row: row.__row, column: 'next_node_id' },
            value: row.nextNodeId,
          },
        );
      }
    }

    if (row.messageType === 'choice') {
      if (!row.choiceId) {
        issues.error('missing_choice_id', 'message_type=choice requires choice_id', {
          at: { sheet, row: row.__row, column: 'choice_id' },
        });
      } else if (!choices.has(row.choiceId)) {
        issues.error('dangling_choice_id', `choice_id ${row.choiceId} does not exist`, {
          at: { sheet, row: row.__row, column: 'choice_id' },
          value: row.choiceId,
        });
      } else if (
        !(choices.get(row.choiceId) ?? []).every((choice) => choice.dailyId === row.scenarioId)
      ) {
        issues.error(
          'choice_reference_mismatch',
          `choice_id ${row.choiceId} belongs to another daily`,
          {
            at: { sheet, row: row.__row, column: 'choice_id' },
            value: row.choiceId,
          },
        );
      }
    } else if (row.choiceId) {
      issues.warning('unexpected_choice_id', 'choice_id is set on a non-choice node', {
        at: { sheet, row: row.__row, column: 'choice_id' },
        value: row.choiceId,
      });
    }

    if (row.messageType === 'image' && !row.assetId) {
      issues.error('image_without_asset', 'message_type=image requires asset_id', {
        at: { sheet, row: row.__row, column: 'asset_id' },
      });
    }
    if (row.minPhase !== undefined && row.maxPhase !== undefined && row.minPhase > row.maxPhase) {
      issues.error('phase_range_inverted', 'min_phase must not exceed max_phase', {
        at: { sheet, row: row.__row, column: 'min_phase' },
        value: `${row.minPhase} > ${row.maxPhase}`,
      });
    }
    if (
      row.typingDurationMs !== undefined &&
      (row.typingDurationMs < 0 || row.typingDurationMs > 30_000)
    ) {
      issues.error('invalid_typing_duration', 'typing_duration_ms must be between 0 and 30000', {
        at: { sheet, row: row.__row, column: 'typing_duration_ms' },
        value: String(row.typingDurationMs),
      });
    }

    if (row.command === 'portrait_hesitate') {
      if (
        row.messageType !== 'action' ||
        row.screenMode !== 'adv' ||
        row.uiVariant !== 'scene_transition' ||
        row.text.trim() !== '' ||
        row.choiceId !== undefined
      ) {
        issues.error(
          'invalid_portrait_hesitation_row',
          'portrait_hesitate requires an empty action/adv/scene_transition row without a choice',
          {
            at: { sheet, row: row.__row, column: 'command' },
            fix: 'Set message_type=action, screen_mode=adv, ui_variant=scene_transition, and leave text and choice_id empty',
          },
        );
      }
      const durationValue = jsonObject(row.commandArgs)?.duration_ms;
      if (durationValue !== undefined) {
        const duration =
          typeof durationValue === 'number'
            ? durationValue
            : typeof durationValue === 'string' && durationValue.trim()
              ? Number(durationValue.trim())
              : Number.NaN;
        if (!Number.isFinite(duration) || duration < 0 || duration > 5_000) {
          issues.error(
            'invalid_portrait_hesitation_duration',
            'portrait_hesitate duration_ms must be between 0 and 5000',
            {
              at: { sheet, row: row.__row, column: 'command_args' },
              value: JSON.stringify(durationValue),
              fix: 'Omit duration_ms for the 1500ms default, or set it between 0 and 5000',
            },
          );
        }
      }
    }

    if (sheet === 'senarios') {
      warnUnknown(
        issues,
        KNOWN_SCENARIO_TYPES,
        row.scenarioType,
        'scenario_type',
        row.__row,
        sheet,
      );
    }
    warnUnknown(issues, KNOWN_MESSAGE_TYPES, row.messageType, 'message_type', row.__row, sheet);
    warnUnknown(issues, KNOWN_SCREEN_MODES, row.screenMode, 'screen_mode', row.__row, sheet);
    warnUnknown(issues, KNOWN_UI_VARIANTS, row.uiVariant, 'ui_variant', row.__row, sheet);
    warnUnknown(issues, KNOWN_COMMANDS, row.command, 'command', row.__row, sheet);
  }

  for (const [scenarioId, groupedRows] of scenarios) {
    const head = groupedRows[0]!;
    const lineOrders = new Map<number, NormalizedScenarioRow>();
    for (const row of groupedRows) {
      if (row.sourceSheet !== head.sourceSheet) {
        issues.error(
          'duplicate_scenario_id',
          `scenario_id ${scenarioId} exists in both content tabs`,
          {
            at: { sheet: row.sourceSheet, row: row.__row, column: 'scenario_id' },
            value: scenarioId,
            fix: `Also used by ${head.sourceSheet} row ${head.__row}`,
          },
        );
      }
      if (row.scenarioType !== head.scenarioType) {
        issues.error('inconsistent_scenario_type', `scenario_type differs within ${scenarioId}`, {
          at: { sheet: row.sourceSheet, row: row.__row, column: 'scenario_type' },
          value: row.scenarioType,
          fix: `Row ${head.__row} uses ${head.scenarioType}`,
        });
      }
      const duplicate = lineOrders.get(row.lineOrder);
      if (duplicate) {
        issues.error('duplicate_line_order', `line_order must be unique within ${scenarioId}`, {
          at: { sheet: row.sourceSheet, row: row.__row, column: 'line_order' },
          value: String(row.lineOrder),
          fix: `Also used by ${duplicate.sourceSheet} row ${duplicate.__row}`,
        });
      } else {
        lineOrders.set(row.lineOrder, row);
      }
    }
  }
}

function validateChoiceRows(
  rows: NormalizedChoiceRow[],
  dailyRows: NormalizedScenarioRow[],
  groups: Map<string, NormalizedChoiceRow[]>,
  issues: IssueBag,
): void {
  const daily = groupScenarios(dailyRows);
  const referencedBy = new Map<string, Set<string>>();
  for (const [dailyId, scenarioRows] of daily) {
    for (const row of scenarioRows) {
      if (row.messageType !== 'choice' || !row.choiceId) continue;
      const references = referencedBy.get(row.choiceId) ?? new Set<string>();
      references.add(dailyId);
      referencedBy.set(row.choiceId, references);
    }
  }

  for (const [choiceId, choices] of groups) {
    const seenOrders = new Map<number, NormalizedChoiceRow>();
    const expectedDailyId = choices[0]!.dailyId;
    for (const row of choices) {
      if (row.dailyId !== expectedDailyId) {
        issues.error('choice_daily_mismatch', `daily_id differs within ${choiceId}`, {
          at: { sheet: 'choices', row: row.__row, column: 'daily_id' },
          value: row.dailyId,
          fix: `Row ${choices[0]!.__row} uses ${expectedDailyId}`,
        });
      }
      const scenario = daily.get(row.dailyId);
      if (!scenario) {
        issues.error('dangling_daily_id', `daily_id ${row.dailyId} does not exist`, {
          at: { sheet: 'choices', row: row.__row, column: 'daily_id' },
          value: row.dailyId,
        });
      }

      const duplicate = seenOrders.get(row.choiceOrder);
      if (duplicate) {
        issues.error('duplicate_choice_order', `choice_order must be unique within ${choiceId}`, {
          at: { sheet: 'choices', row: row.__row, column: 'choice_order' },
          value: String(row.choiceOrder),
          fix: `Also used by choices row ${duplicate.__row}`,
        });
      } else {
        seenOrders.set(row.choiceOrder, row);
      }
      if (row.choiceOrder <= 0) {
        issues.error('invalid_choice_order', 'choice_order must be greater than zero', {
          at: { sheet: 'choices', row: row.__row, column: 'choice_order' },
          value: String(row.choiceOrder),
        });
      }

      if (row.nextNodeId && !scenario?.some((node) => node.nodeId === row.nextNodeId)) {
        issues.warning(
          'dangling_choice_next',
          `Choice ${choiceId} points to missing node ${row.nextNodeId}; the player will recover by line order`,
          {
            at: { sheet: 'choices', row: row.__row, column: 'next_node_id' },
            value: row.nextNodeId,
          },
        );
      }
    }

    const references = referencedBy.get(choiceId);
    if (!references) {
      issues.warning('unused_choice_group', `choice_id ${choiceId} is not used by any daily`, {
        at: { sheet: 'choices', row: choices[0]!.__row, column: 'choice_id' },
        value: choiceId,
      });
    } else if (references.size !== 1 || !references.has(expectedDailyId)) {
      issues.error(
        'choice_reference_mismatch',
        `choice_id ${choiceId} is not owned by daily_id ${expectedDailyId}`,
        {
          at: { sheet: 'choices', row: choices[0]!.__row, column: 'daily_id' },
          value: expectedDailyId,
        },
      );
    }
  }

  if (rows.length > 0 && groups.size === 0) {
    issues.error('missing_choice_groups', 'Enabled choice rows could not be grouped');
  }
}

function validateInteractions(rows: NormalizedInteractionRow[], issues: IssueBag): void {
  const ids = new Map<string, number>();
  for (const row of rows) {
    const duplicateRow = ids.get(row.id);
    if (duplicateRow !== undefined) {
      issues.error('duplicate_interaction_id', `id ${row.id} must be unique`, {
        at: { sheet: 'interactions', row: row.__row, column: 'id' },
        value: row.id,
        fix: `Also used by interactions row ${duplicateRow}`,
      });
    } else {
      ids.set(row.id, row.__row);
    }
    if (row.weight <= 0) {
      issues.error('invalid_interaction_weight', 'weight must be greater than zero', {
        at: { sheet: 'interactions', row: row.__row, column: 'weight' },
        value: String(row.weight),
      });
    }
    warnUnknown(
      issues,
      KNOWN_TIME_CONDITIONS,
      row.timeCondition,
      'time_condition',
      row.__row,
      'interactions',
    );
  }
}

const EVENT_METADATA_FIELDS = [
  'eventType',
  'title',
  'entryScenarioId',
  'priority',
  'repeatable',
  'cooldownDays',
  'background',
  'advancesToPhase',
  'enabled',
  'notes',
  'chapterId',
  'episodeOrder',
  'storyCategory',
] as const satisfies readonly (keyof NormalizedEventRow)[];

function validateEventRows(
  rows: NormalizedEventRow[],
  scenarios: Map<string, NormalizedScenarioRow[]>,
  issues: IssueBag,
): void {
  const groups = groupEvents(rows);
  const priorities = new Map<number, string>();

  for (const [eventId, eventRows] of groups) {
    const head = eventRows[0]!;
    const entryRows = scenarios.get(head.entryScenarioId);
    if (!entryRows || entryRows[0]!.sourceSheet !== 'senarios') {
      issues.error(
        'dangling_entry_scenario',
        `entry_scenario_id ${head.entryScenarioId} does not exist in senarios`,
        {
          at: { sheet: 'events', row: head.__row, column: 'entry_scenario_id' },
          value: head.entryScenarioId,
        },
      );
    } else if (entryRows[0]!.scenarioType !== head.eventType) {
      issues.error(
        'event_scenario_type_mismatch',
        `event_type ${head.eventType} differs from entry scenario type ${entryRows[0]!.scenarioType}`,
        {
          at: { sheet: 'events', row: head.__row, column: 'event_type' },
          value: head.eventType,
        },
      );
    }

    for (const row of eventRows.slice(1)) {
      for (const field of EVENT_METADATA_FIELDS) {
        if (row[field] !== head[field]) {
          issues.error(
            'event_metadata_mismatch',
            `${toSnakeCase(field)} differs within ${eventId}`,
            {
              at: { sheet: 'events', row: row.__row, column: toSnakeCase(field) },
              value: String(row[field] ?? ''),
              fix: `Row ${head.__row} uses ${String(head[field] ?? '')}`,
            },
          );
        }
      }
    }

    for (const row of eventRows) {
      if (row.episodeOrder !== undefined && row.episodeOrder < 0) {
        issues.error('invalid_episode_order', 'episode_order must be zero or greater', {
          at: { sheet: 'events', row: row.__row, column: 'episode_order' },
          value: String(row.episodeOrder),
        });
      }
    }

    const seenConditions = new Map<string, number>();
    for (const row of eventRows) {
      const conditionKey = JSON.stringify([
        row.conditionType,
        row.conditionKey,
        row.operator,
        row.threshold,
      ]);
      const duplicateRow = seenConditions.get(conditionKey);
      if (duplicateRow !== undefined) {
        issues.warning(
          'duplicate_event_condition',
          'Duplicate AND condition has no additional effect',
          {
            at: { sheet: 'events', row: row.__row, column: 'condition_type' },
            fix: `Same condition appears on events row ${duplicateRow}`,
          },
        );
      } else {
        seenConditions.set(conditionKey, row.__row);
      }
      warnUnknown(issues, KNOWN_OPERATORS, row.operator, 'operator', row.__row, 'events');
    }

    warnUnknown(issues, KNOWN_EVENT_TYPES, head.eventType, 'event_type', head.__row, 'events');
    warnUnknown(
      issues,
      KNOWN_STORY_CATEGORIES,
      head.storyCategory,
      'story_category',
      head.__row,
      'events',
    );

    const previousEvent = priorities.get(head.priority);
    if (previousEvent && previousEvent !== eventId) {
      issues.warning('duplicate_event_priority', 'priority is shared by multiple events', {
        at: { sheet: 'events', row: head.__row, column: 'priority' },
        value: String(head.priority),
        fix: `Also used by ${previousEvent}; event_id provides the deterministic tie-breaker`,
      });
    } else {
      priorities.set(head.priority, eventId);
    }
  }
}

function warnUnknown(
  issues: IssueBag,
  known: ReadonlySet<string>,
  value: string | undefined,
  column: string,
  row: number,
  sheet: string,
): void {
  if (!value || known.has(value)) return;
  issues.warning('unknown_value', `Unknown ${column} is preserved in generated content`, {
    at: { sheet, row, column },
    value,
  });
}

function groupScenarios(rows: NormalizedScenarioRow[]): Map<string, NormalizedScenarioRow[]> {
  return groupBy(rows, (row) => row.scenarioId);
}

function groupChoices(rows: NormalizedChoiceRow[]): Map<string, NormalizedChoiceRow[]> {
  return groupBy(rows, (row) => row.choiceId);
}

function groupEvents(rows: NormalizedEventRow[]): Map<string, NormalizedEventRow[]> {
  return groupBy(rows, (row) => row.eventId);
}

function groupBy<T>(rows: T[], key: (row: T) => string): Map<string, T[]> {
  const groups = new Map<string, T[]>();
  for (const row of rows) {
    const values = groups.get(key(row)) ?? [];
    values.push(row);
    groups.set(key(row), values);
  }
  return groups;
}

function toSnakeCase(value: string): string {
  return value.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}
