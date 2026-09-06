import { resolve } from 'node:path';
import { argv } from 'node:process';
import { loadConfig, OUTPUT_PATH, SNAPSHOT_PATH } from './config.js';
import { fetchFromSheets, loadSnapshot, saveSnapshot, snapshotToRawSheets } from './fetch.js';
import { commitWrites } from './generate.js';
import { formatIssue } from './issues.js';
import { runPipeline } from './pipeline.js';
import type { SheetSnapshot } from './types.js';

export interface CliOptions {
  mode: 'plan' | 'check' | 'write';
  snapshotPath?: string;
  saveSnapshotPath?: string;
  help: boolean;
}

const HELP = `scenario-sync — Google Sheets story CMS validator/generator

Usage:
  npm run sync
  npm run sync:check
  npm run sync:write
  npm run sync -- --snapshot [path] [--check]
  npm run sync -- --save-snapshot [path] [--write]

Modes:
  (default)       Fetch live, validate, and show the generated-file plan. No writes.
  --check         Exit nonzero on validation errors or generated-file drift. No writes.
  --write         Fetch live and atomically update the generated JSON.

Source options:
  --snapshot [path]       Explicitly use a snapshot instead of the network.
                          Default: ${SNAPSHOT_PATH}
  --save-snapshot [path]  Save a successful live read for offline checks.
                          Default: ${SNAPSHOT_PATH}
  -h, --help              Show this help.

There is no automatic snapshot fallback when a live fetch fails.
Generated output: ${OUTPUT_PATH}
`;

export function parseArgs(args: string[]): CliOptions {
  let mode: CliOptions['mode'] = 'plan';
  let snapshotPath: string | undefined;
  let saveSnapshotPath: string | undefined;
  let help = false;

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index]!;
    if (argument === '--help' || argument === '-h') {
      help = true;
      continue;
    }
    if (argument === '--check' || argument === '--write') {
      const requested = argument === '--check' ? 'check' : 'write';
      if (mode !== 'plan' && mode !== requested) {
        throw new Error('--check and --write cannot be used together.');
      }
      mode = requested;
      continue;
    }
    if (argument === '--snapshot' || argument.startsWith('--snapshot=')) {
      if (snapshotPath !== undefined) throw new Error('--snapshot may only be specified once.');
      const inline = argument.startsWith('--snapshot=') ? argument.slice('--snapshot='.length) : '';
      const following = inline || optionalPath(args[index + 1]);
      if (!inline && following) index += 1;
      snapshotPath = resolve(following || SNAPSHOT_PATH);
      continue;
    }
    if (argument === '--save-snapshot' || argument.startsWith('--save-snapshot=')) {
      if (saveSnapshotPath !== undefined) {
        throw new Error('--save-snapshot may only be specified once.');
      }
      const inline = argument.startsWith('--save-snapshot=')
        ? argument.slice('--save-snapshot='.length)
        : '';
      const following = inline || optionalPath(args[index + 1]);
      if (!inline && following) index += 1;
      saveSnapshotPath = resolve(following || SNAPSHOT_PATH);
      continue;
    }
    throw new Error(`Unknown argument: ${argument}`);
  }

  if (snapshotPath && saveSnapshotPath) {
    throw new Error(
      '--save-snapshot requires a live source and cannot be combined with --snapshot.',
    );
  }
  if (snapshotPath && mode === 'write') {
    throw new Error('--write requires a live source and cannot be combined with --snapshot.');
  }
  return { mode, snapshotPath, saveSnapshotPath, help };
}

function optionalPath(value: string | undefined): string | undefined {
  return value && !value.startsWith('-') ? value : undefined;
}

async function acquire(options: CliOptions): Promise<{ snapshot: SheetSnapshot; live: boolean }> {
  if (options.snapshotPath) {
    return { snapshot: loadSnapshot(options.snapshotPath), live: false };
  }

  const config = loadConfig();
  const method = config.credentials.kind === 'none' ? 'public-xlsx' : 'sheets-api';
  console.log(`Fetching live Google Sheets source (${method})...`);
  return { snapshot: await fetchFromSheets(config), live: true };
}

export async function run(args: string[]): Promise<number> {
  let options: CliOptions;
  try {
    options = parseArgs(args);
  } catch (error) {
    console.error(`Argument error: ${errorMessage(error)}`);
    console.error('Run with --help for usage.');
    return 2;
  }

  if (options.help) {
    console.log(HELP);
    return 0;
  }

  let acquired: { snapshot: SheetSnapshot; live: boolean };
  try {
    acquired = await acquire(options);
  } catch (error) {
    console.error(`Source read failed: ${errorMessage(error)}`);
    console.error('No generated files or snapshots were changed.');
    return 2;
  }

  const raw = snapshotToRawSheets(acquired.snapshot);
  const result = runPipeline(raw);
  printSummary(acquired.snapshot, raw, result);

  if (result.issues.hasErrors || !result.artifact) {
    console.error('Validation failed. No generated files or snapshots were changed.');
    return 1;
  }

  if (options.saveSnapshotPath) {
    if (!acquired.live) {
      console.error('--save-snapshot cannot save a non-live source.');
      return 2;
    }
    saveSnapshot(acquired.snapshot, options.saveSnapshotPath);
    console.log(`Snapshot saved: ${options.saveSnapshotPath}`);
  }

  if (options.mode === 'check') {
    if (result.hasChanges) {
      console.error(
        'Generated content is out of date. Run npm run sync:write and commit the result.',
      );
      return 1;
    }
    console.log('Generated content is up to date.');
    return 0;
  }

  if (options.mode === 'write') {
    commitWrites(result.plans);
    const changedCount = result.plans.filter((plan) => plan.changed).length;
    console.log(
      changedCount === 0
        ? 'Generated content was already up to date; nothing was written.'
        : `Atomically wrote ${changedCount} generated file(s).`,
    );
    return 0;
  }

  console.log('Plan only: no generated files were changed.');
  return 0;
}

function printSummary(
  snapshot: SheetSnapshot,
  raw: ReturnType<typeof snapshotToRawSheets>,
  result: ReturnType<typeof runPipeline>,
): void {
  console.log(
    `Source: ${snapshot.source} (sheet ${snapshot.sheetId}, fetched ${snapshot.fetchedAt})`,
  );
  console.log(
    `Rows: scenarios=${raw.scenarios.length}, choices=${raw.choices.length}, events=${raw.events.length}`,
  );

  if (result.artifact) {
    const dailyCount = result.artifact.scenarios.filter(
      (scenario) => scenario.scenarioType === 'daily',
    ).length;
    const nodeCount = result.artifact.scenarios.reduce(
      (total, scenario) => total + scenario.nodes.length,
      0,
    );
    console.log(
      `Bundle: scenarios=${result.artifact.scenarios.length} (daily=${dailyCount}), ` +
        `nodes=${nodeCount}, choiceGroups=${result.artifact.choiceGroups.length}, ` +
        `events=${result.artifact.events.length}`,
    );
  }

  console.log(
    `Diagnostics: errors=${result.issues.errors.length}, warnings=${result.issues.warnings.length}`,
  );
  for (const issue of result.issues.errors) console.error(`ERROR ${formatIssue(issue)}`);
  for (const issue of result.issues.warnings) console.warn(`WARN  ${formatIssue(issue)}`);

  console.log('Generated-file plan:');
  if (result.plans.length === 0) {
    console.log('  unavailable because validation did not succeed');
    return;
  }
  for (const plan of result.plans) {
    const state = !plan.changed ? 'unchanged' : plan.previous === null ? 'create' : 'update';
    console.log(`  ${state}: ${plan.path} (${Buffer.byteLength(plan.next, 'utf8')} bytes)`);
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

if (import.meta.url === new URL(argv[1] ?? '', 'file:').href) {
  run(argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error: unknown) => {
      console.error(`Unexpected failure: ${errorMessage(error)}`);
      process.exitCode = 2;
    });
}
