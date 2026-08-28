import ExcelJS from 'exceljs';
import { resolve } from 'node:path';
import { mkdirSync } from 'node:fs';
import { TOOL_ROOT } from '../src/config.js';
import { snapshotToRawSheets, loadSnapshot } from '../src/fetch.js';
import {
  SCENARIO_COLUMNS,
  CHOICE_COLUMNS,
  EVENT_COLUMNS,
  SCENARIO_TYPES,
  MESSAGE_TYPES,
  SPEAKERS,
  EVENT_TYPES,
  CONDITION_TYPES,
  COMPARE_OPERATORS,
} from '../src/schema.js';

/**
 * Regenerates `template/scenario-template.xlsx` — a workbook with the three
 * sheets, their full column set, data-validation dropdowns for the enum
 * columns, and the current sample rows (from the committed snapshot) as a
 * starting point. Import it into Google Sheets to bootstrap the spreadsheet.
 */

const OUT_DIR = resolve(TOOL_ROOT, 'template');
const OUT_FILE = resolve(OUT_DIR, 'scenario-template.xlsx');

const HEADERS = {
  scenarios: [...SCENARIO_COLUMNS.required, ...SCENARIO_COLUMNS.optional] as string[],
  choices: [...CHOICE_COLUMNS.required, ...CHOICE_COLUMNS.optional] as string[],
  events: [...EVENT_COLUMNS.required, ...EVENT_COLUMNS.optional] as string[],
};

// Put columns in a human-friendly order for the template (spec order first).
const DISPLAY_ORDER = {
  scenarios: [
    'scenario_id',
    'scenario_type',
    'line_order',
    'node_id',
    'speaker',
    'message_type',
    'text',
    'choice_id',
    'next_node_id',
    'save_key',
    'save_value',
    'asset_id',
    'min_phase',
    'max_phase',
    'speaker_name',
    'background',
    'portrait',
    'cg',
    'enabled',
    'notes',
  ],
  choices: [
    'choice_id',
    'choice_order',
    'label',
    'next_node_id',
    'save_key',
    'save_value',
    'required_key',
    'required_operator',
    'required_value',
    'enabled',
    'notes',
  ],
  events: [
    'event_id',
    'event_type',
    'title',
    'entry_scenario_id',
    'priority',
    'repeatable',
    'cooldown_days',
    'condition_type',
    'condition_key',
    'operator',
    'threshold',
    'background',
    'advances_to_phase',
    'enabled',
    'notes',
  ],
};

const ENUM_VALIDATION: Record<string, Record<string, readonly string[]>> = {
  scenarios: {
    scenario_type: SCENARIO_TYPES,
    message_type: MESSAGE_TYPES,
    speaker: SPEAKERS,
    enabled: ['TRUE', 'FALSE'],
  },
  choices: {
    required_operator: ['', ...COMPARE_OPERATORS],
    enabled: ['TRUE', 'FALSE'],
  },
  events: {
    event_type: EVENT_TYPES,
    condition_type: CONDITION_TYPES,
    operator: COMPARE_OPERATORS,
    repeatable: ['TRUE', 'FALSE'],
    enabled: ['TRUE', 'FALSE'],
  },
};

function colLetter(n: number): string {
  let s = '';
  let x = n;
  while (x > 0) {
    const m = (x - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    x = Math.floor((x - 1) / 26);
  }
  return s;
}

function addSheet(wb: ExcelJS.Workbook, name: keyof typeof HEADERS, gridRows: string[][]): void {
  const ws = wb.addWorksheet(name);
  const order = DISPLAY_ORDER[name];
  const snapshotHeader = gridRows[0] ?? [];

  ws.addRow(order);
  ws.getRow(1).font = { bold: true };
  ws.views = [{ state: 'frozen', ySplit: 1 }];

  for (const row of gridRows.slice(1)) {
    const record: Record<string, string> = {};
    snapshotHeader.forEach((h, i) => (record[h] = row[i] ?? ''));
    ws.addRow(order.map((c) => record[c] ?? ''));
  }

  order.forEach((col, i) => {
    ws.getColumn(i + 1).width = Math.max(12, Math.min(40, col.length + 6));
    const allowed = ENUM_VALIDATION[name]?.[col];
    if (allowed) {
      const letter = colLetter(i + 1);
      for (let r = 2; r <= 500; r++) {
        ws.getCell(`${letter}${r}`).dataValidation = {
          type: 'list',
          allowBlank: true,
          formulae: [`"${allowed.join(',')}"`],
        };
      }
    }
  });
}

async function main(): Promise<void> {
  mkdirSync(OUT_DIR, { recursive: true });
  const snapshot = loadSnapshot();
  const raw = snapshotToRawSheets(snapshot);
  void raw;

  const wb = new ExcelJS.Workbook();
  wb.creator = 'scenario-sync';
  wb.created = new Date();

  addSheet(wb, 'scenarios', snapshot.tabs.scenarios);
  addSheet(wb, 'choices', snapshot.tabs.choices);
  addSheet(wb, 'events', snapshot.tabs.events);

  await wb.xlsx.writeFile(OUT_FILE);
  console.log(`✓ ${OUT_FILE}`);
  console.log('  Google Sheets へ「ファイル > インポート」で取り込んでください。');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
