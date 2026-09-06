import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { OUTPUT_PATH, SNAPSHOT_PATH } from '../src/config.js';
import { loadSnapshot, snapshotToRawSheets } from '../src/fetch.js';
import { generate, serialize } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';

const EXPECTED_MODES = ['adv', 'call', 'chat'];
const EXPECTED_VARIANTS = [
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
];
const EXPECTED_COMMANDS = [
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
];

describe('current Google Sheets fixture', () => {
  if (!existsSync(SNAPSHOT_PATH)) {
    throw new Error(
      `Missing ${SNAPSHOT_PATH}. Create it from the live source with ` +
        '`npm run sync -- --save-snapshot`.',
    );
  }

  const snapshot = loadSnapshot();
  const raw = snapshotToRawSheets(snapshot);
  const normalized = normalize(raw);
  const validated = validate(normalized.data);
  const bundle = generate(normalized.data);

  it('captures all current rows and detects the headers below the title area', () => {
    expect(raw.scenarios.length).toBeGreaterThan(0);
    expect(raw.choices.length).toBeGreaterThan(0);
    expect(raw.events.length).toBeGreaterThan(0);
    expect(raw.scenarios[0]?.__row).toBeGreaterThan(1);
    expect(raw.choices[0]?.__row).toBeGreaterThan(1);
    expect(raw.events[0]?.__row).toBeGreaterThan(1);
    expect(normalized.issues.errors).toEqual([]);
  });

  it('contains the daily catalog and chapter-01 episodes 1–7 with entry scenarios', () => {
    const daily = bundle.scenarios.filter((scenario) => scenario.scenarioType === 'daily');
    const scenarioById = new Map(
      bundle.scenarios.map((scenario) => [scenario.scenarioId, scenario]),
    );
    const chapterOne = bundle.events
      .filter((event) => event.chapterId === 'chapter_01' && event.storyCategory === 'main')
      .filter((event) => event.episodeOrder !== undefined && event.episodeOrder <= 7)
      .sort((left, right) => (left.episodeOrder ?? 0) - (right.episodeOrder ?? 0));

    expect(daily.length).toBeGreaterThanOrEqual(14);
    expect(chapterOne.map((event) => event.episodeOrder)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    for (const event of chapterOne) {
      expect(scenarioById.get(event.entryScenarioId)?.nodes.length).toBeGreaterThan(0);
    }
  });

  it('preserves every current mode, variant, command, and raw content field', () => {
    const nodes = bundle.scenarios.flatMap((scenario) => scenario.nodes);
    const values = (pick: (node: (typeof nodes)[number]) => string | undefined) =>
      [...new Set(nodes.map(pick).filter((value): value is string => value !== undefined))].sort();

    expect(values((node) => node.screenMode)).toEqual(expect.arrayContaining(EXPECTED_MODES));
    expect(values((node) => node.uiVariant)).toEqual(expect.arrayContaining(EXPECTED_VARIANTS));
    expect(values((node) => node.command)).toEqual(expect.arrayContaining(EXPECTED_COMMANDS));
    expect([...new Set(bundle.scenarios.map((scenario) => scenario.scenarioType))]).toEqual(
      expect.arrayContaining(['daily', 'small_event', 'middle_event', 'large_event']),
    );
    expect(nodes.some((node) => node.speaker === 'protagonist')).toBe(true);
    expect(nodes.some((node) => node.messageType === 'action')).toBe(true);
    expect(nodes.some((node) => node.commandArgs && typeof node.commandArgs === 'object')).toBe(
      true,
    );
  });

  it('preserves chapter, episode, category, and raw AND condition rows', () => {
    expect(bundle.events.map((event) => event.chapterId)).toContain('chapter_01');
    expect(bundle.events.map((event) => event.storyCategory)).toContain('main');
    const chapterOne = bundle.events
      .filter((event) => event.chapterId === 'chapter_01' && event.storyCategory === 'main')
      .filter((event) => event.episodeOrder !== undefined && event.episodeOrder <= 7)
      .sort((left, right) => (left.episodeOrder ?? 0) - (right.episodeOrder ?? 0));
    expect(chapterOne.map((event) => event.episodeOrder)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    for (const [index, event] of chapterOne.entries()) {
      expect(event.episodeOrder).toBe(index + 1);
      expect(event.conditions).toEqual([
        {
          conditionType: 'streak',
          conditionKey: 'continuous_days',
          operator: 'eq',
          threshold: String(index + 1),
        },
      ]);
    }
  });

  it('retains branches and validates choice references within each scenario', () => {
    const groups = new Map(bundle.choiceGroups.map((group) => [group.choiceId, group]));
    const choiceNodes = bundle.scenarios.flatMap((scenario) =>
      scenario.nodes
        .filter((node) => node.messageType === 'choice')
        .map((node) => ({ scenario, node })),
    );

    expect(groups.size).toBeGreaterThanOrEqual(10);
    expect(
      bundle.choiceGroups.reduce((total, group) => total + group.choices.length, 0),
    ).toBeGreaterThanOrEqual(20);
    expect(choiceNodes.length).toBeGreaterThanOrEqual(10);
    const reportedDanglingTargets = new Set(
      validated.issues.warnings
        .filter((issue) => issue.code === 'dangling_choice_next')
        .map((issue) => issue.value),
    );
    for (const { scenario, node } of choiceNodes) {
      const group = groups.get(node.choiceId ?? '');
      expect(group, `missing choice group ${node.choiceId}`).toBeDefined();
      const nodeIds = new Set(scenario.nodes.map((candidate) => candidate.nodeId));
      for (const option of group!.choices) {
        if (!option.nextNodeId) continue;
        expect(
          nodeIds.has(option.nextNodeId) || reportedDanglingTargets.has(option.nextNodeId),
        ).toBe(true);
      }
    }
  });

  it('reports every current dangling choice target instead of silently dropping it', () => {
    expect(validated.issues.errors).toEqual([]);
    const allNodeIds = new Set(
      bundle.scenarios.flatMap((scenario) => scenario.nodes.map((node) => node.nodeId)),
    );
    const missingTargets = bundle.choiceGroups
      .flatMap((group) =>
        group.choices.map((choice) => ({ choiceId: group.choiceId, target: choice.nextNodeId })),
      )
      .filter(({ target }) => target && !allNodeIds.has(target))
      .map(({ target }) => target!)
      .sort();
    const dangling = validated.issues.warnings.filter(
      (issue) => issue.code === 'dangling_choice_next',
    );

    expect(dangling.map((issue) => issue.value).sort()).toEqual(missingTargets);
  });

  it('is deterministic and matches the committed generated artifact', () => {
    const reversed = {
      scenarios: [...normalized.data.scenarios].reverse(),
      choices: [...normalized.data.choices].reverse(),
      events: [...normalized.data.events].reverse(),
    };
    const content = serialize(bundle);

    expect(serialize(generate(reversed))).toBe(content);
    expect(existsSync(OUTPUT_PATH)).toBe(true);
    expect(readFileSync(OUTPUT_PATH, 'utf8')).toBe(content);
  });
});
