import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { OUTPUT_PATH, SNAPSHOT_PATH } from '../src/config.js';
import { loadSnapshot, snapshotToRawSheets } from '../src/fetch.js';
import { generate, serialize } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';

const EXPECTED_MODES = ['adv', 'chat'];
const EXPECTED_VARIANTS = ['dialogue', 'narration', 'scene_transition', 'title_card'];
const EXPECTED_COMMANDS = [
  'clear_background',
  'hide_portrait',
  'play_bgm',
  'play_se',
  'scene_change',
  'show_portrait',
  'stop_bgm',
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

  it('contains the authored daily catalog, prologue, and chapter episodes', () => {
    const daily = bundle.scenarios.filter((scenario) => scenario.scenarioType === 'daily');
    const scenarioById = new Map(
      bundle.scenarios.map((scenario) => [scenario.scenarioId, scenario]),
    );
    const chapterOneEpisodes = bundle.events
      .filter((event) => event.chapterId === 'chapter_01' && event.storyCategory === 'main')
      .filter((event) => event.episodeOrder !== undefined && event.episodeOrder >= 1)
      .sort((left, right) => (left.episodeOrder ?? 0) - (right.episodeOrder ?? 0));
    const prologueEvent = bundle.events.find((event) => event.eventId === 'event_prologue_001');
    const prologueScenario = scenarioById.get('prologue_001');
    const middleEvent = bundle.events.find((event) => event.eventId === 'event_middle_001_1');
    const middleScenario = scenarioById.get('middle_001_1');
    const secondMiddleEvent = bundle.events.find(
      (event) => event.eventId === 'event_middle_001_2',
    );
    const secondMiddleScenario = scenarioById.get('middle_001_2');

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
    expect(middleEvent).toMatchObject({
      eventType: 'middle_event',
      title: '人生再建プログラム',
      entryScenarioId: 'middle_001_1',
      chapterId: 'chapter_01',
      episodeOrder: 1,
      storyCategory: 'main',
    });
    expect(middleScenario).toMatchObject({
      scenarioId: 'middle_001_1',
      scenarioType: 'middle_event',
    });
    expect(middleScenario?.nodes).toHaveLength(149);
    expect(middleScenario?.nodes.slice(0, 4)).toMatchObject([
      { command: 'clear_background' },
      { command: 'hide_portrait' },
      { text: '人生はいつからでも[br]変えることができる。' },
      { text: '今日がその日だ。' },
    ]);
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 8)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 500 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 15)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 800 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 16)).toMatchObject({
      command: 'scene_change',
      background: 'bg_protagonist_my_room',
      commandArgs: expect.objectContaining({ background: 'bg_protagonist_my_room' }),
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 21)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 500 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 22)).toMatchObject({
      command: 'play_se',
      assetId: 'se_keyboard_typing',
      commandArgs: expect.objectContaining({ action: 'play', loop: true, volume: 0.5 }),
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 23)).toMatchObject({
      text: 'カタカタカタ',
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 25)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 500 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 27)).toMatchObject({
      text: '『挑戦てwww[br]書くだけで挑戦とか言えちゃう[br]感性見習いたいわw』',
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 42)).toMatchObject({
      command: 'play_se',
      assetId: 'se_keyboard_typing',
      commandArgs: expect.objectContaining({ action: 'stop' }),
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 44)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 300 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 46)).toMatchObject({
      command: 'clear_background',
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 47)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 1000 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 54)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 500 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 56)).toMatchObject({
      command: 'play_bgm',
      assetId: 'bgm_usually',
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 79)).toMatchObject({
      command: 'scene_change',
      background: 'bg_protagonist_living_room',
      commandArgs: expect.objectContaining({ transition: { type: 'colorSlide' } }),
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 107)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 500 },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 119)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 1000 },
    });
    expect(middleScenario?.nodes.some((node) => node.uiVariant === 'beat')).toBe(false);
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 131)).toMatchObject({
      command: 'scene_change',
      background: 'bg_protagonist_living_room',
      commandArgs: expect.objectContaining({
        transition: { type: 'colorSlide' },
        label: 'リビング',
      }),
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 140)).toMatchObject({
      command: 'stop_bgm',
      assetId: 'bgm_usually',
      commandArgs: {
        action: 'stop',
        asset_id: 'bgm_usually',
        fade_ms: 1000,
        volume: 0.8,
      },
    });
    expect(middleScenario?.nodes.find((node) => node.lineOrder === 144)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 1000 },
    });
    expect(middleScenario?.nodes.at(-1)).toMatchObject({
      lineOrder: 149,
      text: 'それは[br]俺が一番見られたくないノートだった。',
    });
    expect(secondMiddleEvent).toMatchObject({
      eventType: 'middle_event',
      title: 'Day first',
      entryScenarioId: 'middle_001_2',
      priority: 101,
      chapterId: 'chapter_01',
      episodeOrder: 2,
      storyCategory: 'main',
    });
    expect(secondMiddleScenario).toMatchObject({
      scenarioId: 'middle_001_2',
      scenarioType: 'middle_event',
    });
    expect(secondMiddleScenario?.nodes).toHaveLength(160);
    expect(secondMiddleScenario?.nodes.slice(0, 8)).toMatchObject([
      {
        lineOrder: 1,
        command: 'scene_change',
        background: 'bg_protagonist_living_room',
        commandArgs: expect.objectContaining({ scene_id: 'middle_001_2_recap' }),
      },
      { lineOrder: 2, command: 'hide_portrait' },
      {
        lineOrder: 3,
        command: 'play_bgm',
        assetId: 'bgm_usually',
        commandArgs: {
          action: 'play',
          asset_id: 'bgm_usually',
          loop: true,
          fade_ms: 1000,
          volume: 0.8,
        },
      },
      { lineOrder: 4, text: '前回のあらすじ。' },
      {
        lineOrder: 5,
        text: '俺がゲームに夢中になっていると[br]『人生再建プログラム』の単語が耳に入った。',
      },
      { lineOrder: 6, text: 'ちらっと横を見る。' },
      {
        lineOrder: 7,
        command: 'show_portrait',
        assetId: 'portrait_rio_focused',
      },
      { lineOrder: 8, text: '莉央が机の上に置いてあった[br]1冊のノートを開いている。' },
    ]);
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 11)).toMatchObject({
      text: 'あいつの「男磨きビレッジ」に[br]参加しようか迷ったこともあった。',
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 23)).toMatchObject({
      command: 'stop_bgm',
      commandArgs: { action: 'stop' },
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 34)).toMatchObject({
      command: 'play_bgm',
      assetId: 'bgm_mischief',
      commandArgs: expect.objectContaining({ loop: true, fade_ms: 1000, volume: 0.8 }),
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 38)).toMatchObject({
      command: 'play_se',
      assetId: 'se_damage',
      commandArgs: { action: 'play', asset_id: 'se_damage', volume: 0.55 },
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 68)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 600 },
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 128)).toMatchObject({
      command: 'scene_change',
      background: 'bg_protagonist_living_room',
      commandArgs: expect.objectContaining({ transition: { type: 'colorSlide' } }),
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 155)).toMatchObject({
      command: 'wait',
      commandArgs: { duration_ms: 600 },
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 70)).toMatchObject({
      command: 'play_se',
      assetId: 'se_turn_the_page',
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 72)).toMatchObject({
      command: 'stop_bgm',
      commandArgs: { action: 'stop' },
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 77)).toMatchObject({
      command: 'play_bgm',
      assetId: 'bgm_usually',
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 139)).toMatchObject({
      command: 'stop_bgm',
      assetId: 'bgm_usually',
      commandArgs: expect.objectContaining({ action: 'stop', fade_ms: 1000 }),
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 147)).toMatchObject({
      command: 'play_se',
      assetId: 'se_turn_some_page',
    });
    expect(secondMiddleScenario?.nodes.find((node) => node.lineOrder === 160)).toMatchObject({
      speaker: 'rio',
      text: '私しかいないじゃん',
    });
    expect(chapterOneEpisodes.map((event) => event.episodeOrder)).toEqual([1, 2]);
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

    expect(values((node) => node.screenMode)).toEqual(EXPECTED_MODES);
    expect(values((node) => node.uiVariant)).toEqual(EXPECTED_VARIANTS);
    expect(values((node) => node.command)).toEqual(EXPECTED_COMMANDS);
    expect([...new Set(bundle.scenarios.map((scenario) => scenario.scenarioType))]).toEqual([
      'daily',
      'middle_event',
      'prologue',
    ]);
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
      .filter((event) => event.episodeOrder !== undefined)
      .sort((left, right) => (left.episodeOrder ?? 0) - (right.episodeOrder ?? 0));
    expect(chapterOne.map((event) => event.episodeOrder)).toEqual([0, 1, 2]);
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
    expect(chapterOne[1]).toMatchObject({
      eventId: 'event_middle_001_1',
      episodeOrder: 1,
      conditions: [
        {
          conditionType: 'achievement',
          conditionKey: 'cumulative_days',
          operator: 'gte',
          threshold: '1',
        },
      ],
    });
    expect(chapterOne[2]).toMatchObject({
      eventId: 'event_middle_001_2',
      episodeOrder: 2,
      conditions: [
        {
          conditionType: 'achievement',
          conditionKey: 'cumulative_days',
          operator: 'gte',
          threshold: '2',
        },
      ],
    });
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
