import type { NormalizedChoiceRow, NormalizedScenarioRow, NormalizedSheets } from './types.js';
import { IssueBag } from './issues.js';

/** Validate graph reachability and detect components that can never terminate. */
export function checkReachability(data: NormalizedSheets, bag: IssueBag): void {
  const choicesById = groupChoices(data.choices);
  const scenarios = groupScenarios(data.scenarios);

  for (const [scenarioId, rows] of scenarios) {
    const ordered = [...rows].sort(
      (left, right) => left.lineOrder - right.lineOrder || compareText(left.nodeId, right.nodeId),
    );
    if (ordered.length === 0) continue;
    const nodes = new Map(ordered.map((row) => [row.nodeId, row]));
    const indexById = new Map(ordered.map((row, index) => [row.nodeId, index]));
    const successors = (node: NormalizedScenarioRow, repairDanglingChoices = false): string[] => {
      const values: string[] = [];
      const fallthrough = ordered[(indexById.get(node.nodeId) ?? -1) + 1]?.nodeId;
      const choices = node.choiceId ? (choicesById.get(node.choiceId) ?? []) : [];

      if (node.messageType === 'choice' && choices.length > 0) {
        for (const choice of choices) {
          let target = choice.nextNodeId ?? node.nextNodeId ?? fallthrough;
          if (repairDanglingChoices && choice.nextNodeId && !nodes.has(choice.nextNodeId)) {
            // Match StoryPlayer's recovery path: once the selected choice's
            // explicit edge fails, ignore every explicit edge on the choice
            // node and continue by line order.
            target = fallthrough;
          }
          if (target) values.push(target);
        }
      } else {
        const target = node.nextNodeId ?? fallthrough;
        if (target) values.push(target);
      }
      return [...new Set(values)];
    };

    const reachable = collectReachable(ordered[0]!.nodeId, nodes, (node) => successors(node));
    const reachableWithFallback = collectReachable(ordered[0]!.nodeId, nodes, (node) =>
      successors(node, true),
    );
    const uncertainBranchNodes = collectUncertainBranchNodes(
      ordered,
      nodes,
      indexById,
      choicesById,
    );

    for (const node of ordered) {
      if (reachable.has(node.nodeId)) continue;
      const details = {
        at: { sheet: 'scenarios', row: node.__row, column: 'node_id' },
        value: scenarioId,
      } as const;
      if (reachableWithFallback.has(node.nodeId) || uncertainBranchNodes.has(node.nodeId)) {
        bag.warning(
          'unverifiable_after_dangling_choice',
          `Node ${node.nodeId} reachability cannot be proven while an earlier choice target is missing`,
          details,
        );
      } else {
        bag.error(
          'unreachable_node',
          `Node ${node.nodeId} is unreachable from the scenario entry`,
          details,
        );
      }
    }

    const inScenarioSuccessors = new Map<string, string[]>();
    for (const node of ordered) {
      inScenarioSuccessors.set(
        node.nodeId,
        successors(node, true).filter((target) => nodes.has(target)),
      );
    }

    const canTerminate = new Set<string>();
    for (const [id, targets] of inScenarioSuccessors) {
      if (targets.length === 0) canTerminate.add(id);
    }
    let changed = true;
    while (changed) {
      changed = false;
      for (const [id, targets] of inScenarioSuccessors) {
        if (canTerminate.has(id)) continue;
        if (targets.some((target) => canTerminate.has(target))) {
          canTerminate.add(id);
          changed = true;
        }
      }
    }

    for (const node of ordered) {
      if (reachableWithFallback.has(node.nodeId) && !canTerminate.has(node.nodeId)) {
        bag.error('infinite_loop', `Node ${node.nodeId} cannot reach a scenario ending`, {
          at: { sheet: 'scenarios', row: node.__row, column: 'next_node_id' },
          value: scenarioId,
        });
      }
    }
  }
}

/**
 * A missing choice edge can hide an alternate branch placed between the
 * line-order recovery arm and its first explicit forward merge. Only that
 * narrow skipped range is uncertain; later disconnected islands remain hard
 * errors instead of being masked by an earlier CMS defect.
 */
function collectUncertainBranchNodes(
  ordered: NormalizedScenarioRow[],
  nodes: Map<string, NormalizedScenarioRow>,
  indexById: Map<string, number>,
  choicesById: Map<string, NormalizedChoiceRow[]>,
): Set<string> {
  const uncertain = new Set<string>();

  for (const choiceNode of ordered) {
    if (
      !choiceNode.choiceId ||
      !(choicesById.get(choiceNode.choiceId) ?? []).some(
        (choice) => choice.nextNodeId && !nodes.has(choice.nextNodeId),
      )
    ) {
      continue;
    }

    let cursorIndex = (indexById.get(choiceNode.nodeId) ?? -1) + 1;
    const visited = new Set<string>();
    while (cursorIndex >= 0 && cursorIndex < ordered.length) {
      const cursor = ordered[cursorIndex]!;
      if (visited.has(cursor.nodeId) || cursor.messageType === 'choice') break;
      visited.add(cursor.nodeId);

      if (cursor.nextNodeId) {
        const targetIndex = indexById.get(cursor.nextNodeId);
        if (targetIndex !== undefined && targetIndex > cursorIndex + 1) {
          for (let index = cursorIndex + 1; index < targetIndex; index += 1) {
            uncertain.add(ordered[index]!.nodeId);
          }
        }
        break;
      }

      cursorIndex += 1;
    }
  }

  return uncertain;
}

function collectReachable(
  entryNodeId: string,
  nodes: Map<string, NormalizedScenarioRow>,
  successors: (node: NormalizedScenarioRow) => string[],
): Set<string> {
  const reachable = new Set<string>();
  const stack = [entryNodeId];
  while (stack.length > 0) {
    const id = stack.pop()!;
    if (reachable.has(id)) continue;
    reachable.add(id);
    const node = nodes.get(id);
    if (!node) continue;
    for (const target of successors(node)) {
      if (nodes.has(target) && !reachable.has(target)) stack.push(target);
    }
  }
  return reachable;
}

function groupChoices(rows: NormalizedChoiceRow[]): Map<string, NormalizedChoiceRow[]> {
  const result = new Map<string, NormalizedChoiceRow[]>();
  for (const row of rows) {
    const group = result.get(row.choiceId) ?? [];
    group.push(row);
    result.set(row.choiceId, group);
  }
  return result;
}

function groupScenarios(rows: NormalizedScenarioRow[]): Map<string, NormalizedScenarioRow[]> {
  const result = new Map<string, NormalizedScenarioRow[]>();
  for (const row of rows) {
    const group = result.get(row.scenarioId) ?? [];
    group.push(row);
    result.set(row.scenarioId, group);
  }
  return result;
}

function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
