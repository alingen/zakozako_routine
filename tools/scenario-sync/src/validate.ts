import type {
  NormalizedSheets,
  NormalizedScenarioRow,
  NormalizedChoiceRow,
  NormalizedEventConditionRow,
} from './types.js';
import { IssueBag } from './issues.js';
import { checkReachability } from './reachability.js';
import { METRIC_CONDITION_KEYS, EVENT_COMPLETED_KEYS } from './schema.js';

export interface ValidateResult {
  issues: IssueBag;
}

export function validate(data: NormalizedSheets): ValidateResult {
  const bag = new IssueBag();

  const scenarioIds = new Set(data.scenarios.map((r) => r.scenarioId));
  const nodeIndex = indexNodes(bag, data.scenarios);
  const choicesByGroup = groupChoices(bag, data.choices);

  checkScenarioTypeConsistency(bag, data.scenarios);
  checkLineOrderUniqueness(bag, data.scenarios);
  checkChoiceRefs(bag, data.scenarios, choicesByGroup);
  checkChoiceTargets(bag, data.choices, nodeIndex);
  checkChoiceNodesHaveOptions(bag, data.scenarios, choicesByGroup);
  checkMessageTypeRules(bag, data.scenarios);
  checkEvents(bag, data.events, data.scenarios, scenarioIds);

  checkReachability(bag, data.scenarios, choicesByGroup);

  return { issues: bag };
}

// ---------------------------------------------------------------------------

function indexNodes(
  bag: IssueBag,
  scenarios: NormalizedScenarioRow[],
): Map<string, NormalizedScenarioRow> {
  const byId = new Map<string, NormalizedScenarioRow>();
  for (const row of scenarios) {
    const existing = byId.get(row.nodeId);
    if (existing) {
      bag.error('duplicate_node_id', `node_id ${row.nodeId} が重複しています`, {
        at: { sheet: 'scenarios', row: row.__row, column: 'node_id' },
        value: row.nodeId,
        fix: `全シナリオ横断で一意にする(重複相手: 行${existing.__row})`,
      });
      continue;
    }
    byId.set(row.nodeId, row);
  }
  return byId;
}

function groupChoices(
  bag: IssueBag,
  choices: NormalizedChoiceRow[],
): Map<string, NormalizedChoiceRow[]> {
  const groups = new Map<string, NormalizedChoiceRow[]>();
  for (const row of choices) {
    if (!groups.has(row.choiceId)) groups.set(row.choiceId, []);
    groups.get(row.choiceId)!.push(row);
  }
  for (const [choiceId, rows] of groups) {
    const seen = new Map<number, number>();
    for (const row of rows) {
      const prev = seen.get(row.choiceOrder);
      if (prev !== undefined) {
        bag.error('duplicate_choice_order', `choice_id ${choiceId} 内で choice_order が重複`, {
          at: { sheet: 'choices', row: row.__row, column: 'choice_order' },
          value: String(row.choiceOrder),
          fix: `同一 choice_id 内で一意にする(重複相手: 行${prev})`,
        });
      } else {
        seen.set(row.choiceOrder, row.__row);
      }
    }
    rows.sort((a, b) => a.choiceOrder - b.choiceOrder);
  }
  return groups;
}

function checkScenarioTypeConsistency(bag: IssueBag, scenarios: NormalizedScenarioRow[]): void {
  const typeById = new Map<string, { type: string; row: number }>();
  for (const row of scenarios) {
    const existing = typeById.get(row.scenarioId);
    if (existing && existing.type !== row.scenarioType) {
      bag.error(
        'inconsistent_scenario_type',
        `scenario_id ${row.scenarioId} の scenario_type が不一致`,
        {
          at: { sheet: 'scenarios', row: row.__row, column: 'scenario_type' },
          value: row.scenarioType,
          fix: `同じ scenario_id の行は同じ値にする(行${existing.row} は "${existing.type}")`,
        },
      );
    } else if (!existing) {
      typeById.set(row.scenarioId, { type: row.scenarioType, row: row.__row });
    }
  }
}

function checkLineOrderUniqueness(bag: IssueBag, scenarios: NormalizedScenarioRow[]): void {
  const seen = new Map<string, Map<number, number>>();
  for (const row of scenarios) {
    if (!seen.has(row.scenarioId)) seen.set(row.scenarioId, new Map());
    const inner = seen.get(row.scenarioId)!;
    const prev = inner.get(row.lineOrder);
    if (prev !== undefined) {
      bag.error('duplicate_line_order', `scenario_id ${row.scenarioId} 内で line_order が重複`, {
        at: { sheet: 'scenarios', row: row.__row, column: 'line_order' },
        value: String(row.lineOrder),
        fix: `同一 scenario_id 内で一意にする(重複相手: 行${prev})`,
      });
    } else {
      inner.set(row.lineOrder, row.__row);
    }
  }
}

function checkChoiceRefs(
  bag: IssueBag,
  scenarios: NormalizedScenarioRow[],
  choicesByGroup: Map<string, NormalizedChoiceRow[]>,
): void {
  for (const row of scenarios) {
    if (row.messageType === 'choice') {
      if (!row.choiceId) {
        bag.error('missing_choice_id', 'message_type=choice なのに choice_id が空です', {
          at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
          fix: 'choices シートの choice_id を指定',
        });
      } else if (!choicesByGroup.has(row.choiceId)) {
        bag.error(
          'dangling_choice_id',
          `choice_id ${row.choiceId} が choices シートに存在しません`,
          {
            at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
            value: row.choiceId,
            fix: 'choices シートに該当行を追加するか、参照を修正',
          },
        );
      }
    } else if (row.choiceId) {
      bag.warning(
        'unexpected_choice_id',
        'message_type が choice 以外なのに choice_id があります',
        {
          at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
          value: row.choiceId,
        },
      );
    }
  }
}

function checkChoiceTargets(
  bag: IssueBag,
  choices: NormalizedChoiceRow[],
  nodeIndex: Map<string, NormalizedScenarioRow>,
): void {
  for (const choice of choices) {
    if (choice.nextNodeId && !nodeIndex.has(choice.nextNodeId)) {
      bag.error('dangling_choice_next', `choices.next_node_id ${choice.nextNodeId} が参照切れ`, {
        at: { sheet: 'choices', row: choice.__row, column: 'next_node_id' },
        value: choice.nextNodeId,
        fix: 'scenarios シートに存在する node_id を指定',
      });
    }
  }
}

function checkChoiceNodesHaveOptions(
  bag: IssueBag,
  scenarios: NormalizedScenarioRow[],
  choicesByGroup: Map<string, NormalizedChoiceRow[]>,
): void {
  for (const row of scenarios) {
    if (row.messageType !== 'choice' || !row.choiceId) continue;
    const options = choicesByGroup.get(row.choiceId) ?? [];
    if (options.length === 0) {
      bag.error('choice_node_no_options', `choice ノード ${row.nodeId} に有効な選択肢が0件です`, {
        at: { sheet: 'scenarios', row: row.__row, column: 'choice_id' },
        value: row.choiceId,
        fix: 'choices シートに enabled=TRUE の行を追加',
      });
    }
  }
}

function checkMessageTypeRules(bag: IssueBag, scenarios: NormalizedScenarioRow[]): void {
  for (const row of scenarios) {
    if (row.messageType === 'image' && !row.assetId) {
      bag.error('image_without_asset', 'message_type=image なのに asset_id が空です', {
        at: { sheet: 'scenarios', row: row.__row, column: 'asset_id' },
        fix: '表示する画像名(Assets.xcassets)を asset_id に入力',
      });
    }
    if (row.assetId && row.messageType !== 'image') {
      bag.warning('asset_ignored', 'message_type が image 以外なので asset_id は無視されます', {
        at: { sheet: 'scenarios', row: row.__row, column: 'asset_id' },
        value: row.assetId,
      });
    }
    if (row.minPhase !== undefined && row.maxPhase !== undefined && row.minPhase > row.maxPhase) {
      bag.error(
        'phase_range_inverted',
        'min_phase が max_phase より大きいため常に非表示になります',
        {
          at: { sheet: 'scenarios', row: row.__row, column: 'min_phase' },
          value: `${row.minPhase} > ${row.maxPhase}`,
        },
      );
    }
  }
}

function checkEvents(
  bag: IssueBag,
  events: NormalizedEventConditionRow[],
  scenarios: NormalizedScenarioRow[],
  scenarioIds: Set<string>,
): void {
  const scenarioTypeById = new Map<string, string>();
  for (const row of scenarios) {
    if (!scenarioTypeById.has(row.scenarioId))
      scenarioTypeById.set(row.scenarioId, row.scenarioType);
  }

  const groups = new Map<string, NormalizedEventConditionRow[]>();
  for (const row of events) {
    if (!groups.has(row.eventId)) groups.set(row.eventId, []);
    groups.get(row.eventId)!.push(row);
  }

  const priorities = new Map<number, string>();

  for (const [eventId, rows] of groups) {
    const head = rows[0]!;

    // shared fields must be identical across all rows of one event
    for (const key of ['eventType', 'title', 'entryScenarioId', 'priority'] as const) {
      for (const row of rows.slice(1)) {
        if (row[key] !== head[key]) {
          bag.error(
            'event_field_mismatch',
            `event_id ${eventId} 内で ${key} が行ごとに異なります`,
            {
              at: { sheet: 'events', row: row.__row, column: toColumn(key) },
              value: String(row[key]),
              fix: `同じ event_id の全行で ${toColumn(key)} を揃える(行${head.__row} は "${String(head[key])}")`,
            },
          );
        }
      }
    }
    for (const row of rows.slice(1)) {
      if (row.background !== head.background || row.advancesToPhase !== head.advancesToPhase) {
        bag.warning(
          'event_meta_mismatch',
          `event_id ${eventId} 内で background / advances_to_phase が不一致`,
          {
            at: { sheet: 'events', row: row.__row, column: 'background' },
            fix: '1行目の値だけが使われます。全行で揃えることを推奨',
          },
        );
      }
    }

    // entry scenario reference + type match
    if (!scenarioIds.has(head.entryScenarioId)) {
      bag.error('dangling_entry_scenario', `entry_scenario_id ${head.entryScenarioId} が参照切れ`, {
        at: { sheet: 'events', row: head.__row, column: 'entry_scenario_id' },
        value: head.entryScenarioId,
        fix: 'scenarios シートに存在する scenario_id を指定',
      });
    } else {
      const scnType = scenarioTypeById.get(head.entryScenarioId);
      if (scnType !== head.eventType) {
        bag.error(
          'event_scenario_type_mismatch',
          `event_type "${head.eventType}" と参照先シナリオの scenario_type "${scnType}" が一致しません`,
          {
            at: { sheet: 'events', row: head.__row, column: 'event_type' },
            value: `${head.eventType} ≠ ${scnType}`,
            fix: 'event_type と entry_scenario の scenario_type を揃える(small_event / large_event)',
          },
        );
      }
    }

    // priority uniqueness (stable ordering)
    const dupPriority = priorities.get(head.priority);
    if (dupPriority && dupPriority !== eventId) {
      bag.warning('duplicate_priority', `priority ${head.priority} が複数イベントで重複`, {
        at: { sheet: 'events', row: head.__row, column: 'priority' },
        value: String(head.priority),
        fix: `一意にすると解放順が安定します(重複相手: ${dupPriority})`,
      });
    } else {
      priorities.set(head.priority, eventId);
    }

    // condition semantics the app can actually enforce
    for (const row of rows) {
      const key = row.conditionKey;
      if (EVENT_COMPLETED_KEYS.has(key)) {
        if (row.operator !== 'exists' && row.operator !== 'eq') {
          bag.error(
            'bad_event_condition_operator',
            `${key} には operator "exists" を使ってください`,
            {
              at: { sheet: 'events', row: row.__row, column: 'operator' },
              value: row.operator,
            },
          );
        }
      } else if (METRIC_CONDITION_KEYS[key]) {
        if (row.operator !== 'gte' && row.operator !== 'gt') {
          bag.error(
            'unsupported_metric_operator',
            `メトリクス条件 (${key}) はアプリ側で下限のみ対応です。operator は gte または gt にしてください`,
            {
              at: { sheet: 'events', row: row.__row, column: 'operator' },
              value: row.operator,
              fix: 'gte(以上) / gt(超過) を使う',
            },
          );
        }
        if (!/^\d+$/.test(row.threshold)) {
          bag.error('bad_threshold', `${key} の threshold は非負整数にしてください`, {
            at: { sheet: 'events', row: row.__row, column: 'threshold' },
            value: row.threshold,
          });
        }
      } else {
        bag.error('unknown_condition_key', `condition_key "${key}" は未対応です`, {
          at: { sheet: 'events', row: row.__row, column: 'condition_key' },
          value: key,
          fix: `${[...Object.keys(METRIC_CONDITION_KEYS), ...EVENT_COMPLETED_KEYS].join(' / ')} のいずれか`,
        });
      }
    }
  }
}

function toColumn(field: string): string {
  return field
    .replace(/([A-Z])/g, '_$1')
    .toLowerCase()
    .replace('event_type', 'event_type');
}
