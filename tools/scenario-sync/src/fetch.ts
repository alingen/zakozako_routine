import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { RawRow, RawSheets, SheetSnapshot } from './types.js';
import type { SyncConfig } from './config.js';
import { SNAPSHOT_PATH } from './config.js';

function headerRowIndex(grid: string[][], firstColumnName: string): number {
  const index = grid.findIndex((row) => row.some((cell) => cell.trim() === firstColumnName));
  return index >= 0 ? index : 0;
}

/** Convert a tab grid to keyed rows while preserving Google Sheets row numbers. */
export function gridToRows(grid: string[][], firstColumnName: string): RawRow[] {
  if (grid.length === 0) return [];

  const headerIndex = headerRowIndex(grid, firstColumnName);
  const header = (grid[headerIndex] ?? []).map((cell) => cell.trim());
  const rows: RawRow[] = [];

  for (let index = headerIndex + 1; index < grid.length; index += 1) {
    const cells = grid[index] ?? [];
    if (cells.every((cell) => cell.trim() === '')) continue;

    const row: RawRow = { __row: index + 1 };
    header.forEach((column, columnIndex) => {
      if (column) row[column] = cells[columnIndex] ?? '';
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
    throw new Error(`Snapshot not found: ${path}. Fetch live or pass a valid snapshot path.`);
  }
  const parsed = JSON.parse(readFileSync(path, 'utf8')) as Partial<SheetSnapshot>;
  if (!parsed.sheetId || !parsed.tabs?.scenarios || !parsed.tabs.choices || !parsed.tabs.events) {
    throw new Error(`Invalid scenario snapshot: ${path}`);
  }
  return {
    fetchedAt: parsed.fetchedAt ?? new Date(0).toISOString(),
    sheetId: parsed.sheetId,
    source: 'snapshot',
    tabs: parsed.tabs,
  };
}

export function saveSnapshot(snapshot: SheetSnapshot, path = SNAPSHOT_PATH): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(snapshot, null, 2)}\n`, 'utf8');
}

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
  const response = await sheets.spreadsheets.values.batchGet({
    spreadsheetId: config.sheetId,
    ranges: [config.tabs.scenarios, config.tabs.choices, config.tabs.events],
    majorDimension: 'ROWS',
  });
  const ranges = response.data.valueRanges ?? [];
  const grid = (index: number): string[][] =>
    trimGrid((ranges[index]?.values ?? []).map((row) => (row ?? []).map(cellToString)));

  return {
    fetchedAt: new Date().toISOString(),
    sheetId: config.sheetId,
    source: 'api',
    tabs: { scenarios: grid(0), choices: grid(1), events: grid(2) },
  };
}

async function fetchViaPublicXlsx(config: SyncConfig): Promise<SheetSnapshot> {
  const url = `https://docs.google.com/spreadsheets/d/${config.sheetId}/export?format=xlsx`;
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok) {
    throw new Error(`Public XLSX fetch failed (HTTP ${response.status}).`);
  }
  if ((response.headers.get('content-type') ?? '').includes('text/html')) {
    throw new Error('Google returned HTML instead of XLSX; configure readonly credentials.');
  }

  const ExcelJS = (await import('exceljs')).default;
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(Buffer.from(await response.arrayBuffer()) as unknown as ArrayBuffer);

  const readTab = (name: string): string[][] => {
    const worksheet = workbook.getWorksheet(name);
    if (!worksheet) throw new Error(`Sheet tab not found: ${name}`);

    const grid: string[][] = [];
    worksheet.eachRow({ includeEmpty: true }, (row) => {
      const values = Array.isArray(row.values) ? row.values.slice(1) : [];
      grid.push(values.map(cellToString));
    });
    return trimGrid(grid);
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

/** Live fetch only. Snapshot fallback is deliberately owned by an explicit CLI flag. */
export async function fetchFromSheets(config: SyncConfig): Promise<SheetSnapshot> {
  if (!config.sheetId.trim()) throw new Error('SCENARIO_SHEET_ID is empty.');
  return config.credentials.kind === 'none' ? fetchViaPublicXlsx(config) : fetchViaApi(config);
}

function trimGrid(grid: string[][]): string[][] {
  const rows = grid.map(trimTrailingEmptyCells);
  let end = rows.length;
  while (end > 0 && (rows[end - 1] ?? []).every((cell) => cell.trim() === '')) end -= 1;
  return rows.slice(0, end);
}

function trimTrailingEmptyCells(row: string[]): string[] {
  let end = row.length;
  while (end > 0 && (row[end - 1] ?? '').trim() === '') end -= 1;
  return row.slice(0, end);
}

function cellToString(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value !== 'object') return String(value);

  const object = value as Record<string, unknown>;
  if (typeof object.text === 'string') return object.text;
  if (typeof object.result === 'string' || typeof object.result === 'number') {
    return String(object.result);
  }
  if (Array.isArray(object.richText)) {
    return (object.richText as Array<{ text?: string }>).map((part) => part.text ?? '').join('');
  }
  return String(value);
}
