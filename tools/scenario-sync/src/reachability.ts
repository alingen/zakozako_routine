import type { NormalizedScenarioRow, NormalizedChoiceRow } from './types.js';
import { IssueBag } from './issues.js';

interface ScenarioGraph {
  scenarioId: string;
  sheet: 'scenarios';
  /** node id -> row */
  nodes: Map<string, NormalizedScenarioRow>;
  /** ordered node ids by line_order */
  ordered: NormalizedScenarioRow[];
}

/**
 * Walks each scenario as a directed graph and reports:
 *  - transitions pointing at a node that does not exist (in the same scenario)
 *  - nodes that can never be reached from the entry node
 *  - cycles that have no exit (a definite infinite loop)
 */
export function checkReachability(
  bag: IssueBag,
  scenarios: NormalizedScenarioRow[],
  choicesByGroup: Map<string, NormalizedChoiceRow[]>,
): void {
  const groups = new Map<string, NormalizedScenarioRow[]>();
  for (const row of scenarios) {
    if (!groups.has(row.scenarioId)) groups.set(row.scenarioId, []);
    groups.get(row.scenarioId)!.push(row);
  }

  for (const [scenarioId, rows] of groups) {
    const ordered = [...rows].sort((a, b) => a.lineOrder - b.lineOrder);
    const nodes = new Map<string, NormalizedScenarioRow>();
    for (const r of ordered) nodes.set(r.nodeId, r);
    const graph: ScenarioGraph = {
      scenarioId,
      sheet: 'scenarios',
      nodes,
      ordered,
    };

    const successors = (node: NormalizedScenarioRow): string[] => {
      const out: string[] = [];
      if (node.messageType === 'choice' && node.choiceId) {
        for (const c of choicesByGroup.get(node.choiceId) ?? []) {
          if (c.nextNodeId) out.push(c.nextNodeId);
        }
      }
      if (node.nextNodeId) {
        out.push(node.nextNodeId);
      } else if (node.messageType !== 'choice') {
        // fall through to the next line
        const idx = ordered.findIndex((r) => r.nodeId === node.nodeId);
        const nextRow = ordered[idx + 1];
        if (nextRow) out.push(nextRow.nodeId);
      }
      return out;
    };

    // dangling transitions
    for (const node of ordered) {
      for (const target of successors(node)) {
        if (!nodes.has(target)) {
          bag.error(
            'dangling_transition',
            `遷移先ノード ${target} が同じシナリオ内に存在しません`,
            {
              at: {
                sheet: 'scenarios',
                row: node.__row,
                column: 'next_node_id',
              },
              value: target,
              fix: `${scenarioId} 内に node_id=${target} の行を作るか、遷移先を修正`,
            },
          );
        }
      }
    }

    // reachability from entry (first line)
    const entry = ordered[0];
    if (!entry) continue;
    const reachable = new Set<string>();
    const stack = [entry.nodeId];
    while (stack.length) {
      const id = stack.pop()!;
      if (reachable.has(id)) continue;
      reachable.add(id);
      const node = nodes.get(id);
      if (!node) continue;
      for (const t of successors(node)) if (nodes.has(t) && !reachable.has(t)) stack.push(t);
    }
    for (const node of ordered) {
      if (!reachable.has(node.nodeId)) {
        bag.error('unreachable_node', `ノード ${node.nodeId} は開始ノードから到達できません`, {
          at: { sheet: 'scenarios', row: node.__row, column: 'node_id' },
          value: node.nodeId,
          fix: 'どこかの next_node_id / 選択肢の遷移先に含めるか、不要なら enabled=FALSE',
        });
      }
    }

    detectInfiniteLoop(bag, graph, successors);
  }
}

/**
 * A cycle is only a problem if none of its nodes can ever reach an ending.
 * Fixpoint: start from terminal nodes (no in-scenario successors), then keep
 * adding any node that has a successor already known to reach an ending.
 * Whatever is left cannot terminate.
 */
function detectInfiniteLoop(
  bag: IssueBag,
  graph: ScenarioGraph,
  successors: (n: NormalizedScenarioRow) => string[],
): void {
  const { ordered, nodes } = graph;
  const succById = new Map<string, string[]>();
  for (const node of ordered) {
    succById.set(
      node.nodeId,
      successors(node).filter((t) => nodes.has(t)),
    );
  }

  const canEnd = new Set<string>();
  for (const [id, succ] of succById) if (succ.length === 0) canEnd.add(id);

  let changed = true;
  while (changed) {
    changed = false;
    for (const [id, succ] of succById) {
      if (canEnd.has(id)) continue;
      if (succ.some((t) => canEnd.has(t))) {
        canEnd.add(id);
        changed = true;
      }
    }
  }

  for (const node of ordered) {
    if (!canEnd.has(node.nodeId)) {
      bag.error(
        'infinite_loop',
        `ノード ${node.nodeId} から会話を終了できません(出口の無いループ)`,
        {
          at: { sheet: 'scenarios', row: node.__row, column: 'next_node_id' },
          value: node.nodeId,
          fix: 'ループのどこかに末尾ノード(next_node_id 空)か外への遷移を用意',
        },
      );
    }
  }
}
