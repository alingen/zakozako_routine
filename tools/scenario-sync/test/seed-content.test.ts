import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { snapshotToRawSheets } from '../src/fetch.js';
import { runPipeline } from '../src/pipeline.js';
import { TOOL_ROOT } from '../src/config.js';

/**
 * `fixtures/full-content.snapshot.json` is the STEP 2-7 conversation data laid
 * out in the spreadsheet's row model. It is what `scripts/seed-content.ts`
 * exports to `template/scenario-data.xlsx` for import into Google Sheets.
 * These assertions guard that the seed data stays valid and complete.
 */
describe('seed content (full-content.snapshot.json)', () => {
  const snap = JSON.parse(
    readFileSync(resolve(TOOL_ROOT, 'fixtures/full-content.snapshot.json'), 'utf8'),
  );
  const result = runPipeline(snapshotToRawSheets(snap));

  it('validates with no errors and no warnings', () => {
    expect(result.issues.errors.map((e) => e.code)).toEqual([]);
    expect(result.issues.warnings.map((w) => w.code)).toEqual([]);
  });

  it('has 3 daily conversations and 4 events (3 small + 1 large)', () => {
    expect(result.artifacts!.daily.scenarios.map((s) => s.scenarioId)).toEqual([
      'daily_001',
      'daily_002',
      'daily_003',
    ]);
    const events = result.artifacts!.events.events;
    expect(events.map((e) => e.eventId)).toEqual([
      'event_small_001',
      'event_small_002',
      'event_small_003',
      'event_large_001',
    ]);
    expect(events.filter((e) => e.eventType === 'big')).toHaveLength(1);
  });

  it('keeps the rich features: minPhase, image, cg, AND conditions, phase advance', () => {
    const day3 = result.artifacts!.daily.scenarios.find((s) => s.scenarioId === 'daily_003')!;
    expect(day3.messages.some((m) => m.minPhase === 1)).toBe(true);

    const dance = result.artifacts!.events.events.find((e) => e.eventId === 'event_small_002')!;
    expect(
      dance.messages.some((m) => m.type === 'image' && m.imageName === 'event_rio_dance'),
    ).toBe(true);

    const night = result.artifacts!.events.events.find((e) => e.eventId === 'event_large_001')!;
    expect(night.background).toBe('bg_rio_room');
    expect(night.advancesToPhase).toBe(1);
    expect(night.unlockConditions).toEqual({
      minTrust: 5,
      minStreakDays: 3,
      requiredCompletedEventIds: ['event_small_001'],
    });
    expect(night.messages.some((m) => m.cg === 'cg_rio_smile')).toBe(true);
  });
});
