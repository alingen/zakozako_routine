import { describe, expect, it } from 'vitest';
import { generate } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';
import { scenario, sheets } from './helpers.js';

describe('fullscreen chat narration', () => {
  it.each([
    { message_type: 'action' },
    { text: '' },
    { screen_mode: 'adv' },
    { choice_id: 'unexpected' },
  ])('rejects unsupported fullscreen narration settings: %o', (override) => {
    const { data } = normalize(
      sheets({
        scenarios: [
          scenario({
            scenario_type: 'middle_event',
            speaker: 'narrator',
            screen_mode: 'chat',
            ui_variant: 'fullscreen_narration',
            ...override,
          }),
        ],
      }),
    );
    expect(validate(data).issues.errors.map((issue) => issue.code)).toContain(
      'invalid_fullscreen_narration',
    );
  });

  it('exports consecutive narration pages without changing ordinary narration', () => {
    const { data, issues } = normalize(
      sheets({
        scenarios: [
          scenario({
            scenario_type: 'middle_event',
            node_id: 'first',
            line_order: 1,
            speaker: 'narrator',
            screen_mode: 'chat',
            ui_variant: 'fullscreen_narration',
            text: 'それが。',
          }),
          scenario({
            scenario_type: 'middle_event',
            node_id: 'last',
            line_order: 2,
            speaker: 'narrator',
            screen_mode: 'chat',
            ui_variant: 'fullscreen_narration',
            text: '莉央との[br]最初の約束だった。',
          }),
          scenario({
            scenario_type: 'middle_event',
            node_id: 'ordinary',
            line_order: 3,
            speaker: 'narrator',
            screen_mode: 'chat',
            ui_variant: 'narration',
            text: '数分後',
          }),
        ],
      }),
    );
    expect(issues.errors).toEqual([]);
    const result = validate(data);
    expect(result.issues.errors).toEqual([]);
    expect(result.issues.warnings.filter((issue) => issue.at?.column === 'ui_variant')).toEqual([]);
    const nodes = generate(data).scenarios[0]!.nodes;
    expect(nodes.map((node) => node.uiVariant)).toEqual([
      'fullscreen_narration',
      'fullscreen_narration',
      'narration',
    ]);
    expect(nodes[1]!.text).toBe('莉央との[br]最初の約束だった。');
    expect(nodes[0]!.screenMode).toBe('chat');
  });
});
