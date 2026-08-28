/**
 * Builds the full "current" conversation content (daily Day 1-3 + 4 events)
 * as spreadsheet rows, and emits:
 *   - fixtures/full-content.snapshot.json  (round-trip / verification)
 *   - seed/scenario-data.xlsx              (import into Google Sheets)
 *   - seed/{scenarios,choices,events}.tsv  (paste into each tab at A3)
 *
 * This is a one-off seeding helper. Once the spreadsheet holds this data, the
 * spreadsheet is the source of truth and this file is no longer used.
 *
 * Run: npx tsx scripts/seed-content.ts
 */
import ExcelJS from 'exceljs';
import { resolve } from 'node:path';
import { mkdirSync, writeFileSync } from 'node:fs';
import { TOOL_ROOT } from '../src/config.js';
import { snapshotToRawSheets } from '../src/fetch.js';
import { runPipeline } from '../src/pipeline.js';

const SCENARIO_COLS = [
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
];
const CHOICE_COLS = [
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
];
const EVENT_COLS = [
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
];

const TITLE: Record<string, [string, string]> = {
  scenarios: [
    'scenarios — ザコルーティン 会話シナリオCMS',
    'Google Sheetsが正本です。アプリ側の生成JSON / TypeScriptを直接編集しないでください。青い見出しの下へ行を追加します。',
  ],
  choices: [
    'choices — ザコルーティン 会話シナリオCMS',
    'Google Sheetsが正本です。アプリ側の生成JSON / TypeScriptを直接編集しないでください。青い見出しの下へ行を追加します。',
  ],
  events: [
    'events — ザコルーティン 会話シナリオCMS',
    'Google Sheetsが正本です。アプリ側の生成JSON / TypeScriptを直接編集しないでください。青い見出しの下へ行を追加します。',
  ],
};

// --- authoring model -------------------------------------------------------

interface Msg {
  id: string;
  speaker?: 'character' | 'user';
  type?: 'text' | 'choice' | 'image';
  text?: string;
  choiceId?: string;
  next?: string;
  save?: [string, string];
  asset?: string;
  minPhase?: number;
  portrait?: string;
  cg?: string;
  notes?: string;
}
interface Scenario {
  id: string;
  type: 'daily' | 'small_event' | 'large_event';
  messages: Msg[];
}
interface Choice {
  id: string;
  options: {
    label: string;
    next: string;
    save?: [string, string];
    require?: [string, string, string];
  }[];
}
interface EventDef {
  id: string;
  type: 'small_event' | 'large_event';
  title: string;
  scenario: string;
  priority: number;
  background?: string;
  advancesToPhase?: number;
  conditions: { type: string; key: string; op: string; value: string }[];
}

const scenarios: Scenario[] = [
  {
    id: 'daily_001',
    type: 'daily',
    messages: [
      { id: 'daily_001_01', text: 'お、ルーティンちゃんと終わらせたんだ。ざこのわりにやるじゃん♡' },
      { id: 'daily_001_02', text: 'べつに褒めてないけどね。あたりまえのことしただけだし' },
      {
        id: 'daily_001_03',
        text: 'わたしは今日、学校のあとダンスの練習してきたの。ちょっと疲れちゃった〜',
      },
      { id: 'daily_001_04', text: '……なんであんたに報告してるんだろ。まあいいや' },
      { id: 'daily_001_05', text: 'じゃ、今日はもう終わり。明日もサボらず来なよね♡' },
    ],
  },
  {
    id: 'daily_002',
    type: 'daily',
    messages: [
      { id: 'daily_002_01', text: 'また来たんだ。ふーん、意外と続くじゃん' },
      {
        id: 'daily_002_02',
        text: '今日はね、新しい振り付けがやっと通しで踊れるようになったの。すごくない?',
      },
      {
        id: 'daily_002_03',
        type: 'choice',
        text: 'ねえ、ちょっと気になったんだけど……あんた、兄弟っているの?',
        choiceId: 'choice_siblings',
      },
      {
        id: 'daily_002_has_sib',
        text: 'へぇ、兄弟いるんだ。にぎやかそうでいいじゃん。ちょっとうらやましいかも',
        next: 'daily_002_merge',
      },
      {
        id: 'daily_002_no_sib',
        text: '一人っ子か。わたしと同じだね。まあ気楽でいいよね〜',
        next: 'daily_002_merge',
      },
      { id: 'daily_002_merge', text: 'ま、どっちでもいいんだけどね。ちょっと聞いてみただけ' },
      { id: 'daily_002_04', text: '……今日もルーティンできてるからよしとしてあげる。えらいえらい♡' },
    ],
  },
  {
    id: 'daily_003',
    type: 'daily',
    messages: [
      { id: 'daily_003_01', text: '3日目。へぇ、ほんとに続いてるんだ' },
      {
        id: 'daily_003_02',
        text: 'そういえば昨日、兄弟は{{fact:hasSiblings|いる?いない?}}って言ってたよね。ちゃんと覚えてるし',
      },
      {
        id: 'daily_003_03',
        text: 'うちはパパもママも共働きでさ、家に帰っても誰もいないことが多いんだよね',
      },
      { id: 'daily_003_04', text: 'だからってべつに寂しくないし。一人のほうが気楽だもん' },
      {
        id: 'daily_003_04b',
        text: '……まあ、こういう話をあんたにするの、ちょっと慣れてきたかも。毎日来るからだと思うけど',
        minPhase: 1,
        notes: '関係Phase1以上でのみ表示',
      },
      { id: 'daily_003_05', text: 'はい今日はおしまい。また明日ね、ざこ♡' },
    ],
  },
  {
    id: 'small_001',
    type: 'small_event',
    messages: [
      { id: 'small_001_01', text: 'ねえ、ちょっとだけ聞いてほしいことがあるんだけど' },
      {
        id: 'small_001_02',
        text: '……毎日あんたが来るの、正直ちょっとだけ楽しみにしてる。ほんとにちょっとだけね',
      },
      {
        id: 'small_001_03',
        type: 'choice',
        text: 'え、意外だった?',
        choiceId: 'choice_honne_react',
      },
      {
        id: 'small_001_happy',
        text: 'な……なにそれ。素直に言われると調子狂うんだけど',
        next: 'small_001_merge',
      },
      {
        id: 'small_001_know',
        text: 'は? 調子乗らないでよ。ちょっと言ってみただけなのに',
        next: 'small_001_merge',
      },
      { id: 'small_001_merge', text: 'とにかく! 明日も来なかったら怒るからね。ばーか♡' },
    ],
  },
  {
    id: 'small_002',
    type: 'small_event',
    messages: [
      {
        id: 'small_002_01',
        text: 'ねえ、今日のダンスの練習、我ながらけっこう上手く踊れたんだよね',
      },
      { id: 'small_002_02', text: '特別に1枚だけ見せてあげる。ほんとに1枚だけだからね' },
      {
        id: 'small_002_03',
        type: 'image',
        asset: 'event_rio_dance',
        text: '',
        notes: '画像メッセージ',
      },
      {
        id: 'small_002_04',
        type: 'choice',
        text: 'どう? わたしのダンス、ちょっとはかっこいいでしょ',
        choiceId: 'choice_dance_react',
      },
      {
        id: 'small_002_praise',
        text: 'でしょ? もっと褒めていいんだよ。ふふん',
        next: 'small_002_merge',
      },
      { id: 'small_002_pout', text: 'は? 見る目ないな〜。まあいいけど', next: 'small_002_merge' },
      { id: 'small_002_merge', text: '…見せたこと、誰にも言わないでよ。約束だからね' },
    ],
  },
  {
    id: 'small_003',
    type: 'small_event',
    messages: [
      { id: 'small_003_01', text: '3日も続けられたご褒美に、自分で自分に服を買ったの' },
      {
        id: 'small_003_02',
        type: 'image',
        asset: 'event_rio_skirt',
        text: '韓国っぽいやつ。かわいくない?',
      },
      { id: 'small_003_03', text: 'あんたも、続けたらいいことあるかもよ。……知らないけど' },
    ],
  },
  {
    id: 'large_001',
    type: 'large_event',
    messages: [
      {
        id: 'large_001_01',
        text: '……もしもし。こんな時間にごめん。起きてた?',
        portrait: 'rio_stand_normal',
      },
      { id: 'large_001_02', text: 'なんとなく、声聞きたくなっただけ。用があるわけじゃない' },
      { id: 'large_001_03', text: 'あのさ。前から思ってたんだけど' },
      {
        id: 'large_001_04',
        type: 'choice',
        text: 'あんた、わたしのこと面倒くさいって思ってる?',
        choiceId: 'choice_night_bother',
      },
      {
        id: 'large_001_soft',
        text: '……ふーん。まあ、そういうことにしといてあげる',
        next: 'large_001_cg',
      },
      {
        id: 'large_001_pout',
        text: 'は? 正直すぎでしょ。……でも、嘘つかれるよりマシか',
        next: 'large_001_cg',
      },
      {
        id: 'large_001_cg',
        text: 'でもね、こうやって毎日ちゃんと来てくれる人、あんたが初めてなんだ',
        cg: 'cg_rio_smile',
        notes: '一枚絵',
      },
      {
        id: 'large_001_05',
        text: '……だから、ちょっとだけ信じてみようかなって。ちょっとだけね',
        portrait: 'rio_stand_normal',
      },
      { id: 'large_001_06', text: 'この話、明日になったら忘れるから。おやすみ' },
    ],
  },
];

const choices: Choice[] = [
  {
    id: 'choice_siblings',
    options: [
      { label: 'いる', next: 'daily_002_has_sib', save: ['hasSiblings', 'いる'] },
      { label: 'いない(一人っ子)', next: 'daily_002_no_sib', save: ['hasSiblings', 'いない'] },
    ],
  },
  {
    id: 'choice_honne_react',
    options: [
      { label: 'うれしいよ', next: 'small_001_happy' },
      { label: '知ってた', next: 'small_001_know' },
    ],
  },
  {
    id: 'choice_dance_react',
    options: [
      { label: 'すごくかっこいい', next: 'small_002_praise', save: ['sawRioDance', 'はい'] },
      { label: 'まあまあかな', next: 'small_002_pout', save: ['sawRioDance', 'はい'] },
    ],
  },
  {
    id: 'choice_night_bother',
    options: [
      { label: '思ってないよ', next: 'large_001_soft' },
      { label: 'ちょっとだけ', next: 'large_001_pout' },
    ],
  },
];

const events: EventDef[] = [
  {
    id: 'event_small_001',
    type: 'small_event',
    title: '莉央のひとりごと',
    scenario: 'small_001',
    priority: 100,
    conditions: [{ type: 'user_state', key: 'trust', op: 'gte', value: '2' }],
  },
  {
    id: 'event_small_002',
    type: 'small_event',
    title: 'ダンスの動画、見る?',
    scenario: 'small_002',
    priority: 110,
    conditions: [{ type: 'user_state', key: 'trust', op: 'gte', value: '3' }],
  },
  {
    id: 'event_small_003',
    type: 'small_event',
    title: '新しい服、買ったんだ',
    scenario: 'small_003',
    priority: 120,
    conditions: [
      { type: 'user_state', key: 'trust', op: 'gte', value: '4' },
      { type: 'streak', key: 'continuous_days', op: 'gte', value: '3' },
    ],
  },
  {
    id: 'event_large_001',
    type: 'large_event',
    title: '夜の電話',
    scenario: 'large_001',
    priority: 200,
    background: 'bg_rio_room',
    advancesToPhase: 1,
    conditions: [
      { type: 'user_state', key: 'trust', op: 'gte', value: '5' },
      { type: 'streak', key: 'continuous_days', op: 'gte', value: '3' },
      { type: 'event', key: 'event_completed', op: 'exists', value: 'event_small_001' },
    ],
  },
];

// --- row builders --------------------------------------------------------

function scenarioRows(): string[][] {
  const rows: string[][] = [];
  for (const s of scenarios) {
    s.messages.forEach((m, i) => {
      const rec: Record<string, string> = {
        scenario_id: s.id,
        scenario_type: s.type,
        line_order: String(i + 1),
        node_id: m.id,
        speaker: m.speaker ?? 'character',
        message_type: m.type ?? 'text',
        text: m.text ?? '',
        choice_id: m.choiceId ?? '',
        next_node_id: m.next ?? '',
        save_key: m.save?.[0] ?? '',
        save_value: m.save?.[1] ?? '',
        asset_id: m.asset ?? '',
        min_phase: m.minPhase !== undefined ? String(m.minPhase) : '',
        portrait: m.portrait ?? '',
        cg: m.cg ?? '',
        enabled: 'TRUE',
        notes: m.notes ?? '',
      };
      rows.push(SCENARIO_COLS.map((c) => rec[c] ?? ''));
    });
  }
  return rows;
}

function choiceRows(): string[][] {
  const rows: string[][] = [];
  for (const c of choices) {
    c.options.forEach((o, i) => {
      const rec: Record<string, string> = {
        choice_id: c.id,
        choice_order: String(i + 1),
        label: o.label,
        next_node_id: o.next,
        save_key: o.save?.[0] ?? '',
        save_value: o.save?.[1] ?? '',
        required_key: o.require?.[0] ?? '',
        required_operator: o.require?.[1] ?? '',
        required_value: o.require?.[2] ?? '',
        enabled: 'TRUE',
        notes: '',
      };
      rows.push(CHOICE_COLS.map((k) => rec[k] ?? ''));
    });
  }
  return rows;
}

function eventRows(): string[][] {
  const rows: string[][] = [];
  for (const e of events) {
    for (const cond of e.conditions) {
      const rec: Record<string, string> = {
        event_id: e.id,
        event_type: e.type,
        title: e.title,
        entry_scenario_id: e.scenario,
        priority: String(e.priority),
        repeatable: 'FALSE',
        cooldown_days: '0',
        condition_type: cond.type,
        condition_key: cond.key,
        operator: cond.op,
        threshold: cond.value,
        background: e.background ?? '',
        advances_to_phase: e.advancesToPhase !== undefined ? String(e.advancesToPhase) : '',
        enabled: 'TRUE',
        notes: '同一event_idの条件はAND',
      };
      rows.push(EVENT_COLS.map((k) => rec[k] ?? ''));
    }
  }
  return rows;
}

// --- outputs -----------------------------------------------------------

function grid(tab: keyof typeof TITLE, cols: string[], dataRows: string[][]): string[][] {
  const [t1, t2] = TITLE[tab] ?? ['', ''];
  return [[t1], [t2], cols, ...dataRows];
}

async function main(): Promise<void> {
  const snapshot = {
    fetchedAt: new Date().toISOString(),
    sheetId: 'seed',
    source: 'snapshot' as const,
    tabs: {
      scenarios: grid('scenarios', SCENARIO_COLS, scenarioRows()),
      choices: grid('choices', CHOICE_COLS, choiceRows()),
      events: grid('events', EVENT_COLS, eventRows()),
    },
  };

  // verify: this data must pass validation and generate cleanly
  const result = runPipeline(snapshotToRawSheets(snapshot));
  if (result.issues.hasErrors) {
    console.error('✖ 生成データに検証エラー:');
    for (const e of result.issues.errors) console.error('  ', e.code, e.message, e.at);
    process.exit(1);
  }
  console.log(
    `✓ 検証OK  daily ${result.artifacts!.daily.scenarios.length}本 / events ${result.artifacts!.events.events.length}件` +
      (result.issues.warnings.length ? ` (警告 ${result.issues.warnings.length})` : ''),
  );

  const fixturePath = resolve(TOOL_ROOT, 'fixtures/full-content.snapshot.json');
  writeFileSync(fixturePath, JSON.stringify(snapshot, null, 2) + '\n', 'utf8');
  console.log('✓', fixturePath);

  const outDir = resolve(TOOL_ROOT, 'seed');
  mkdirSync(outDir, { recursive: true });

  // (1) XLSX — for "ファイル > インポート > スプレッドシートを置換"
  const wb = new ExcelJS.Workbook();
  wb.creator = 'scenario-sync seed';
  for (const [name, rows] of Object.entries(snapshot.tabs)) {
    const ws = wb.addWorksheet(name);
    rows.forEach((r) => ws.addRow(r));
    ws.getRow(3).font = { bold: true };
    ws.views = [{ state: 'frozen', ySplit: 3 }];
    (rows[2] ?? []).forEach((_, i) => {
      ws.getColumn(i + 1).width = 18;
    });
  }
  const xlsxPath = resolve(outDir, 'scenario-data.xlsx');
  await wb.xlsx.writeFile(xlsxPath);
  console.log('✓', xlsxPath);

  // (2) TSV per tab — header + data, to paste over each tab starting at cell A3
  for (const [name, rows] of Object.entries(snapshot.tabs)) {
    const body = rows.slice(2); // drop the 2 title rows; keep header + data
    const tsv = body
      .map((r) => r.map((c) => c.replace(/\t/g, ' ').replace(/\r?\n/g, ' ')).join('\t'))
      .join('\n');
    const tsvPath = resolve(outDir, `${name}.tsv`);
    writeFileSync(tsvPath, tsv + '\n', 'utf8');
    console.log('✓', tsvPath);
  }

  console.log('\n取り込み方法（どちらか）:');
  console.log(
    '  A) 一括: ファイル > インポート > アップロード > scenario-data.xlsx > 「スプレッドシートを置換する」',
  );
  console.log('  B) 貼り付け: 各タブの A3 セルを選び、seed/<タブ名>.tsv の中身をそのまま貼り付け');
  console.log('\n取り込み後: cd tools/scenario-sync && npm run sync で生成JSONを更新');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
