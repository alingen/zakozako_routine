import { describe, expect, it } from 'vitest';
import { parseArgs } from '../src/cli.js';
import { generate, serialize } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { runPipeline } from '../src/pipeline.js';
import { validate } from '../src/validate.js';
import { choice, event, scenario, sheets } from './helpers.js';

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

    expect(raw.scenarios[0]?.__row).toBe(4);
    expect(result.errors).toEqual([]);
    expect(result.data.scenarios[0]?.enabled).toBe(true);
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

  it('reports a non-object command_args value without discarding the parsed JSON', () => {
    const normalized = normalize(
      sheets({ scenarios: [scenario({ command: 'wait', command_args: '[1,{"future":true}]' })] }),
    );

    expect(normalized.issues.errors.map((issue) => issue.code)).toContain(
      'command_args_not_object',
    );
    expect(normalized.data.scenarios[0]?.commandArgs).toEqual([1, { future: true }]);
  });
});

describe('event condition grouping', () => {
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
  it('refuses to generate when source tabs contain no rows', () => {
    const result = runPipeline(sheets({}));

    expect(result.artifact).toBeNull();
    expect(result.plans).toEqual([]);
    expect(result.issues.errors.filter((issue) => issue.code === 'empty_source_tab')).toHaveLength(
      3,
    );
  });

  it('refuses to generate when every row in a source tab is disabled', () => {
    const result = runPipeline(
      sheets({
        scenarios: [scenario({ enabled: false })],
        choices: [choice({ enabled: false })],
        events: [event({ enabled: false })],
      }),
    );

    expect(result.artifact).toBeNull();
    expect(result.plans).toEqual([]);
    expect(result.issues.errors.filter((issue) => issue.code === 'no_enabled_rows')).toHaveLength(
      3,
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
      scenarios: [...normalized.scenarios].reverse(),
      choices: [...normalized.choices].reverse(),
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
