import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import type { RawRow, RawSheets } from './types.js';
import { type SyncConfig, SNAPSHOT_PATH } from './config.js';

/**
 * A snapshot mirrors the raw grid of each tab (a `string[][]` including any
 * title rows above the real header). It lets `--check` and CI run without any
 * Sheets access, and is what the test suite exercises.
 */
export interface SheetSnapshot {
  fetchedAt: string;
  sheetId: string;
  /** How the grid was obtained, for the CLI to report. */
  source?: 'api' | 'public-xlsx' | 'snapshot';
  tabs: {
    scenarios: string[][];
    choices: string[][];
    events: string[][];
  };
}

/** The real header row often sits below one or more title rows. Find it by its
 *  first-column name; fall back to the first row if not found. */
function headerRowIndex(grid: string[][], firstColumnName: string): number {
  const idx = grid.findIndex((row) =>
    row.some((cell) => String(cell ?? '').trim() === firstColumnName),
  );
  return idx >= 0 ? idx : 0;
}

/**
 * Turn a raw grid into keyed RawRow objects. `firstColumnName` locates the
 * header row (skipping title/description rows above it). `__row` is the real
 * 1-based sheet row number, so error messages point at the right line.
 */
export function gridToRows(grid: string[][], firstColumnName: string): RawRow[] {
  if (grid.length === 0) return [];
  const headerIdx = headerRowIndex(grid, firstColumnName);
  const header = (grid[headerIdx] ?? []).map((h) => String(h ?? '').trim());

  const rows: RawRow[] = [];
  for (let i = headerIdx + 1; i < grid.length; i++) {
    const cells = grid[i] ?? [];
    if (cells.every((c) => String(c ?? '').trim() === '')) continue;
    const row: RawRow = { __row: i + 1 };
    header.forEach((col, idx) => {
      if (!col) return;
      row[col] = cells[idx] ?? '';
    });
    rows.push(row);
  }
  return rows;
}

export function snapshotToRawSheets(snapshot: SheetSnapshot): RawSheets {
  return {
    scenarios: gridToRows(snapshot.tabs.scenarios, 'scenario_id'),
    choices: gridToRows(snapshot.tabs.choices, 'choice_id'),
    events: gridToRows(snapshot.tabs.events, 'event_id'),
  };
}

export function loadSnapshot(path = SNAPSHOT_PATH): SheetSnapshot {
  if (!existsSync(path)) {
    throw new Error(
      `スナップショットがありません: ${path}\n` +
        `オンライン取得を実行するか、先に \`npm run sync\` でスナップショットを作成してください。`,
    );
  }
  return JSON.parse(readFileSync(path, 'utf8')) as SheetSnapshot;
}

export function saveSnapshot(snapshot: SheetSnapshot, path = SNAPSHOT_PATH): void {
  writeFileSync(path, JSON.stringify(snapshot, null, 2) + '\n', 'utf8');
}

// ---------------------------------------------------------------------------
// Live fetch strategies
// ---------------------------------------------------------------------------

/**
 * Fetch via the Google Sheets API v4 (service-account credentials).
 * `googleapis` is dynamically imported so offline paths never load it.
 */
async function fetchViaApi(config: SyncConfig): Promise<SheetSnapshot> {
  const { google } = await import('googleapis');
  const { GoogleAuth } = await import('google-auth-library');

  const authOptions: Record<string, unknown> = {
    scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'],
  };
  if (config.credentials.kind === 'inline') {
    authOptions.credentials = JSON.parse(config.credentials.json);
  } else if (config.credentials.kind === 'file') {
    authOptions.keyFile = config.credentials.path;
  }
  const auth = new GoogleAuth(authOptions);
  const sheets = google.sheets({ version: 'v4', auth: (await auth.getClient()) as never });

  const ranges = [config.tabs.scenarios, config.tabs.choices, config.tabs.events];
  const res = await sheets.spreadsheets.values.batchGet({
    spreadsheetId: config.sheetId,
    ranges,
    majorDimension: 'ROWS',
  });
  const valueRanges = res.data.valueRanges ?? [];
  const grid = (idx: number): string[][] =>
    trimTrailingEmptyRows(
      (valueRanges[idx]?.values ?? []).map((r) => (r ?? []).map((c) => String(c ?? ''))),
    );

  return {
    fetchedAt: new Date().toISOString(),
    sheetId: config.sheetId,
    source: 'api',
    tabs: { scenarios: grid(0), choices: grid(1), events: grid(2) },
  };
}

/**
 * Fetch a link-shared ("anyone with the link can view") spreadsheet with no
 * credentials, by downloading the whole workbook as XLSX from the public
 * export endpoint and reading each tab with `exceljs`. Cell values are taken
 * verbatim as strings; title/merged rows above the header are handled by
 * `gridToRows`.
 */
async function fetchViaPublicXlsx(config: SyncConfig): Promise<SheetSnapshot> {
  const url = `https://docs.google.com/spreadsheets/d/${config.sheetId}/export?format=xlsx`;
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) {
    throw new Error(
      `公開XLSXの取得に失敗 (HTTP ${res.status})。スプレッドシートが「リンクを知っている全員が閲覧可」か確認してください。`,
    );
  }
  const contentType = res.headers.get('content-type') ?? '';
  if (contentType.includes('text/html')) {
    throw new Error(
      'ログイン画面が返されました。スプレッドシートを「リンクを知っている全員が閲覧可」にするか、サービスアカウント認証を設定してください。',
    );
  }
  const buf = Buffer.from(await res.arrayBuffer());

  const ExcelJS = (await import('exceljs')).default;
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf as unknown as ArrayBuffer);

  const readTab = (name: string): string[][] => {
    const ws = wb.getWorksheet(name);
    if (!ws) throw new Error(`シート "${name}" が見つかりません。タブ名を確認してください。`);
    const grid: string[][] = [];
    ws.eachRow({ includeEmpty: true }, (row) => {
      const values = Array.isArray(row.values) ? row.values.slice(1) : [];
      grid.push(values.map((v) => cellToString(v)));
    });
    return trimTrailingEmptyRows(grid);
  };

  return {
    fetchedAt: new Date().toISOString(),
    sheetId: config.sheetId,
    source: 'public-xlsx',
    tabs: {
      scenarios: readTab(config.tabs.scenarios),
      choices: readTab(config.tabs.choices),
      events: readTab(config.tabs.events),
    },
  };
}

/** Drop trailing rows that are entirely empty (sheets pad to ~1000 rows). */
function trimTrailingEmptyRows(grid: string[][]): string[][] {
  let end = grid.length;
  while (end > 0 && (grid[end - 1] ?? []).every((c) => String(c ?? '').trim() === '')) {
    end--;
  }
  return grid.slice(0, end);
}

function cellToString(v: unknown): string {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') {
    // exceljs rich text / hyperlink / formula result
    const obj = v as Record<string, unknown>;
    if (typeof obj.text === 'string') return obj.text;
    if (typeof obj.result === 'string' || typeof obj.result === 'number') return String(obj.result);
    if (Array.isArray(obj.richText)) {
      return (obj.richText as Array<{ text?: string }>).map((r) => r.text ?? '').join('');
    }
    if (obj.hyperlink && typeof obj.text === 'string') return obj.text as string;
  }
  return String(v);
}

/**
 * Pick a live-fetch strategy: Sheets API when credentials are configured,
 * otherwise the public XLSX export (link-shared sheets).
 */
export async function fetchFromSheets(config: SyncConfig): Promise<SheetSnapshot> {
  if (!config.sheetId) {
    throw new Error('SCENARIO_SHEET_ID が未設定です (.env を確認してください)。');
  }
  if (config.credentials.kind !== 'none') {
    return fetchViaApi(config);
  }
  return fetchViaPublicXlsx(config);
}
