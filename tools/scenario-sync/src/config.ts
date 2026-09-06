import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));

export const TOOL_ROOT = resolve(HERE, '..');
export const REPO_ROOT = resolve(TOOL_ROOT, '..', '..');

/** Google Sheets is the sole source of truth; this identifier is public metadata. */
export const DEFAULT_SHEET_ID = '1Ifkw0X4TIOxe0f9EpZpZEGIexLg-xoXG8c-ro4I5MBM';

/** The only app-facing artifact. It must always be produced by scenario-sync. */
export const OUTPUT_PATH = resolve(
  REPO_ROOT,
  'MesugakiRoutine/Resources/GeneratedScenarios/story_content.generated.json',
);

/** Raw, committed sheet snapshot used only when the CLI is explicitly passed --snapshot. */
export const SNAPSHOT_PATH = resolve(TOOL_ROOT, 'fixtures/sheets-snapshot.json');

export interface SyncConfig {
  sheetId: string;
  tabs: {
    scenarios: string;
    choices: string;
    events: string;
  };
  credentials: { kind: 'inline'; json: string } | { kind: 'file'; path: string } | { kind: 'none' };
}

/** Minimal dotenv reader. Existing process values always win. */
function loadDotEnv(): void {
  const path = resolve(TOOL_ROOT, '.env');
  if (!existsSync(path)) return;

  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const separator = trimmed.indexOf('=');
    if (separator < 0) continue;

    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

export function loadConfig(): SyncConfig {
  loadDotEnv();

  const inline = process.env.SCENARIO_GOOGLE_SA_JSON?.trim();
  const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  const credentials: SyncConfig['credentials'] = inline
    ? { kind: 'inline', json: inline }
    : credentialPath
      ? { kind: 'file', path: resolve(TOOL_ROOT, credentialPath) }
      : { kind: 'none' };

  return {
    sheetId: process.env.SCENARIO_SHEET_ID?.trim() || DEFAULT_SHEET_ID,
    tabs: {
      scenarios: process.env.SCENARIO_TAB_SCENARIOS?.trim() || 'scenarios',
      choices: process.env.SCENARIO_TAB_CHOICES?.trim() || 'choices',
      events: process.env.SCENARIO_TAB_EVENTS?.trim() || 'events',
    },
    credentials,
  };
}
