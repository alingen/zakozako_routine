import { IssueBag } from './issues.js';
import { checkReachability } from './reachability.js';
import {
  KNOWN_COMMANDS,
  KNOWN_EVENT_TYPES,
  KNOWN_MESSAGE_TYPES,
  KNOWN_OPERATORS,
  KNOWN_SCENARIO_TYPES,
  KNOWN_SCREEN_MODES,
  KNOWN_STORY_CATEGORIES,
  KNOWN_UI_VARIANTS,
} from './schema.js';
import type {
  NormalizedChoiceRow,
  NormalizedEventRow,
  NormalizedScenarioRow,
  NormalizedSheets,
} from './types.js';

export interface ValidateResult {
  issues: IssueBag;
}

/** Structural and forward-compatibility checks over normalized CMS rows. */
export function validate(data: NormalizedSheets): ValidateResult {
  const issues = new IssueBag();
  const scenarios = groupScenarios(data.scenarios);
  const choices = groupChoices(data.choices);

  validateScenarioRows(data.scenarios, scenarios, choices, issues);
  validateChoiceRows(data.choices, scenarios, choices, issues);
  validateEventRows(data.events, scenarios, issues);
  checkReachability(data, issues);

  return { issues };
}

function validateScenarioRows(
  rows: NormalizedScenarioRow[],
  scenarios: Map<string, NormalizedScenarioRow[]>,
  choices: Map<string, NormalizedChoiceRow[]>,
  issues: IssueBag,
): void {
  const nodeIds = new Map<string, NormalizedScenarioRow>();

  for (const row of rows) {
    const scopedNodeId = `${row.scenarioId}\u0000${row.nodeId}`;
    const duplicateNode = nodeIds.get(scopedNodeId);
    if (duplicateNode) {
      issues.error(
        'duplicate_node_id',
        `node_id ${row.nodeId} must be unique within ${row.scenarioId}`,
        {
          at: { sheet: 'scenarios', row: row.__row, column: 'node_id' },
          value: row.nodeId,
          fix: `Also used by scenarios row ${duplicateNode.__row}`,
        },
      );
    } else {
      nodeIds.set(scopedNodeId, row);
    }

    if (row.lineOrder <= 0) {
      issues.error('invalid_line_order', 'line_order must be greater than zero', {
        at: { sheet: 'scenarios', row: row.__row, column: 'line_order' },
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
            at: { sheet: 'scenarios', row: row.__row, column: 'next_node_id' },
            value: row.nextNodeId,
          },
        );
      }
    }

    if (row.messageType === 'choice') {
      if (!row.choiceId) {
        issues.error('missing_choice_id', 'message_type=choice requires choice_id', {
          at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
        });
      } else if (!choices.has(row.choiceId)) {
        issues.error('dangling_choice_id', `choice_id ${row.choiceId} does not exist`, {
          at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
          value: row.choiceId,
        });
      }
    } else if (row.choiceId) {
      issues.warning('unexpected_choice_id', 'choice_id is set on a non-choice node', {
        at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
        value: row.choiceId,
      });
    }

    if (row.messageType === 'image' && !row.assetId) {
      issues.error('image_without_asset', 'message_type=image requires asset_id', {
        at: { sheet: 'scenarios', row: row.__row, column: 'asset_id' },
      });
    }
    if (row.minPhase !== undefined && row.maxPhase !== undefined && row.minPhase > row.maxPhase) {
      issues.error('phase_range_inverted', 'min_phase must not exceed max_phase', {
        at: { sheet: 'scenarios', row: row.__row, column: 'min_phase' },
        value: `${row.minPhase} > ${row.maxPhase}`,
      });
    }

    warnUnknown(issues, KNOWN_SCENARIO_TYPES, row.scenarioType, 'scenario_type', row.__row);
    warnUnknown(issues, KNOWN_MESSAGE_TYPES, row.messageType, 'message_type', row.__row);
    warnUnknown(issues, KNOWN_SCREEN_MODES, row.screenMode, 'screen_mode', row.__row);
    warnUnknown(issues, KNOWN_UI_VARIANTS, row.uiVariant, 'ui_variant', row.__row);
    warnUnknown(issues, KNOWN_COMMANDS, row.command, 'command', row.__row);
  }

  for (const [scenarioId, scenarioRows] of scenarios) {
    const head = scenarioRows[0]!;
    const lineOrders = new Map<number, NormalizedScenarioRow>();
    for (const row of scenarioRows) {
      if (row.scenarioType !== head.scenarioType) {
        issues.error('inconsistent_scenario_type', `scenario_type differs within ${scenarioId}`, {
          at: { sheet: 'scenarios', row: row.__row, column: 'scenario_type' },
          value: row.scenarioType,
          fix: `Row ${head.__row} uses ${head.scenarioType}`,
        });
      }
      const duplicate = lineOrders.get(row.lineOrder);
      if (duplicate) {
        issues.error('duplicate_line_order', `line_order must be unique within ${scenarioId}`, {
          at: { sheet: 'scenarios', row: row.__row, column: 'line_order' },
          value: String(row.lineOrder),
          fix: `Also used by scenarios row ${duplicate.__row}`,
        });
      } else {
        lineOrders.set(row.lineOrder, row);
      }
    }
  }
}

function validateChoiceRows(
  rows: NormalizedChoiceRow[],
  scenarios: Map<string, NormalizedScenarioRow[]>,
  groups: Map<string, NormalizedChoiceRow[]>,
  issues: IssueBag,
): void {
  const referencedBy = new Map<string, Set<string>>();
  for (const [scenarioId, scenarioRows] of scenarios) {
    for (const row of scenarioRows) {
      if (row.messageType !== 'choice' || !row.choiceId) continue;
      const references = referencedBy.get(row.choiceId) ?? new Set<string>();
      references.add(scenarioId);
      referencedBy.set(row.choiceId, references);
    }
  }

  const globalNodeIds = new Set(
    [...scenarios.values()].flatMap((scenarioRows) => scenarioRows.map((row) => row.nodeId)),
  );

  for (const [choiceId, choices] of groups) {
    const seenOrders = new Map<number, NormalizedChoiceRow>();
    for (const row of choices) {
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

      warnUnknown(
        issues,
        KNOWN_OPERATORS,
        row.requiredOperator,
        'required_operator',
        row.__row,
        'choices',
      );

      if (!row.nextNodeId) continue;
      if (!globalNodeIds.has(row.nextNodeId)) {
        const detail = {
          at: { sheet: 'choices', row: row.__row, column: 'next_node_id' },
          value: row.nextNodeId,
        } as const;
        issues.warning(
          'dangling_choice_next',
          `Choice ${choiceId} points to missing node ${row.nextNodeId}; the player will recover by line order`,
          detail,
        );
        continue;
      }

      for (const scenarioId of referencedBy.get(choiceId) ?? []) {
        const existsInScenario = (scenarios.get(scenarioId) ?? []).some(
          (node) => node.nodeId === row.nextNodeId,
        );
        if (!existsInScenario) {
          issues.error(
            'cross_scenario_choice_next',
            `Choice target ${row.nextNodeId} is outside referencing scenario ${scenarioId}`,
            {
              at: { sheet: 'choices', row: row.__row, column: 'next_node_id' },
              value: row.nextNodeId,
            },
          );
        }
      }
    }

    if (!referencedBy.has(choiceId)) {
      issues.warning('unused_choice_group', `choice_id ${choiceId} is not used by any scenario`, {
        at: { sheet: 'choices', row: choices[0]!.__row, column: 'choice_id' },
        value: choiceId,
      });
    }
  }

  // Keep the parameter semantically tied to normalized rows and catch an
  // accidental grouping omission during future refactors.
  if (rows.length > 0 && groups.size === 0) {
    issues.error('missing_choice_groups', 'Enabled choice rows could not be grouped');
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
    if (!entryRows) {
      issues.error(
        'dangling_entry_scenario',
        `entry_scenario_id ${head.entryScenarioId} does not exist`,
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
  sheet = 'scenarios',
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
