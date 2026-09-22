# scenario-sync

Google SheetsのコンテンツCMSを検証し、アプリ用JSONへ一方向に変換するツールです。
Google Sheetsが唯一の正本（SSOT）です。

`MesugakiRoutine/Resources/GeneratedScenarios/story_content.generated.json` は自動生成物です。
直接編集せず、必ずシートを更新してからこのツールで再生成してください。

## セットアップ

Node.js 20以上が必要です。

```bash
cd tools/scenario-sync
npm install
```

対象シートは公開・読み取り専用XLSXとして取得できます。非公開シートではGoogle Sheets APIの
読み取り専用scopeを使うサービスアカウントを設定してください。

| 環境変数 | 用途 |
| --- | --- |
| `SCENARIO_SHEET_ID` | 対象Google Sheets ID。未設定時はコード内の既定ID |
| `SCENARIO_TAB_DAILY` | 日常会話タブ名。既定値 `daily` |
| `SCENARIO_TAB_DAILY_CATALOG` | 日常会話カタログタブ名。既定値 `daily_catalog` |
| `SCENARIO_TAB_CHOICES` | 日常会話の選択肢タブ名。既定値 `choices` |
| `SCENARIO_TAB_INTERACTIONS` | 交流コメントタブ名。既定値 `interactions` |
| `SCENARIO_TAB_SCENARIOS` | イベントシナリオタブ名。既定値 `senarios` |
| `SCENARIO_TAB_EVENTS` | イベント定義タブ名。既定値 `events` |
| `GOOGLE_APPLICATION_CREDENTIALS` | サービスアカウントJSONへのパス |
| `SCENARIO_GOOGLE_SA_JSON` | サービスアカウントJSON本体。パス指定より優先 |

環境変数は `tools/scenario-sync/.env` にも記載できます。認証情報や `.env` はコミットしないでください。

## コマンド

リポジトリルートから実行する場合:

```bash
# ライブ取得 → 検証 → 差分予定を表示。ファイルは変更しない
npm --prefix tools/scenario-sync run sync

# ライブ取得。検証エラーまたは生成物差分があれば非ゼロ終了
npm --prefix tools/scenario-sync run sync:check

# ライブ取得した内容から生成物をatomic write
npm --prefix tools/scenario-sync run sync:write

# 明示した場合だけコミット済みsnapshotを利用
npm --prefix tools/scenario-sync run sync:check -- --snapshot
npm --prefix tools/scenario-sync run sync:check -- --snapshot ./fixtures/sheets-snapshot.json

# ライブ取得結果を読み取り用snapshotとして保存
npm --prefix tools/scenario-sync run sync -- --save-snapshot

# ライブ正本から生成物とsnapshotを同時に更新
npm --prefix tools/scenario-sync run sync -- --write --save-snapshot

npm --prefix tools/scenario-sync test
npm --prefix tools/scenario-sync run typecheck
```

引数なしの `sync` は常に非破壊のplanです。`--write` がない限り生成物を書き換えません。
ライブ取得に失敗してもsnapshotへ暗黙fallbackしません。オフライン確認は必ず `--snapshot [path]`
を明示してください。`--write` はライブ正本にのみ許可されます。

## データフロー

```text
Google Sheets (read only)
  ├─ daily:        1 row = 1 daily conversation node
  ├─ daily_catalog: 1 row = 1 daily conversation metadata entry
  ├─ choices:      1 row = 1 daily choice option
  ├─ interactions: 1 row = 1 short interaction comment
  ├─ senarios:     1 row = 1 event scenario node
  └─ events:       1 row = 1 event AND condition
       ↓ header detection / normalization / validation
StoryContentBundle
       ↓ same-directory temporary file + rename
story_content.generated.json
```

シート上部にタイトルや説明行があっても、各シートのID列を含む行を実ヘッダーとして自動検出します。
`enabled`／`active` は空欄を `TRUE` と解釈します。`daily_catalog.enabled=FALSE` の話は
対応する `daily` 本文と `choices` をまとめて生成対象から除外します。`daily.enabled` は本文の
個別node、その他の `enabled`／`active` は各行の生成可否を表します。

### daily（21列）

`scenario_id`, `line_order`, `node_id`, `speaker`, `message_type`, `text`, `choice_id`,
`next_node_id`, `save_key`, `save_value`, `asset_id`, `min_phase`, `max_phase`, `speaker_name`,
`typing_duration_ms`, `enabled`, `notes`, `screen_mode`, `ui_variant`, `command`, `command_args`

- 日常会話だけを置き、生成時に `scenario_type=daily` を付与します。
- 話単位の題名、表示順、日付、制作状態、配信可否は `daily_catalog` で管理します。
- 背景、立ち絵、CGは日常会話では使わず、`senarios` 側のイベントだけで管理します。
- `node_id` と `line_order` は同一 `scenario_id` 内で一意にします。
- 遷移優先順位は `choice.next_node_id` → nodeの `next_node_id` → `line_order` の次行です。
- `typing_duration_ms` は0〜30000の整数で、空欄時はアプリ既定の600msです。

### daily_catalog（8列）

`scenario_id`, `title`, `display_order`, `category`, `calendar_date`,
`calendar_month_day`, `status`, `enabled`

- `scenario_id` は `daily.scenario_id` と1対1で対応させます。重複、本文のないカタログ、
  カタログのない本文はエラーです。
- `title` は制作時に話を探すための題名、`category` と `status` は制作管理用の文字列です。
- `calendar_date` は一度だけ表示する日を `YYYY-MM-DD`、`calendar_month_day` は毎年同じ日に
  表示する日を `MM-DD` で指定します。2列の併用と同じ日付の重複はエラーです。
- 日付のない有効な話には、1以上で重複しない `display_order` が必要です。
- アプリは `calendar_date` の完全一致を優先し、なければ `calendar_month_day` を使います。
  日付判定は継続日数や初回利用日に依存せず、アプリ日の境界（朝4時）で切り替わります。
- `enabled=FALSE` の話は本文と選択肢も含めて生成されません。チェックボックス設定によって
  `enabled=FALSE` だけが入った空行は、未入力行として無視します。

### choices（9列）

`daily_id`, `choice_id`, `choice_order`, `label`, `next_node_id`, `save_key`, `save_value`,
`enabled`, `notes`

- `daily_id` は有効な `daily_catalog.scenario_id` と、それに対応する `daily.scenario_id` を参照します。
- 同じ `choice_id` の行を1つのchoice groupへまとめます。
- 1つの日常会話に複数の選択箇所を置けるよう、`daily_id` と `choice_id` を分けています。
- 旧 `required_key`／`required_operator`／`required_value` は廃止しました。

### interactions（7列）

`id`, `text`, `condition`, `time_condition`, `touch_area`, `weight`, `active`

- `id` は一意、`weight` は1以上です。
- `time_condition` は空欄／`always`、`morning`（4〜11時）、`daytime`（12〜16時）、
  `evening`（17〜21時）、`night`（22〜3時）を利用できます。
- `touch_area` は空欄／`all`、`character`、`head`、`body` を利用できます。
- `condition` は空欄／`always`、`profile:key`、`profile:key=value`、
  `profile:key!=value` を利用できます。未知の条件はアプリ側で非該当になります。
- アプリは条件に合う候補を `weight` で重み付き抽選し、候補が複数なら直前のIDを除外します。

### senarios（25列）

`scenario_id`, `scenario_type`, `line_order`, `node_id`, `speaker`, `message_type`, `text`,
`choice_id`, `next_node_id`, `save_key`, `save_value`, `asset_id`, `min_phase`, `max_phase`,
`speaker_name`, `typing_duration_ms`, `background`, `portrait`, `cg`, `enabled`, `notes`,
`screen_mode`, `ui_variant`, `command`, `command_args`

- プロローグと小・中・大イベントの本文を同じシートで管理します。
- `scenario_type` は `prologue`、`small_event`、`middle_event`、`large_event` のいずれかです。
- その他のnode／演出列の意味は `daily` と共通です。

### events（18列）

`event_id`, `event_type`, `title`, `entry_scenario_id`, `priority`, `repeatable`, `cooldown_days`,
`condition_type`, `condition_key`, `operator`, `threshold`, `background`, `advances_to_phase`,
`enabled`, `notes`, `chapter_id`, `episode_order`, `story_category`

- `event_type` は `prologue`、`small_event`、`middle_event`、`large_event` のいずれかです。
- `episode_order` は0以上の整数です。プロローグには0を使い、通常の各話には1以上を使います。
- メインストーリーの解放条件は `condition_type=achievement`、
  `condition_key=cumulative_days`、`operator=gte` を使います。累積達成日数は、
  その日に1つ以上の約束を達成した日を1日として数え、連続している必要はありません。
- 同じ `event_id` の複数行は条件のAND配列になります。条件以外のmetadataは全行で一致させます。
- `entry_scenario_id` は `senarios.scenario_id` を参照し、`event_type` と参照先の
  `scenario_type` を一致させます。

## 検証と前方互換性

必須値、型、pair列、重複、シート間参照、scenario内遷移、event metadata、到達可能性、
終了不能cycleを検証します。未知の表示値やcommandは破棄やクラッシュをせず、原値を生成物へ
保持したうえでwarningを出します。未知の交流コメント条件・時間帯は誤表示を避けるためアプリで
非該当として扱います。

choiceの `next_node_id` が参照切れの場合はwarningとし、Playerと同じくそのchoice node直後の
`line_order` へ復旧できる前提で到達性も診断します。node自身の `next_node_id` 参照切れ、
シートをまたぐ不正参照、その他の必須値・型・重複・終了不能cycleはerrorで生成を止めます。

また、取得失敗や誤ったheader検出を全削除と誤認しないよう、6シートのいずれかが空、または
有効な正規化行が0件なら生成物を書き換えずerrorで停止します。

## 生成物

生成JSONは編集用6シートを、そのまま複製せずアプリ向けの単一bundleへ統合します。

```json
{
  "_generated": "AUTO-GENERATED ...",
  "scenarios": [{
    "scenarioId": "...", "scenarioType": "daily", "title": "...",
    "displayOrder": 1, "category": "...", "status": "...", "enabled": true,
    "nodes": []
  }],
  "choiceGroups": [{ "choiceId": "...", "choices": [] }],
  "interactions": [{ "id": "...", "text": "...", "weight": 1, "active": true }],
  "events": [{ "eventId": "...", "eventType": "...", "conditions": [] }]
}
```

dailyとsenariosは `scenarios` へ統合され、daily_catalogのmetadataは対応するdaily scenarioへ
結合されます。scenario、node、choice、interaction、event、conditionは
安定した規則でソートされ、入力行順に依存しません。`--check` はこの決定的出力とコミット済み生成物を
比較します。

## Snapshot運用

`fixtures/sheets-snapshot.json` はオフラインテストと再現用で、正本ではありません。手編集せず、
ライブ取得が成功した状態で `--save-snapshot [path]` を使って更新してください。snapshot指定時は
ネットワークへ接続せず、ライブ取得時はsnapshotを自動利用しません。
