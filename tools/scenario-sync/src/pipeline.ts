import { OUTPUT_PATH } from './config.js';
import { generate, planWrite, serialize, type WritePlan } from './generate.js';
import { IssueBag } from './issues.js';
import { normalize } from './normalize.js';
import type { RawSheets, StoryContentBundle } from './types.js';
import { validate } from './validate.js';

export interface PipelineResult {
  issues: IssueBag;
  artifact: StoryContentBundle | null;
  plans: WritePlan[];
  hasChanges: boolean;
}

/**
 * Pure pipeline core apart from reading the existing generated artifact for
 * comparison. Fetching live data or loading an explicit snapshot is the
 * caller's responsibility; this layer never performs fallback I/O.
 */
export function runPipeline(raw: RawSheets, outputPath = OUTPUT_PATH): PipelineResult {
  const issues = new IssueBag();
  const normalized = normalize(raw);
  issues.merge(normalized.issues);

  // A transient fetch/header failure must never look like a legitimate CMS
  // deletion and overwrite the bundled catalog with an empty artifact.
  const identityColumn = {
    daily: 'scenario_id',
    dailyCatalog: 'scenario_id',
    assetCatalog: 'asset_id',
    interactions: 'id',
    scenarios: 'scenario_id',
    choices: 'choice_id',
    events: 'event_id',
  } as const;
  for (const tab of [
    'daily',
    'dailyCatalog',
    'assetCatalog',
    'choices',
    'interactions',
    'scenarios',
    'events',
  ] as const) {
    const sheetName =
      tab === 'scenarios'
        ? 'senarios'
        : tab === 'dailyCatalog'
          ? 'daily_catalog'
          : tab === 'assetCatalog'
            ? 'asset_catalog'
            : tab;
    const sourceRowCount =
      tab === 'dailyCatalog'
        ? normalized.data.dailyCatalog.length
        : tab === 'assetCatalog'
          ? normalized.data.assetCatalog.length
          : raw[tab].length;
    const enabledRowCount =
      tab === 'dailyCatalog'
        ? normalized.data.dailyCatalog.filter((row) => row.enabled).length
        : tab === 'assetCatalog'
          ? normalized.data.assetCatalog.filter((row) => row.enabled).length
          : normalized.data[tab].length;
    if (sourceRowCount === 0) {
      issues.error('empty_source_tab', `${tab} has no source rows; refusing to generate`, {
        at: { sheet: sheetName, row: 1, column: identityColumn[tab] },
      });
    } else if (enabledRowCount === 0) {
      issues.error('no_enabled_rows', `${tab} has no valid enabled rows; refusing to generate`, {
        at: { sheet: sheetName, row: 1, column: tab === 'interactions' ? 'active' : 'enabled' },
      });
    }
  }

  const validated = validate(normalized.data);
  issues.merge(validated.issues);

  if (issues.hasErrors) {
    return { issues, artifact: null, plans: [], hasChanges: false };
  }

  const artifact = generate(normalized.data);
  const plans = [planWrite(outputPath, serialize(artifact))];
  return {
    issues,
    artifact,
    plans,
    hasChanges: plans.some((plan) => plan.changed),
  };
}
