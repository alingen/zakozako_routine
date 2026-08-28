import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const TOOL_ROOT = resolve(HERE, '..');
export const REPO_ROOT = resolve(TOOL_ROOT, '..', '..');

/** Where the app reads generated scenario data from (bundled by xcodegen). */
export const OUTPUT_DIR = resolve(REPO_ROOT, 'MesugakiRoutine/Resources/GeneratedScenarios');
export const DAILY_OUTPUT = resolve(OUTPUT_DIR, 'daily_conversations.generated.json');
export const EVENTS_OUTPUT = resolve(OUTPUT_DIR, 'events.generated.json');

/** Committed snapshot of the sheet data, used for offline `--check` and tests. */
export const SNAPSHOT_PATH = resolve(TOOL_ROOT, 'fixtures/sheets-snapshot.json');

export interface SyncConfig {
  sheetId: string;
  tabs: { scenarios: string; choices: string; events: string };
  credentials: { kind: 'inline'; json: string } | { kind: 'file'; path: string } | { kind: 'none' };
}

/** Minimal `.env` reader (no dependency). Only KEY=VALUE lines, `#` comments. */
function loadDotEnv(): void {
  const envPath = resolve(TOOL_ROOT, '.env');
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

/**
 * The project's scenario spreadsheet. Not a secret (it is in the shareable URL);
 * kept here so the tool works with no `.env`. Override via `SCENARIO_SHEET_ID`.
 */
export const DEFAULT_SHEET_ID = '1Ifkw0X4TIOxe0f9EpZpZEGIexLg-xoXG8c-ro4I5MBM';

export function loadConfig(): SyncConfig {
  loadDotEnv();

  const sheetId = process.env.SCENARIO_SHEET_ID?.trim() || DEFAULT_SHEET_ID;

  const tabs = {
    scenarios: process.env.SCENARIO_TAB_SCENARIOS?.trim() || 'scenarios',
    choices: process.env.SCENARIO_TAB_CHOICES?.trim() || 'choices',
    events: process.env.SCENARIO_TAB_EVENTS?.trim() || 'events',
  };

  let credentials: SyncConfig['credentials'] = { kind: 'none' };
  const inline = process.env.SCENARIO_GOOGLE_SA_JSON?.trim();
  const file = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  if (inline) {
    credentials = { kind: 'inline', json: inline };
  } else if (file) {
    credentials = { kind: 'file', path: resolve(TOOL_ROOT, file) };
  }

  return { sheetId, tabs, credentials };
}
