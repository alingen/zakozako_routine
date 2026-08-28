import { describe, it, expect } from 'vitest';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';
import { generate } from '../src/generate.js';
import { sheets } from './helpers.js';

/** A minimal valid daily scenario + one small event. */
function happyPath() {
  return sheets({
    scenarios: [
      ['daily_001', 'daily', '1', 'n1', 'character', 'text', 'おはよう'],
      ['daily_001', 'daily', '2', 'n2', 'character', 'choice', '兄弟いる?', 'c_sib'],
      ['daily_001', 'daily', '3', 'n_yes', 'character', 'text', 'いるんだ', '', 'n_end'],
      ['daily_001', 'daily', '4', 'n_no', 'character', 'text', '一人っ子か', '', 'n_end'],
      ['daily_001', 'daily', '5', 'n_end', 'character', 'text', 'じゃあね'],
      ['ev_scn', 'small_event', '1', 'e1', 'character', 'text', 'ひみつだよ'],
      ['ev_scn', 'small_event', '2', 'e2', 'character', 'text', 'わすれて'],
    ],
    choices: [
      ['c_sib', '1', 'いる', 'n_yes', 'hasSiblings', 'yes'],
      ['c_sib', '2', 'いない', 'n_no', 'hasSiblings', 'no'],
    ],
    events: [
      ['ev1', 'small_event', 'ひみつ', 'ev_scn', '10', 'FALSE', '0', 'metric', 'trust', 'gte', '3'],
    ],
  });
}

function run(raw: ReturnType<typeof sheets>) {
  const { data, issues: n } = normalize(raw);
  const { issues: v } = validate(data);
  return {
    data,
    errors: [...n.errors, ...v.errors],
    warnings: [...n.warnings, ...v.warnings],
  };
}

describe('happy path', () => {
  it('validates with no errors', () => {
    const { errors } = run(happyPath());
    expect(errors).toEqual([]);
  });

  it('generates the expected app shapes', () => {
    const { data } = run(happyPath());
    const out = generate(data);
    expect(out.daily.scenarios).toHaveLength(1);
    const day = out.daily.scenarios[0]!;
    expect(day.dayIndex).toBe(1);
    expect(day.messages.map((m) => m.id)).toEqual(['n1', 'n2', 'n_yes', 'n_no', 'n_end']);
    const choiceNode = day.messages.find((m) => m.id === 'n2')!;
    expect(choiceNode.choices).toEqual([
      {
        text: 'いる',
        next: 'n_yes',
        saveFact: { key: 'hasSiblings', value: 'yes' },
      },
      {
        text: 'いない',
        next: 'n_no',
        saveFact: { key: 'hasSiblings', value: 'no' },
      },
    ]);
    expect(out.events.events).toHaveLength(1);
    expect(out.events.events[0]!.eventType).toBe('small');
    expect(out.events.events[0]!.unlockConditions).toEqual({ minTrust: 3 });
  });
});

describe('duplicate ids', () => {
  it('flags a duplicated node_id across scenarios', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'dup', 'character', 'text', 'x'],
        ['b', 'daily', '1', 'dup', 'character', 'text', 'y'],
      ],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('duplicate_node_id');
  });

  it('flags a duplicated line_order in one scenario', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'text', 'x'],
        ['a', 'daily', '1', 'n2', 'character', 'text', 'y'],
      ],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('duplicate_line_order');
  });

  it('flags a duplicated choice_order in one choice group', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'choice', 'q', 'c1'],
        ['a', 'daily', '2', 'n2', 'character', 'text', 'end'],
      ],
      choices: [
        ['c1', '1', 'A', 'n2'],
        ['c1', '1', 'B', 'n2'],
      ],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('duplicate_choice_order');
  });
});

describe('reference integrity', () => {
  it('flags a choice pointing at a missing node', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'choice', 'q', 'c1'],
        ['a', 'daily', '2', 'n2', 'character', 'text', 'end'],
      ],
      choices: [['c1', '1', 'A', 'ghost']],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('dangling_choice_next');
  });

  it('flags a scenario choice_id with no choices rows', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'choice', 'q', 'c_missing'],
        ['a', 'daily', '2', 'n2', 'character', 'text', 'end'],
      ],
    });
    const { errors } = run(raw);
    const set = new Set(errors.map((e) => e.code));
    expect(set.has('dangling_choice_id') || set.has('choice_node_no_options')).toBe(true);
  });

  it('flags a missing entry_scenario_id and a type mismatch', () => {
    const raw = sheets({
      scenarios: [['scn', 'daily', '1', 'n1', 'character', 'text', 'x']],
      events: [
        ['e1', 'small_event', 'T', 'ghost_scn', '1', 'FALSE', '0', 'metric', 'trust', 'gte', '1'],
        ['e2', 'small_event', 'T2', 'scn', '2', 'FALSE', '0', 'metric', 'trust', 'gte', '1'],
      ],
    });
    const { errors } = run(raw);
    const set = errors.map((e) => e.code);
    expect(set).toContain('dangling_entry_scenario');
    expect(set).toContain('event_scenario_type_mismatch');
  });
});

describe('enums and types', () => {
  it('rejects an unknown scenario_type', () => {
    const raw = sheets({
      scenarios: [['a', 'weekly', '1', 'n1', 'character', 'text', 'x']],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('bad_enum');
  });

  it('rejects a non-integer line_order', () => {
    const raw = sheets({
      scenarios: [['a', 'daily', 'one', 'n1', 'character', 'text', 'x']],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('bad_number');
  });

  it('rejects an unsupported metric operator', () => {
    const raw = sheets({
      scenarios: [['scn', 'small_event', '1', 'n1', 'character', 'text', 'x']],
      events: [['e', 'small_event', 'T', 'scn', '1', 'FALSE', '0', 'metric', 'trust', 'lt', '5']],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('unsupported_metric_operator');
  });
});

describe('AND conditions', () => {
  it('merges multiple rows of one event into a single condition set', () => {
    const raw = sheets({
      scenarios: [['scn', 'large_event', '1', 'n1', 'character', 'text', 'x']],
      events: [
        ['e', 'large_event', 'T', 'scn', '1', 'FALSE', '0', 'metric', 'trust', 'gte', '10'],
        ['e', 'large_event', 'T', 'scn', '1', 'FALSE', '0', 'metric', 'streak_days', 'gte', '7'],
        [
          'e',
          'large_event',
          'T',
          'scn',
          '1',
          'FALSE',
          '0',
          'event',
          'event_completed',
          'exists',
          'e_prev',
        ],
      ],
    });
    const { data, errors } = run(raw);
    expect(errors).toEqual([]);
    const out = generate(data);
    expect(out.events.events[0]!.unlockConditions).toEqual({
      minTrust: 10,
      minStreakDays: 7,
      requiredCompletedEventIds: ['e_prev'],
    });
  });

  it('treats gt as threshold + 1', () => {
    const raw = sheets({
      scenarios: [['scn', 'small_event', '1', 'n1', 'character', 'text', 'x']],
      events: [['e', 'small_event', 'T', 'scn', '1', 'FALSE', '0', 'metric', 'trust', 'gt', '2']],
    });
    const { data } = run(raw);
    expect(generate(data).events.events[0]!.unlockConditions.minTrust).toBe(3);
  });
});

describe('disabled rows', () => {
  it('excludes enabled=FALSE rows from output and reference checks', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'text', 'keep'],
        [
          'a',
          'daily',
          '2',
          'n2',
          'character',
          'text',
          'drop',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          'FALSE',
        ],
      ],
    });
    const { data, errors } = run(raw);
    expect(errors).toEqual([]);
    const out = generate(data);
    expect(out.daily.scenarios[0]!.messages.map((m) => m.id)).toEqual(['n1']);
  });

  it('drops a disabled choice option', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'choice', 'q', 'c1'],
        ['a', 'daily', '2', 'n2', 'character', 'text', 'end'],
      ],
      choices: [
        ['c1', '1', 'keep', 'n2'],
        ['c1', '2', 'drop', 'n2', '', '', '', '', '', 'FALSE'],
      ],
    });
    const { data } = run(raw);
    const out = generate(data);
    const node = out.daily.scenarios[0]!.messages.find((m) => m.id === 'n1')!;
    expect(node.choices?.map((c) => c.text)).toEqual(['keep']);
  });
});

describe('stable output', () => {
  it('produces identical JSON regardless of input row order', () => {
    const rowsA: string[][] = [
      ['d_b', 'daily', '1', 'b1', 'character', 'text', 'B'],
      ['d_a', 'daily', '1', 'a1', 'character', 'text', 'A'],
    ];
    const rowsB = [...rowsA].reverse();
    const outA = generate(normalize(sheets({ scenarios: rowsA })).data);
    const outB = generate(normalize(sheets({ scenarios: rowsB })).data);
    expect(JSON.stringify(outA)).toBe(JSON.stringify(outB));
    // sorted by scenario_id -> d_a is Day 1
    expect(outA.daily.scenarios.map((s) => s.scenarioId)).toEqual(['d_a', 'd_b']);
  });

  it('sorts events by priority then id', () => {
    const raw = sheets({
      scenarios: [
        ['s1', 'small_event', '1', 'n1', 'character', 'text', 'x'],
        ['s2', 'small_event', '1', 'n2', 'character', 'text', 'y'],
      ],
      events: [
        ['z_evt', 'small_event', 'Z', 's1', '5', 'FALSE', '0', 'metric', 'trust', 'gte', '1'],
        ['a_evt', 'small_event', 'A', 's2', '5', 'FALSE', '0', 'metric', 'trust', 'gte', '1'],
        ['mid', 'small_event', 'M', 's1', '1', 'FALSE', '0', 'metric', 'trust', 'gte', '1'],
      ],
    });
    const out = generate(normalize(raw).data);
    expect(out.events.events.map((e) => e.eventId)).toEqual(['mid', 'a_evt', 'z_evt']);
  });
});

describe('infinite loop detection', () => {
  it('flags a scenario with no reachable ending', () => {
    const raw = sheets({
      scenarios: [
        ['a', 'daily', '1', 'n1', 'character', 'text', 'x', '', 'n2'],
        ['a', 'daily', '2', 'n2', 'character', 'text', 'y', '', 'n1'],
      ],
    });
    const { errors } = run(raw);
    expect(errors.map((e) => e.code)).toContain('infinite_loop');
  });
});
