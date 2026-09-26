import { describe, expect, it } from 'vitest';
import { loadSnapshot, snapshotToRawSheets } from '../src/fetch.js';
import { generate } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';
import { sheets } from './helpers.js';

const condition = {
  condition_id: 'streak_7',
  label: '7日',
  trigger_type: 'state',
  condition_key: 'currentStreak',
  operator: '==',
  value: '7',
  priority: 80,
  active: true,
};
const line = {
  line_id: 'seven',
  condition_id: 'streak_7',
  text: 'A[br]B',
  strength: 'strong',
  premium_only: true,
  weight: 3,
  active: true,
};

describe('production reactions CMS', () => {
  it('keeps strong/premium metadata and text markers; ignores inactive rows', () => {
    const result = normalize(
      sheets({
        reactionConditions: [condition, { condition_id: 'not_ready', active: false }],
        reactionLines: [line, { line_id: 'not_ready', active: false }],
      }),
    );
    expect(result.issues.errors).toEqual([]);
    const bundle = generate(result.data);
    expect(bundle.reactionConditions).toHaveLength(1);
    expect(bundle.reactionLines).toEqual([
      {
        lineId: 'seven',
        conditionId: 'streak_7',
        text: 'A[br]B',
        strength: 'strong',
        premiumOnly: true,
        weight: 3,
        active: true,
      },
    ]);
  });

  it('rejects duplicate IDs, dangling active lines and invalid weights', () => {
    const result = normalize(
      sheets({
        reactionConditions: [condition, condition],
        reactionLines: [
          line,
          line,
          { ...line, line_id: 'bad', condition_id: 'absent', weight: -1 },
        ],
      }),
    );
    const errors = validate(result.data).issues.errors.map((e) => e.code);
    expect(errors).toContain('duplicate_reaction_condition');
    expect(errors).toContain('duplicate_reaction_line');
    expect(errors).toContain('missing_reaction_condition');
    expect(errors).toContain('invalid_reaction_weight');
  });

  it('defaults a blank weight to one but requires active TRUE', () => {
    const result = normalize(
      sheets({
        reactionConditions: [condition],
        reactionLines: [
          { ...line, weight: '' },
          { ...line, line_id: 'blank', active: '' },
        ],
      }),
    );
    expect(result.data.reactionLines).toHaveLength(1);
    expect(result.data.reactionLines[0]?.weight).toBe(1);
  });

  it('loads only production tabs and links every active line to an active condition', () => {
    const snapshot = loadSnapshot();
    expect(Object.keys(snapshot.tabs)).not.toContain('reaction_lines_draft');
    expect(Object.keys(snapshot.tabs)).not.toContain('reaction_reference');
    const result = normalize(snapshotToRawSheets(snapshot));
    expect(result.issues.errors).toEqual([]);
    expect(validate(result.data).issues.errors).toEqual([]);
    expect(result.data.reactionConditions.filter((c) => c.active)).toHaveLength(52);
    expect(result.data.reactionLines).toHaveLength(288);
    expect(result.data.reactionLines.some((l) => l.strength === 'strong' && l.premiumOnly)).toBe(
      true,
    );
  });

  it('allows disabling a condition without manually disabling all of its lines', () => {
    const result = normalize(
      sheets({ reactionConditions: [{ ...condition, active: false }], reactionLines: [line] }),
    );
    expect(validate(result.data).issues.errors).toEqual([]);
    expect(generate(result.data).reactionConditions).toEqual([]);
    expect(generate(result.data).reactionLines).toEqual([]);
  });

  it('rejects a missing production tab header before generation', () => {
    const snapshot = loadSnapshot();
    snapshot.tabs.reaction_lines = [];
    expect(() => snapshotToRawSheets(snapshot)).toThrow('reaction_lines header');
  });
});
