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

  it('accepts the user name placeholder', () => {
    const result = normalize(
      sheets({ rioLines: [{ ...line, text: 'お、ざこの{user_name}おにいさん発見〜' }] }),
    );
    const codes = validate(result.data).issues.errors.map((error) => error.code);
    expect(codes).not.toContain('invalid_rio_placeholder');
  });

  it('refuses a missing live header rather than erasing the fixed copy', () => {
    const snapshot = loadSnapshot();
    snapshot.tabs.rio_lines = [];
    expect(() => snapshotToRawSheets(snapshot)).toThrow('rio_lines header');
  });

  it('provides every fixed line referenced by the app and all migrated challenges', () => {
    const result = normalize(snapshotToRawSheets(loadSnapshot()));
    expect(result.issues.errors).toEqual([]);
    const generated = generate(result.data);
    const lines = generated.rioLines;
    expect(lines).toHaveLength(59);
    const bundled = JSON.parse(
      readFileSync(
        join(
          REPO_ROOT,
          'MesugakiRoutine/Resources/GeneratedScenarios/story_content.generated.json',
        ),
        'utf8',
      ),
    );
    expect(bundled.rioLines).toEqual(lines);
    expect(bundled.reactionLines).toEqual(generated.reactionLines);
    expect(bundled.reactionConditions).toEqual(generated.reactionConditions);
    expect(lines.some((row) => /^(home_|blocked_)/.test(row.groupId))).toBe(false);
    expect(
      generated.reactionLines.filter((row) => row.displayTarget === 'home_routine_added'),
    ).toHaveLength(3);
    const compactPeekLines = generated.reactionLines.filter(
      (row) => row.displayTarget === 'home_peek_unfinished_top',
    );
    expect(compactPeekLines).toHaveLength(3);
    for (const row of compactPeekLines) {
      expect([...row.text].length).toBeLessThanOrEqual(10);
      expect(row.text).not.toContain('{routine_title}');
    }
    const ids = new Set(lines.map((row) => row.lineId));
    // reaction_lines へ移した旧行(「移管済み:」の無効行)はシートから片付けた。rio_lines に残さない。
    const moved = loadSnapshot()
      .tabs.rio_lines.slice(3)
      .filter((row) => row[5]?.startsWith('移管済み:'));
    expect(moved).toHaveLength(0);
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
    const groups = new Set(lines.map((row) => row.groupId));
    const referencedGroups = sources(join(REPO_ROOT, 'MesugakiRoutine')).flatMap((text) =>
      [...text.matchAll(/RioCopy\.(?:random|lines)\(group:\s*"([^"]+)"/g)].map(
        (match) => match[1]!,
      ),
    );
    for (const group of referencedGroups) expect(groups.has(group), group).toBe(true);
    expect(lines.some((row) => row.note?.includes('Sheets未登録'))).toBe(false);
    expect(
      lines.filter(
        (row) => row.groupId.startsWith('challenge_') && row.groupId !== 'challenge_intro',
      ),
    ).toHaveLength(39);
  });
});
