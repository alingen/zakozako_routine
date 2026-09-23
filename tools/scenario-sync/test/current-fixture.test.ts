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
  'premium_gate',
  'recording',
  'scene_transition',
  'silence',
  'state',
  'typing',
  'wait',
];
const EXPECTED_COMMANDS = [
  'call_connected',
  'call_end',
  'call_start',
  'clear_background',
  'hide_cg',
  'hide_portrait',
  'play_bgm',
  'play_audio',
  'premium_gate',
  'record_audio',
  'scene_change',
  'set_state',
  'show_cg',
  'show_portrait',
  'show_modal',
  'typing_hide',
  'typing_show',
  'wait',
];

const hasCurrentFixture = (() => {
  if (!existsSync(SNAPSHOT_PATH)) return false;
  const parsed = JSON.parse(readFileSync(SNAPSHOT_PATH, 'utf8')) as {
    tabs?: { daily_catalog?: unknown; asset_catalog?: unknown };
  };
  return Array.isArray(parsed.tabs?.daily_catalog) && Array.isArray(parsed.tabs?.asset_catalog);
})();

const raw = hasCurrentFixture
  ? snapshotToRawSheets(loadSnapshot())
  : {
      daily: [],
      dailyCatalog: [],
      assetCatalog: [],
      choices: [],
      interactions: [],
      scenarios: [],
      events: [],
    };
const normalized = normalize(raw);
const validated = validate(normalized.data);
const bundle = generate(normalized.data);

describe.skipIf(!hasCurrentFixture)('current Google Sheets fixture', () => {
  it('captures all current rows and detects the headers below the title area', () => {
    expect(raw.daily.length).toBeGreaterThan(0);
    expect(raw.dailyCatalog.length).toBeGreaterThan(0);
    expect(raw.assetCatalog.length).toBeGreaterThan(0);
    expect(raw.scenarios.length).toBeGreaterThan(0);
    expect(raw.choices.length).toBeGreaterThan(0);
    expect(raw.interactions.length).toBeGreaterThan(0);
    expect(raw.events.length).toBeGreaterThan(0);
    expect(raw.daily[0]?.__row).toBeGreaterThan(1);
    expect(raw.dailyCatalog[0]?.__row).toBeGreaterThan(1);
    expect(raw.assetCatalog[0]?.__row).toBeGreaterThan(1);
    expect(raw.scenarios[0]?.__row).toBeGreaterThan(1);
    expect(raw.choices[0]?.__row).toBeGreaterThan(1);
    expect(raw.interactions[0]?.__row).toBeGreaterThan(1);
    expect(raw.events[0]?.__row).toBeGreaterThan(1);
    const dailyHeaders = Object.keys(raw.daily[0] ?? {});
    for (const removedColumn of [
      'calendar_date',
      'calendar_month_day',
      'background',
      'portrait',
      'cg',
    ]) {
      expect(dailyHeaders).not.toContain(removedColumn);
    }
    expect(Object.keys(raw.dailyCatalog[0] ?? {})).toEqual(
      expect.arrayContaining([
        'scenario_id',
        'title',
        'display_order',
        'category',
        'calendar_date',
        'calendar_month_day',
        'status',
        'enabled',
      ]),
    );
    expect(normalized.issues.errors).toEqual([]);
  });

  it('contains the authored daily catalog, prologue, and chapter-01 episodes 1–7', () => {
    const daily = bundle.scenarios.filter((scenario) => scenario.scenarioType === 'daily');
    const scenarioById = new Map(
      bundle.scenarios.map((scenario) => [scenario.scenarioId, scenario]),
    );
    const chapterOneEpisodes = bundle.events
      .filter((event) => event.chapterId === 'chapter_01' && event.storyCategory === 'main')
      .filter(
        (event) =>
          event.episodeOrder !== undefined && event.episodeOrder >= 1 && event.episodeOrder <= 7,
      )
      .sort((left, right) => (left.episodeOrder ?? 0) - (right.episodeOrder ?? 0));
    const prologueEvent = bundle.events.find((event) => event.eventId === 'event_prologue_001');
    const prologueScenario = scenarioById.get('prologue_001');

    expect(daily.map((scenario) => scenario.scenarioId)).toEqual(['daily_q003']);
    expect(daily[0]).toMatchObject({
      title: '一人映画',
      calendarMonthDay: '09-16',
      enabled: true,
    });
    expect(prologueEvent).toMatchObject({
      eventType: 'prologue',
      title: 'プロローグ',
      entryScenarioId: 'prologue_001',
      chapterId: 'chapter_01',
      episodeOrder: 0,
      storyCategory: 'main',
    });
    expect(prologueScenario).toMatchObject({
      scenarioId: 'prologue_001',
      scenarioType: 'prologue',
    });
    expect(prologueScenario?.nodes).toHaveLength(55);
    expect(prologueScenario?.nodes[0]).toMatchObject({
      nodeId: 'prologue_001_001',
      screenMode: 'adv',
      uiVariant: 'scene_transition',
      command: 'scene_change',
      background: 'bg_protagonist_living_room',
    });
    expect(prologueScenario?.nodes).toContainEqual(
      expect.objectContaining({ text: 'LOSE', uiVariant: 'title_card' }),
    );
    expect(prologueScenario?.nodes.slice(10, 13)).toMatchObject([
      { text: 'おわり〜' },
      {
        command: 'play_se',
        assetId: 'se_defeat',
        commandArgs: { asset_id: 'se_defeat', volume: 1 },
      },
      { text: 'LOSE' },
    ]);
    expect(prologueScenario?.nodes).toContainEqual(
      expect.objectContaining({
        command: 'play_bgm',
        commandArgs: expect.objectContaining({
          asset_id: 'bgm_usually',
          loop: true,
          fade_ms: 1000,
          volume: 0.8,
        }),
      }),
    );
    expect(prologueScenario?.nodes).toContainEqual(
      expect.objectContaining({ command: 'clear_background' }),
    );
    expect(prologueScenario?.nodes.slice(14, 17)).toMatchObject([
      { command: 'show_portrait', assetId: 'portrait_rio_laugh' },
      { command: 'play_bgm', assetId: 'bgm_usually' },
      { text: 'あははっ' },
    ]);
    expect(prologueScenario?.nodes.slice(45, 49)).toMatchObject([
      { lineOrder: 46, command: 'clear_background' },
      {
        lineOrder: 47,
        command: 'hide_portrait',
        commandArgs: { action: 'hide', transition: 'fade' },
      },
      { lineOrder: 48, command: 'wait', commandArgs: { duration_ms: 300 } },
      { lineOrder: 49, text: '数週間前。' },
    ]);
    expect(prologueScenario?.nodes.some((node) => node.nodeId === 'prologue_001_054')).toBe(false);
    expect(chapterOneEpisodes.map((event) => event.episodeOrder)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    for (const event of [prologueEvent!, ...chapterOneEpisodes]) {
      expect(scenarioById.get(event.entryScenarioId)?.nodes.length).toBeGreaterThan(0);
    }
  });

  it('publishes the three migrated touch comments independently from scenarios', () => {
    expect(bundle.interactions.map((comment) => comment.text)).toEqual(
      expect.arrayContaining([
        'がんばってね、ざこざこおにいさん♡',
        'また負けちゃったんだ、ざ〜こ♡',
        '今回は何日もつかな〜？',
      ]),
    );
    expect(bundle.interactions.every((comment) => comment.touchArea === 'character')).toBe(true);
  });

  it('does not publish memo title cards in middle or large events', () => {
    const eventNodes = bundle.scenarios
      .filter(
        (scenario) =>
          scenario.scenarioType === 'middle_event' || scenario.scenarioType === 'large_event',
      )
      .flatMap((scenario) => scenario.nodes);

    expect(eventNodes.filter((node) => node.uiVariant === 'title_card')).toEqual([]);
  });

  it('preserves every current mode, variant, command, and raw content field', () => {
    const nodes = bundle.scenarios.flatMap((scenario) => scenario.nodes);
    const values = (pick: (node: (typeof nodes)[number]) => string | undefined) =>
      [...new Set(nodes.map(pick).filter((value): value is string => value !== undefined))].sort();

    expect(values((node) => node.screenMode)).toEqual(expect.arrayContaining(EXPECTED_MODES));
    expect(values((node) => node.uiVariant)).toEqual(expect.arrayContaining(EXPECTED_VARIANTS));
    expect(values((node) => node.command)).toEqual(expect.arrayContaining(EXPECTED_COMMANDS));
    expect([...new Set(bundle.scenarios.map((scenario) => scenario.scenarioType))]).toEqual(
      expect.arrayContaining(['daily', 'prologue', 'small_event', 'middle_event', 'large_event']),
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
    expect(chapterOne.map((event) => event.episodeOrder)).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
    expect(chapterOne[0]).toMatchObject({
      eventId: 'event_prologue_001',
      episodeOrder: 0,
      conditions: [
        {
          conditionType: 'achievement',
          conditionKey: 'cumulative_days',
          operator: 'gte',
          threshold: '0',
        },
      ],
    });
    for (const [index, event] of chapterOne.slice(1).entries()) {
      expect(event.episodeOrder).toBe(index + 1);
      expect(event.conditions).toEqual([
        {
          conditionType: 'achievement',
          conditionKey: 'cumulative_days',
          operator: 'gte',
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

    expect(groups.size).toBe(1);
    expect(bundle.choiceGroups.reduce((total, group) => total + group.choices.length, 0)).toBe(2);
    expect(choiceNodes.length).toBe(1);
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
      daily: [...normalized.data.daily].reverse(),
      dailyCatalog: [...normalized.data.dailyCatalog].reverse(),
      assetCatalog: [...normalized.data.assetCatalog].reverse(),
      scenarios: [...normalized.data.scenarios].reverse(),
      choices: [...normalized.data.choices].reverse(),
      interactions: [...normalized.data.interactions].reverse(),
      events: [...normalized.data.events].reverse(),
    };
    const content = serialize(bundle);

    expect(serialize(generate(reversed))).toBe(content);
    expect(existsSync(OUTPUT_PATH)).toBe(true);
    expect(readFileSync(OUTPUT_PATH, 'utf8')).toBe(content);
  });
});
