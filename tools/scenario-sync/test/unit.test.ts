import { describe, expect, it } from 'vitest';
import { parseArgs } from '../src/cli.js';
import { generate, serialize } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { runPipeline } from '../src/pipeline.js';
import { validate } from '../src/validate.js';
import {
  assetCatalog,
  choice,
  dailyCatalog,
  event,
  interaction,
  scenario,
  sheets,
} from './helpers.js';

function process(raw: ReturnType<typeof sheets>) {
  const normalized = normalize(raw);
  const validated = validate(normalized.data);
  return {
    data: normalized.data,
    errors: [...normalized.issues.errors, ...validated.issues.errors],
    warnings: [...normalized.issues.warnings, ...validated.issues.warnings],
  };
}

describe('source normalization', () => {
  it('detects a real header below title rows and treats blank enabled as true', () => {
    const raw = sheets({ titleRows: 2, scenarios: [scenario()] });
    const result = process(raw);

    expect(raw.daily[0]?.__row).toBe(4);
    expect(raw.dailyCatalog).toHaveLength(1);
    expect(raw.dailyCatalog[0]?.__row).toBe(4);
    expect(result.errors).toEqual([]);
    expect(result.data.daily[0]?.enabled).toBe(true);
    expect(result.data.dailyCatalog[0]?.scenarioId).toBe('daily_test');
  });

  it('keeps nested command_args and open string values while warning on unknown UI values', () => {
    const raw = sheets({
      scenarios: [
        scenario({
          speaker: 'guest_character',
          message_type: 'gesture',
          screen_mode: 'immersive',
          ui_variant: 'future_card',
          command: 'future_command',
          command_args: '{"duration":{"seconds":2},"flags":[true,null,"x"]}',
        }),
      ],
    });
    const result = process(raw);
    const node = generate(result.data).scenarios[0]!.nodes[0]!;

    expect(result.errors).toEqual([]);
    expect(result.warnings.filter((issue) => issue.code === 'unknown_value')).toHaveLength(4);
    expect(node.speaker).toBe('guest_character');
    expect(node.messageType).toBe('gesture');
    expect(node.screenMode).toBe('immersive');
    expect(node.uiVariant).toBe('future_card');
    expect(node.command).toBe('future_command');
    expect(node.commandArgs).toEqual({
      duration: { seconds: 2 },
      flags: [true, null, 'x'],
    });
  });

  it('accepts clear_background as a known command without arguments', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            scenario_type: 'small_event',
            message_type: 'action',
            ui_variant: 'scene_transition',
            command: 'clear_background',
          }),
        ],
      }),
    );
    const node = generate(result.data).scenarios[0]!.nodes[0]!;

    expect(result.errors).toEqual([]);
    expect(
      result.warnings.filter(
        (issue) => issue.code === 'unknown_value' && issue.at?.column === 'command',
      ),
    ).toEqual([]);
    expect(node.command).toBe('clear_background');
    expect(node.commandArgs).toBeUndefined();
  });

  it.each(['show_portrait', 'hide_portrait', 'play_bgm', 'play_se', 'stop_bgm'])(
    'accepts %s as a known presentation command',
    (command) => {
      const result = process(
        sheets({
          scenarios: [
            scenario({
              scenario_type: 'prologue',
              message_type: 'action',
              ui_variant: 'scene_transition',
              command,
            }),
          ],
        }),
      );

      expect(
        result.warnings.filter(
          (issue) => issue.code === 'unknown_value' && issue.at?.column === 'command',
        ),
      ).toEqual([]);
    },
  );

  it('preserves a per-line Rio typing duration', () => {
    const raw = sheets({ scenarios: [scenario({ typing_duration_ms: 650 })] });
    const result = process(raw);
    const node = generate(result.data).scenarios[0]!.nodes[0]!;

    expect(result.errors).toEqual([]);
    expect(node.typingDurationMs).toBe(650);
  });

  it('publishes exact and recurring calendar metadata at scenario level', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario(),
          scenario({
            scenario_id: 'daily_recurring',
            node_id: 'recurring_01',
          }),
        ],
        catalogs: [
          dailyCatalog({
            title: 'Exact daily',
            display_order: 7,
            category: 'question',
            calendar_date: '2026-09-13',
            status: 'ready',
          }),
          dailyCatalog({
            scenario_id: 'daily_recurring',
            title: 'Recurring daily',
            display_order: '',
            calendar_month_day: '12-24',
          }),
        ],
      }),
    );
    const generated = generate(result.data).scenarios;

    expect(result.errors).toEqual([]);
    expect(generated.find((item) => item.scenarioId === 'daily_test')).toMatchObject({
      title: 'Exact daily',
      displayOrder: 7,
      category: 'question',
      calendarDate: '2026-09-13',
      status: 'ready',
      enabled: true,
    });
    expect(generated.find((item) => item.scenarioId === 'daily_recurring')).toMatchObject({
      calendarMonthDay: '12-24',
    });
    expect(generated.flatMap((item) => item.nodes).every((node) => !('calendarDate' in node))).toBe(
      true,
    );
  });

  it('rejects invalid, conflicting, and duplicate daily calendar metadata', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            scenario_id: 'daily_invalid',
            node_id: 'invalid_01',
          }),
          scenario({
            scenario_id: 'daily_conflict',
            node_id: 'conflict_01',
          }),
          scenario({
            scenario_id: 'daily_duplicate_a',
            node_id: 'duplicate_a_01',
          }),
          scenario({
            scenario_id: 'daily_duplicate_b',
            node_id: 'duplicate_b_01',
          }),
        ],
        catalogs: [
          dailyCatalog({
            scenario_id: 'daily_invalid',
            calendar_date: '2026-02-30',
          }),
          dailyCatalog({
            scenario_id: 'daily_conflict',
            calendar_date: '2026-09-13',
            calendar_month_day: '09-13',
          }),
          dailyCatalog({
            scenario_id: 'daily_duplicate_a',
            calendar_month_day: '12-24',
          }),
          dailyCatalog({
            scenario_id: 'daily_duplicate_b',
            calendar_month_day: '12-24',
          }),
        ],
      }),
    );

    expect(result.errors.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        'invalid_calendar_date',
        'daily_schedule_conflict',
        'duplicate_daily_schedule',
      ]),
    );
  });

  it('ignores unchecked checkbox-only catalog rows', () => {
    const result = process(
      sheets({
        scenarios: [scenario()],
        catalogs: [dailyCatalog(), { enabled: false }],
      }),
    );

    expect(result.errors).toEqual([]);
    expect(result.data.dailyCatalog).toHaveLength(1);
    expect(result.data.dailyCatalog[0]?.scenarioId).toBe('daily_test');
  });

  it('validates asset catalog references, types, duplicates, and checkbox-only rows', () => {
    const valid = process(
      sheets({
        scenarios: [
          scenario({
            scenario_id: 'small_test',
            scenario_type: 'small_event',
            background: 'bg_test',
          }),
        ],
        assets: [
          assetCatalog({ asset_id: 'bg_test', asset_type: 'background' }),
          { enabled: false },
        ],
      }),
    );
    expect(valid.errors).toEqual([]);
    expect(valid.data.assetCatalog).toHaveLength(1);

    const invalid = process(
      sheets({
        scenarios: [
          scenario({
            scenario_id: 'small_test',
            scenario_type: 'small_event',
            background: 'missing_bg',
            asset_id: 'wrong_type',
            message_type: 'image',
          }),
        ],
        assets: [
          assetCatalog({ asset_id: 'wrong_type', asset_type: 'voice' }),
          assetCatalog({ asset_id: 'wrong_type', asset_type: 'image', display_name: 'Duplicate' }),
        ],
      }),
    );
    expect(invalid.errors.map((issue) => issue.code)).toEqual(
      expect.arrayContaining(['duplicate_asset_id', 'dangling_asset_id', 'asset_type_mismatch']),
    );
  });

  it.each(['command_args', 'asset_id'] as const)(
    'requires a play_se %s reference to use a se asset',
    (column) => {
      const reference =
        column === 'command_args'
          ? { command_args: '{"asset_id":"se_test","volume":0.8}' }
          : { asset_id: 'se_test' };
      const rawScenario = scenario({
        scenario_id: 'small_test',
        scenario_type: 'small_event',
        message_type: 'action',
        ui_variant: 'scene_transition',
        command: 'play_se',
        ...reference,
      });
      const valid = process(
        sheets({
          scenarios: [rawScenario],
          assets: [assetCatalog({ asset_id: 'se_test', asset_type: 'se' })],
        }),
      );
      const invalid = process(
        sheets({
          scenarios: [rawScenario],
          assets: [assetCatalog({ asset_id: 'se_test', asset_type: 'bgm' })],
        }),
      );

      expect(valid.errors).toEqual([]);
      expect(generate(valid.data).scenarios[0]?.nodes[0]).toMatchObject({ command: 'play_se' });
      expect(invalid.errors).toEqual([
        expect.objectContaining({
          code: 'asset_type_mismatch',
          at: expect.objectContaining({ column }),
        }),
      ]);
    },
  );

  it('rejects play_se without an asset reference', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            scenario_id: 'small_test',
            scenario_type: 'small_event',
            message_type: 'action',
            command: 'play_se',
          }),
        ],
      }),
    );

    expect(result.errors).toEqual([expect.objectContaining({ code: 'missing_command_asset_id' })]);
  });

  it('requires a one-to-one relationship between daily and daily_catalog', () => {
    const missingCatalog = process(sheets({ scenarios: [scenario()], catalogs: [] }));
    const missingDaily = process(
      sheets({
        scenarios: [scenario()],
        catalogs: [dailyCatalog(), dailyCatalog({ scenario_id: 'daily_orphan' })],
      }),
    );
    const duplicateCatalog = process(
      sheets({
        scenarios: [scenario()],
        catalogs: [dailyCatalog(), dailyCatalog({ title: 'Duplicate' })],
      }),
    );

    expect(missingCatalog.errors.map((issue) => issue.code)).toContain('missing_daily_catalog');
    expect(missingDaily.errors.map((issue) => issue.code)).toContain('dangling_daily_catalog_id');
    expect(duplicateCatalog.errors.map((issue) => issue.code)).toContain(
      'duplicate_daily_catalog_id',
    );
  });

  it('requires unique positive display_order for enabled unscheduled daily entries', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({ scenario_id: 'daily_missing', node_id: 'missing' }),
          scenario({ scenario_id: 'daily_invalid', node_id: 'invalid' }),
          scenario({ scenario_id: 'daily_duplicate', node_id: 'duplicate' }),
        ],
        catalogs: [
          dailyCatalog({ scenario_id: 'daily_missing', display_order: '' }),
          dailyCatalog({ scenario_id: 'daily_invalid', display_order: 0 }),
          dailyCatalog({ scenario_id: 'daily_duplicate', display_order: 0 }),
        ],
      }),
    );

    expect(result.errors.map((issue) => issue.code)).toEqual(
      expect.arrayContaining([
        'missing_daily_display_order',
        'invalid_display_order',
        'duplicate_daily_display_order',
      ]),
    );
  });

  it('filters a disabled daily scenario and all of its choices from generated content', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({ scenario_id: 'daily_enabled', node_id: 'enabled' }),
          scenario({
            scenario_id: 'daily_disabled',
            node_id: 'disabled',
            message_type: 'choice',
            choice_id: 'disabled_choice',
          }),
        ],
        catalogs: [
          dailyCatalog({ scenario_id: 'daily_enabled' }),
          dailyCatalog({
            scenario_id: 'daily_disabled',
            display_order: '',
            enabled: false,
          }),
        ],
        choices: [
          choice({
            daily_id: 'daily_disabled',
            choice_id: 'disabled_choice',
          }),
        ],
      }),
    );
    const generated = generate(result.data);

    expect(result.errors).toEqual([]);
    expect(generated.scenarios.map((item) => item.scenarioId)).toContain('daily_enabled');
    expect(generated.scenarios.map((item) => item.scenarioId)).not.toContain('daily_disabled');
    expect(generated.choiceGroups).toEqual([]);
  });

  it('rejects a typing duration outside the supported range', () => {
    const result = process(sheets({ scenarios: [scenario({ typing_duration_ms: 30_001 })] }));

    expect(result.errors.map((issue) => issue.code)).toContain('invalid_typing_duration');
  });

  it('reports a non-object command_args value without discarding the parsed JSON', () => {
    const normalized = normalize(
      sheets({ scenarios: [scenario({ command: 'wait', command_args: '[1,{"future":true}]' })] }),
    );

    expect(normalized.issues.errors.map((issue) => issue.code)).toContain(
      'command_args_not_object',
    );
    expect(normalized.data.daily[0]?.commandArgs).toEqual([1, { future: true }]);
  });

  it('normalizes active weighted interaction comments', () => {
    const result = process(
      sheets({
        interactions: [
          interaction({
            id: 'tap_morning',
            condition: 'always',
            time_condition: 'morning',
            touch_area: 'character',
            weight: 3,
          }),
        ],
      }),
    );

    expect(result.errors).toEqual([]);
    expect(generate(result.data).interactions).toEqual([
      {
        id: 'tap_morning',
        text: 'test comment',
        condition: 'always',
        timeCondition: 'morning',
        touchArea: 'character',
        weight: 3,
        active: true,
      },
    ]);
  });
});

describe('event condition grouping', () => {
  it('accepts prologue metadata with episode_order zero', () => {
    const result = process(
      sheets({
        scenarios: [scenario({ scenario_id: 'prologue_001', scenario_type: 'prologue' })],
        events: [
          event({
            event_id: 'event_prologue_001',
            event_type: 'prologue',
            title: 'プロローグ',
            entry_scenario_id: 'prologue_001',
            episode_order: 0,
          }),
        ],
      }),
    );
    const generated = generate(result.data).events[0]!;

    expect(result.errors).toEqual([]);
    expect(
      result.warnings.filter(
        (issue) =>
          issue.code === 'unknown_value' &&
          (issue.at?.column === 'scenario_type' || issue.at?.column === 'event_type'),
      ),
    ).toEqual([]);
    expect(generated).toMatchObject({
      eventId: 'event_prologue_001',
      eventType: 'prologue',
      entryScenarioId: 'prologue_001',
      episodeOrder: 0,
    });
  });

  it('rejects a negative episode_order', () => {
    const result = process(
      sheets({
        scenarios: [scenario({ scenario_id: 'small_test', scenario_type: 'small_event' })],
        events: [event({ episode_order: -1 })],
      }),
    );

    expect(result.errors).toContainEqual(
      expect.objectContaining({
        code: 'invalid_episode_order',
        value: '-1',
      }),
    );
  });

  it('groups same-event condition rows as a deterministic AND array', () => {
    const raw = sheets({
      scenarios: [scenario({ scenario_id: 'small_test', scenario_type: 'small_event' })],
      events: [
        event({
          condition_type: 'streak',
          condition_key: 'continuous_days',
          operator: 'gte',
          threshold: 3,
          chapter_id: 'chapter_02',
          episode_order: 4,
          story_category: 'main',
        }),
        event({
          condition_type: 'relationship',
          condition_key: 'trust',
          operator: 'gte',
          threshold: 10,
          chapter_id: 'chapter_02',
          episode_order: 4,
          story_category: 'main',
        }),
      ],
    });
    const result = process(raw);
    const generated = generate(result.data);

    expect(result.errors).toEqual([]);
    expect(generated.events).toHaveLength(1);
    expect(generated.events[0]).toMatchObject({
      eventId: 'event_test',
      chapterId: 'chapter_02',
      episodeOrder: 4,
      storyCategory: 'main',
      conditions: [
        {
          conditionType: 'relationship',
          conditionKey: 'trust',
          operator: 'gte',
          threshold: '10',
        },
        {
          conditionType: 'streak',
          conditionKey: 'continuous_days',
          operator: 'gte',
          threshold: '3',
        },
      ],
    });
  });

  it('preserves unknown event category/operator as warnings', () => {
    const result = process(
      sheets({
        scenarios: [scenario({ scenario_id: 'small_test', scenario_type: 'small_event' })],
        events: [event({ operator: 'approximately', story_category: 'seasonal' })],
      }),
    );
    const generated = generate(result.data).events[0]!;

    expect(result.errors).toEqual([]);
    expect(result.warnings.filter((issue) => issue.code === 'unknown_value')).toHaveLength(2);
    expect(generated.storyCategory).toBe('seasonal');
    expect(generated.conditions[0]?.operator).toBe('approximately');
  });

  it('rejects metadata differences between rows sharing an event_id', () => {
    const result = process(
      sheets({
        scenarios: [scenario({ scenario_id: 'small_test', scenario_type: 'small_event' })],
        events: [event(), event({ title: 'Different title', condition_key: 'trust' })],
      }),
    );
    expect(result.errors.map((issue) => issue.code)).toContain('event_metadata_mismatch');
  });
});

describe('transition graph', () => {
  it('allows the same node_id in different scenarios', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({ scenario_id: 'daily_a', node_id: 'shared' }),
          scenario({ scenario_id: 'daily_b', node_id: 'shared' }),
        ],
      }),
    );

    expect(result.errors.filter((issue) => issue.code === 'duplicate_node_id')).toEqual([]);
  });

  it('uses choice.next before node.next and node.next before line-order fallback', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            line_order: 1,
            node_id: 'start',
            message_type: 'choice',
            choice_id: 'route',
            next_node_id: 'node_fallback',
          }),
          scenario({ line_order: 2, node_id: 'choice_target' }),
          scenario({ line_order: 3, node_id: 'node_fallback' }),
        ],
        choices: [
          choice({ choice_id: 'route', choice_order: 1, next_node_id: 'choice_target' }),
          choice({ choice_id: 'route', choice_order: 2, label: 'fallback' }),
        ],
      }),
    );

    expect(result.errors).toEqual([]);
  });

  it('marks a line-order node skipped by explicit next_node_id as unreachable', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({ line_order: 1, node_id: 'start', next_node_id: 'end' }),
          scenario({ line_order: 2, node_id: 'skipped' }),
          scenario({ line_order: 3, node_id: 'end' }),
        ],
      }),
    );

    expect(result.errors.map((issue) => issue.code)).toContain('unreachable_node');
  });

  it('allows a reachable cycle when one choice exits it', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            line_order: 1,
            node_id: 'loop',
            message_type: 'choice',
            choice_id: 'loop_or_exit',
          }),
          scenario({ line_order: 2, node_id: 'end' }),
        ],
        choices: [
          choice({ choice_id: 'loop_or_exit', choice_order: 1, next_node_id: 'loop' }),
          choice({ choice_id: 'loop_or_exit', choice_order: 2, next_node_id: 'end' }),
        ],
      }),
    );

    expect(result.errors.filter((issue) => issue.code === 'infinite_loop')).toEqual([]);
  });

  it('uses the same recoverable warning policy for every dangling choice target', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            line_order: 1,
            node_id: 'start',
            message_type: 'choice',
            choice_id: 'future_route',
          }),
          scenario({ line_order: 2, node_id: 'line_order_fallback' }),
        ],
        choices: [choice({ choice_id: 'future_route', next_node_id: 'missing_future_target' })],
      }),
    );

    expect(result.errors).toEqual([]);
    expect(result.warnings.map((issue) => issue.code)).toEqual(
      expect.arrayContaining(['dangling_choice_next', 'unverifiable_after_dangling_choice']),
    );
  });

  it('still rejects a non-terminating path reached through dangling-choice recovery', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            line_order: 1,
            node_id: 'start',
            message_type: 'choice',
            choice_id: 'broken_route',
          }),
          scenario({
            line_order: 2,
            node_id: 'loop',
            message_type: 'action',
            next_node_id: 'loop',
          }),
        ],
        choices: [choice({ choice_id: 'broken_route', next_node_id: 'missing_target' })],
      }),
    );

    expect(result.errors.map((issue) => issue.code)).toContain('infinite_loop');
  });

  it('matches player recovery by ignoring node.next after a selected choice target is missing', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            line_order: 1,
            node_id: 'start',
            message_type: 'choice',
            choice_id: 'broken_route',
            next_node_id: 'end',
          }),
          scenario({
            line_order: 2,
            node_id: 'line_order_loop',
            message_type: 'action',
            next_node_id: 'line_order_loop',
          }),
          scenario({ line_order: 3, node_id: 'end' }),
        ],
        choices: [choice({ choice_id: 'broken_route', next_node_id: 'missing_target' })],
      }),
    );

    expect(result.errors.map((issue) => issue.code)).toContain('infinite_loop');
  });

  it('does not let one dangling choice mask an unrelated unreachable island', () => {
    const result = process(
      sheets({
        scenarios: [
          scenario({
            line_order: 1,
            node_id: 'start',
            message_type: 'choice',
            choice_id: 'broken_route',
          }),
          scenario({ line_order: 2, node_id: 'fallback_arm', next_node_id: 'merge' }),
          scenario({ line_order: 3, node_id: 'possible_missing_arm', next_node_id: 'merge' }),
          scenario({ line_order: 4, node_id: 'merge' }),
          scenario({ line_order: 5, node_id: 'after_merge', next_node_id: 'end' }),
          scenario({ line_order: 6, node_id: 'unrelated_island' }),
          scenario({ line_order: 7, node_id: 'end' }),
        ],
        choices: [choice({ choice_id: 'broken_route', next_node_id: 'missing_target' })],
      }),
    );

    expect(
      result.warnings.some(
        (issue) =>
          issue.code === 'unverifiable_after_dangling_choice' &&
          issue.message.includes('possible_missing_arm'),
      ),
    ).toBe(true);
    expect(
      result.errors.some(
        (issue) => issue.code === 'unreachable_node' && issue.message.includes('unrelated_island'),
      ),
    ).toBe(true);
  });
});

describe('destructive sync guards', () => {
  it('compiles a complete seven-tab source with one authored catalog row', () => {
    const result = runPipeline(
      sheets({
        scenarios: [
          scenario(),
          scenario({ scenario_id: 'small_test', scenario_type: 'small_event' }),
        ],
        choices: [choice()],
        interactions: [interaction()],
        events: [event()],
        assets: [assetCatalog()],
      }),
    );

    expect(result.issues.errors).toEqual([]);
    expect(
      result.artifact?.scenarios.find((item) => item.scenarioId === 'daily_test'),
    ).toMatchObject({
      title: 'Test daily',
      displayOrder: 1,
      status: '公開可能',
      enabled: true,
    });
  });

  it('refuses to generate when source tabs contain no rows', () => {
    const result = runPipeline(sheets({}));

    expect(result.artifact).toBeNull();
    expect(result.plans).toEqual([]);
    expect(result.issues.errors.filter((issue) => issue.code === 'empty_source_tab')).toHaveLength(
      7,
    );
  });

  it('does not count checkbox-only FALSE catalog rows as source content', () => {
    const raw = sheets({
      scenarios: [scenario()],
      catalogs: [{ enabled: false }],
      assets: [assetCatalog()],
    });
    const result = runPipeline(raw);

    expect(
      result.issues.errors.some(
        (issue) => issue.code === 'empty_source_tab' && issue.at?.sheet === 'daily_catalog',
      ),
    ).toBe(true);
    expect(
      result.issues.errors.some(
        (issue) => issue.code === 'no_enabled_rows' && issue.at?.sheet === 'daily_catalog',
      ),
    ).toBe(false);
  });

  it('refuses to generate when every row in a source tab is disabled', () => {
    const result = runPipeline(
      sheets({
        scenarios: [
          scenario({ enabled: false }),
          scenario({ scenario_id: 'small_test', scenario_type: 'small_event', enabled: false }),
        ],
        choices: [choice({ enabled: false })],
        interactions: [interaction({ active: false })],
        events: [event({ enabled: false })],
        assets: [assetCatalog()],
      }),
    );

    expect(result.artifact).toBeNull();
    expect(result.plans).toEqual([]);
    expect(result.issues.errors.filter((issue) => issue.code === 'no_enabled_rows')).toHaveLength(
      5,
    );
  });
});

describe('deterministic generation and CLI contracts', () => {
  it('generates identical JSON after row order is reversed', () => {
    const normalized = normalize(
      sheets({
        scenarios: [
          scenario({ scenario_id: 'daily_b', node_id: 'b' }),
          scenario({ scenario_id: 'daily_a', node_id: 'a' }),
        ],
      }),
    ).data;
    const reversed = {
      daily: [...normalized.daily].reverse(),
      dailyCatalog: [...normalized.dailyCatalog].reverse(),
      assetCatalog: [...normalized.assetCatalog].reverse(),
      scenarios: [...normalized.scenarios].reverse(),
      choices: [...normalized.choices].reverse(),
      interactions: [...normalized.interactions].reverse(),
      events: [...normalized.events].reverse(),
    };

    expect(serialize(generate(normalized))).toBe(serialize(generate(reversed)));
  });

  it('defaults to a non-destructive live plan and requires an explicit snapshot flag', () => {
    expect(parseArgs([])).toMatchObject({ mode: 'plan', snapshotPath: undefined });
    expect(parseArgs(['--check'])).toMatchObject({ mode: 'check', snapshotPath: undefined });
    expect(parseArgs(['--snapshot', '--check'])).toMatchObject({
      mode: 'check',
      snapshotPath: expect.stringContaining('fixtures/sheets-snapshot.json'),
    });
    expect(() => parseArgs(['--snapshot', '--write'])).toThrow(/live source/);
    expect(() => parseArgs(['--snapshot', '--save-snapshot'])).toThrow(/live source/);
  });
});
