import { createInterface } from 'node:readline/promises';
import { execFileSync } from 'node:child_process';
import { stdin, stdout, argv, exit } from 'node:process';
import { existsSync } from 'node:fs';
import { loadConfig, TOOL_ROOT, DAILY_OUTPUT, EVENTS_OUTPUT, SNAPSHOT_PATH } from './config.js';
import {
  fetchFromSheets,
  loadSnapshot,
  saveSnapshot,
  snapshotToRawSheets,
  type SheetSnapshot,
} from './fetch.js';
import { runPipeline } from './pipeline.js';
import { commitWrites } from './generate.js';
import { formatIssue } from './issues.js';
import { renderDiff } from './diff.js';

interface Flags {
  check: boolean;
  write: boolean;
  snapshot: boolean;
  noTests: boolean;
  help: boolean;
}

function parseFlags(args: string[]): Flags {
  return {
    check: args.includes('--check'),
    write: args.includes('--write'),
    snapshot: args.includes('--snapshot'),
    noTests: args.includes('--no-tests'),
    help: args.includes('--help') || args.includes('-h'),
  };
}

const HELP = `
scenario-sync — Google Sheets → 正規化JSON

使い方:
  npm run sync            取得→検証→差分表示→確認後に書き込み
  npm run sync -- --write  確認をスキップして書き込み
  npm run sync:check      CI用。差分か検証エラーがあれば非ゼロ終了(書き込みなし)

オプション:
  --check       検証と差分チェックのみ。書き込みしない。ずれていれば exit 1
  --write       差分の確認プロンプトを出さずに書き込む
  --snapshot    ライブ取得せず fixtures/sheets-snapshot.json を使う
  --no-tests    書き込み後の型チェック/テストをスキップ
  -h, --help    このヘルプ

環境変数は .env.example を参照。
`;

async function acquireSnapshot(flags: Flags): Promise<{ snapshot: SheetSnapshot; live: boolean }> {
  const config = loadConfig();
  // Live fetch works with a sheet id alone: service-account API when credentials
  // are set, otherwise the public XLSX export for link-shared sheets.
  const canFetch = !!config.sheetId;

  if (!flags.snapshot && canFetch) {
    const how = config.credentials.kind !== 'none' ? 'Google Sheets API' : '公開XLSXエクスポート';
    console.log(`▶ ${how} で取得中…`);
    try {
      const snapshot = await fetchFromSheets(config);
      console.log(`  取得元: ${snapshot.source}`);
      return { snapshot, live: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (!existsSync(SNAPSHOT_PATH)) {
        console.error(`✖ 取得に失敗: ${message}`);
        exit(2);
      }
      console.warn(`⚠ 取得に失敗 (${message})\n  スナップショットにフォールバックします。`);
      return { snapshot: loadSnapshot(), live: false };
    }
  }

  if (!existsSync(SNAPSHOT_PATH)) {
    console.error(
      '✖ SCENARIO_SHEET_ID が未設定で、スナップショットもありません。\n' +
        '  .env を設定してオンライン取得するか、一度 `npm run sync` を実行してください。',
    );
    exit(2);
  }
  console.log(
    flags.snapshot
      ? '▶ スナップショット (fixtures/sheets-snapshot.json) を使用'
      : '▶ SCENARIO_SHEET_ID 未設定のためスナップショットを使用',
  );
  return { snapshot: loadSnapshot(), live: false };
}

function printIssues(bag: ReturnType<typeof runPipeline>['issues']): void {
  if (bag.warnings.length) {
    console.log(`\n⚠ 警告 (${bag.warnings.length}):`);
    for (const w of bag.warnings) console.log('  ' + formatIssue(w));
  }
  if (bag.errors.length) {
    console.log(`\n✖ エラー (${bag.errors.length}):`);
    for (const e of bag.errors) console.log('  ' + formatIssue(e));
  }
}

async function confirm(question: string): Promise<boolean> {
  const rl = createInterface({ input: stdin, output: stdout });
  try {
    const answer = (await rl.question(`${question} [y/N] `)).trim().toLowerCase();
    return answer === 'y' || answer === 'yes';
  } finally {
    rl.close();
  }
}

function runPostChecks(): void {
  console.log('\n▶ 型チェック (tsc --noEmit) …');
  execFileSync('npx', ['tsc', '--noEmit'], {
    cwd: TOOL_ROOT,
    stdio: 'inherit',
  });
  console.log('▶ フォーマット確認 (prettier) …');
  execFileSync('npx', ['prettier', '--check', `${DAILY_OUTPUT}`, `${EVENTS_OUTPUT}`], {
    cwd: TOOL_ROOT,
    stdio: 'inherit',
  });
  console.log('▶ テスト (vitest) …');
  execFileSync('npx', ['vitest', 'run'], { cwd: TOOL_ROOT, stdio: 'inherit' });
}

async function main(): Promise<void> {
  const flags = parseFlags(argv.slice(2));
  if (flags.help) {
    console.log(HELP);
    return;
  }

  const { snapshot, live } = await acquireSnapshot(flags);
  const raw = snapshotToRawSheets(snapshot);

  console.log('▶ 正規化 → 検証 …');
  const result = runPipeline(raw);
  printIssues(result.issues);

  if (result.issues.hasErrors || !result.artifacts) {
    console.error('\n✖ 検証エラーがあるため中止しました。生成物は変更していません。');
    exit(1);
  }

  const changed = result.plans.filter((p) => p.changed);

  console.log('\n' + renderDiff(result.diff!));

  console.log('\n▶ 変更予定ファイル:');
  if (changed.length === 0) {
    console.log('  (なし)');
  } else {
    for (const p of changed) {
      const status = p.previous === null ? '新規' : '更新';
      console.log(`  ${status}: ${p.path}`);
    }
  }

  // --- CI mode -------------------------------------------------------------
  if (flags.check) {
    if (changed.length > 0) {
      console.error(
        `\n✖ 生成物が ${live ? 'Google Sheets' : 'スナップショット'} と一致していません。` +
          `\n  \`npm run sync -- --write\` を実行してコミットしてください。`,
      );
      exit(1);
    }
    console.log('\n✓ 生成物は最新です。');
    return;
  }

  // --- write ------------------------------------------------------------
  if (changed.length === 0) {
    console.log('\n✓ 変更なし。何も書き込みませんでした。');
    if (live) saveSnapshot(snapshot);
    return;
  }

  if (!flags.write) {
    const ok = await confirm('\nこの内容で生成物を書き換えますか？');
    if (!ok) {
      console.log('中止しました。');
      exit(1);
    }
  }

  commitWrites(result.plans);
  if (live) saveSnapshot(snapshot);
  console.log(`\n✓ ${changed.length} 件のファイルを書き込みました。`);

  if (!flags.noTests) {
    runPostChecks();
  }

  console.log(
    '\n次の手順: iOS ビルド/型チェック（xcodegen generate && xcodebuild ... build）→ 動作確認 → コミット',
  );
}

main().catch((err) => {
  console.error('\n✖ 予期しないエラー:', err instanceof Error ? err.message : err);
  exit(2);
});
