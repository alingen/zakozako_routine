import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { REPO_ROOT } from '../src/config.js';
import { loadSnapshot, snapshotToRawSheets } from '../src/fetch.js';
import { generate } from '../src/generate.js';
import { normalize } from '../src/normalize.js';
import { validate } from '../src/validate.js';
import { sheets } from './helpers.js';

const line = {
  line_id: 'welcome',
  group_id: 'onboarding',
  text: '今日は{routine_title}[br]A[sp]B',
  weight: 1,
  active: true,
  note: '案内',
};

describe('rio_lines CMS', () => {
  it('preserves templates and excludes disabled copy', () => {
    const result = normalize(sheets({ rioLines: [line, { line_id: 'off', active: false }] }));
    expect(result.issues.errors).toEqual([]);
    expect(generate(result.data).rioLines).toEqual([
      {
        lineId: 'welcome',
        groupId: 'onboarding',
        text: line.text,
        weight: 1,
        active: true,
        note: '案内',
      },
    ]);
  });

  it('rejects duplicate IDs, invalid weights, unknown placeholders and challenge categories', () => {
    const result = normalize(
      sheets({
        rioLines: [
          line,
          line,
          {
            ...line,
            line_id: 'bad',
            weight: -1,
            group_id: 'challenge_unknown',
            text: '{unsupported}',
          },
        ],
      }),
    );
    const codes = validate(result.data).issues.errors.map((error) => error.code);
    expect(codes).toEqual(
      expect.arrayContaining([
        'duplicate_rio_line',
        'invalid_rio_weight',
        'invalid_rio_placeholder',
        'invalid_challenge_group',
      ]),
    );
  });

  it('refuses a missing live header rather than erasing the fixed copy', () => {
    const snapshot = loadSnapshot();
    snapshot.tabs.rio_lines = [];
    expect(() => snapshotToRawSheets(snapshot)).toThrow('rio_lines header');
  });

  it('provides every fixed line referenced by the app and all migrated challenges', () => {
    const result = normalize(snapshotToRawSheets(loadSnapshot()));
    expect(result.issues.errors).toEqual([]);
    const lines = generate(result.data).rioLines;
    expect(lines).toHaveLength(74);
    const ids = new Set(lines.map((row) => row.lineId));
    function sources(dir: string): string[] {
      return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const path = join(dir, entry.name);
        return entry.isDirectory()
          ? sources(path)
          : entry.name.endsWith('.swift')
            ? [readFileSync(path, 'utf8')]
            : [];
      });
    }
    const referenced = sources(join(REPO_ROOT, 'MesugakiRoutine')).flatMap((text) =>
      [...text.matchAll(/RioCopy\.text\("([^"]+)"/g)].map((match) => match[1]!),
    );
    expect(referenced.length).toBeGreaterThan(20);
    for (const id of referenced) expect(ids.has(id), id).toBe(true);
    expect(
      lines.filter(
        (row) => row.groupId.startsWith('challenge_') && row.groupId !== 'challenge_intro',
      ),
    ).toHaveLength(39);
  });
});
