import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'node:fs';
import { loadSnapshot, snapshotToRawSheets } from '../src/fetch.js';
import { runPipeline } from '../src/pipeline.js';
import { serialize } from '../src/generate.js';
import { DAILY_OUTPUT, EVENTS_OUTPUT } from '../src/config.js';

describe('committed snapshot (real spreadsheet)', () => {
  const raw = snapshotToRawSheets(loadSnapshot());
  const result = runPipeline(raw);

  it('skips the sheet title rows and finds the real header', () => {
    // rows 1-2 are title/description; row 3 is the header; first data row is 4.
    expect(raw.scenarios[0]?.__row).toBe(4);
  });

  it('has no validation errors', () => {
    expect(result.issues.errors.map((e) => `${e.code}: ${e.message}`)).toEqual([]);
  });

  it('reproduces the sample daily conversation and small event', () => {
    expect(result.artifacts!.daily.scenarios.map((s) => s.scenarioId)).toEqual(['daily_001']);
    const day1 = result.artifacts!.daily.scenarios[0]!;
    expect(day1.dayIndex).toBe(1);
    expect(day1.messages.map((m) => m.id)).toEqual([
      'daily_001_01',
      'daily_001_02',
      'daily_001_03',
      'daily_001_04',
    ]);
    const choiceNode = day1.messages.find((m) => m.id === 'daily_001_03')!;
    expect(choiceNode.choices?.map((c) => c.text)).toEqual(['いる', 'いない']);
    expect(choiceNode.choices?.[0]?.saveFact).toEqual({ key: 'hasSiblings', value: 'true' });

    expect(result.artifacts!.events.events.map((e) => e.eventId)).toEqual(['event_small_001']);
    expect(result.artifacts!.events.events[0]!.unlockConditions).toEqual({
      minTrust: 10,
      minStreakDays: 7,
    });
  });

  it('matches the committed generated files (drift check)', () => {
    if (!existsSync(DAILY_OUTPUT) || !existsSync(EVENTS_OUTPUT)) {
      throw new Error('生成物が未コミットです。`npm run sync -- --write` を実行してください。');
    }
    expect(serialize(result.artifacts!.daily)).toBe(readFileSync(DAILY_OUTPUT, 'utf8'));
    expect(serialize(result.artifacts!.events)).toBe(readFileSync(EVENTS_OUTPUT, 'utf8'));
  });

  it('is deterministic', () => {
    const again = runPipeline(snapshotToRawSheets(loadSnapshot()));
    expect(serialize(again.artifacts!.daily)).toBe(serialize(result.artifacts!.daily));
    expect(serialize(again.artifacts!.events)).toBe(serialize(result.artifacts!.events));
  });
});
