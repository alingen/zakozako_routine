# scenario-sync

Google Sheets のストーリーCMSを検証し、アプリ用JSONへ一方向に変換するツールです。
Google Sheets が唯一の正本（SSOT）です。

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
| `SCENARIO_TAB_SCENARIOS` | scenariosタブ名。既定値 `scenarios` |
| `SCENARIO_TAB_CHOICES` | choicesタブ名。既定値 `choices` |
| `SCENARIO_TAB_EVENTS` | eventsタブ名。既定値 `events` |
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

終了コードは成功が `0`、検証エラー・`--check` の差分が `1`、引数・取得など実行エラーが `2` です。

## データフロー

```text
Google Sheets (read only)
  ├─ scenarios: 1 row = 1 node
  ├─ choices:   1 row = 1 choice option
  └─ events:    1 row = 1 AND condition
       ↓ header detection / normalization / validation
StoryContentBundle
       ↓ same-directory temporary file + rename
story_content.generated.json
```

シート上部にタイトルや説明行があっても、`scenario_id` / `choice_id` / `event_id` を含む行を
実ヘッダーとして自動検出します。`enabled` は空欄を `TRUE` と解釈し、`FALSE` の行は除外します。

### scenarios（25列）

`scenario_id`, `scenario_type`, `line_order`, `node_id`, `speaker`, `message_type`, `text`,
`choice_id`, `next_node_id`, `save_key`, `save_value`, `asset_id`, `min_phase`, `max_phase`,
`speaker_name`, `typing_duration_ms`, `background`, `portrait`, `cg`, `enabled`, `notes`,
`screen_mode`, `ui_variant`, `command`, `command_args`

- `node_id` と `line_order` は同一 `scenario_id` 内で一意にします。
- 遷移優先順位は `choice.next_node_id` → nodeの `next_node_id` → `line_order` の次行です。
- `speaker`, `message_type`, `screen_mode`, `ui_variant`, `command` の原値を保持します。
- `command_args` はJSON objectです。配列・scalarは破棄せず診断しますが、検証エラーになります。
- nested object/array/scalarを含む任意のJSON値を保持します。
- `scenario_type` は現在 `daily`, `small_event`, `middle_event`, `large_event` を利用しています。
- `typing_duration_ms` は莉央の各セリフで「入力中…」を表示する時間です。空欄時はアプリ既定の
  600msを使い、個別指定する場合は0〜30000の整数を入力します。

### choices（11列）

`choice_id`, `choice_order`, `label`, `next_node_id`, `save_key`, `save_value`, `required_key`,
`required_operator`, `required_value`, `enabled`, `notes`

同じ `choice_id` の行を1つのchoice groupへまとめます。遷移先はそのgroupを参照する各scenario内で
検証されます。未使用groupはwarningです。

### events（18列）

`event_id`, `event_type`, `title`, `entry_scenario_id`, `priority`, `repeatable`, `cooldown_days`,
`condition_type`, `condition_key`, `operator`, `threshold`, `background`, `advances_to_phase`,
`enabled`, `notes`, `chapter_id`, `episode_order`, `story_category`

同じ `event_id` の複数行は条件のAND配列になります。条件以外のmetadataは全行で一致させます。
`entry_scenario_id` は存在するscenarioを参照し、`event_type` とその `scenario_type` を一致させます。

## 検証と前方互換性

必須値、型、pair列、重複、scenario内遷移、choice/event参照、event metadata、到達可能性、
終了不能cycleを検証します。未知の `screen_mode`, `ui_variant`, `command`, `story_category`,
`operator` は破棄やクラッシュをせず、原値を生成物へ保持したうえでwarningを出します。

choiceの `next_node_id` が参照切れの場合はwarningとし、Playerと同じくそのchoice node直後の
`line_order` へ復旧できる前提で到達性も診断します。この方針はIDに依存せず全scenarioへ共通です。
現行シートでは `daily_001` / `first_day_can_do` の `daily_001_09` と `daily_001_10` が該当し、
その影響を受ける3ノードの到達経路を確定できない警告を含めて5 warningsです。node自身の `next_node_id` 参照切れ、
scenario外へのchoice参照、その他の必須値・型・重複・終了不能cycleはerrorで生成を止めます。

また、取得失敗や誤ったheader検出を全削除と誤認しないよう、scenarios／choices／eventsのいずれかが
空、または有効な正規化行が0件なら生成物を書き換えずerrorで停止します。

## 生成物

生成JSONは次の単一bundleです。

```json
{
  "_generated": "AUTO-GENERATED ...",
  "scenarios": [{ "scenarioId": "...", "scenarioType": "...", "nodes": [] }],
  "choiceGroups": [{ "choiceId": "...", "choices": [] }],
  "events": [{ "eventId": "...", "conditions": [] }]
}
```

scenario、node、choice、event、conditionは安定した規則でソートされ、入力行順に依存しません。
`--check` はこの決定的出力とコミット済み生成物を比較します。

## Snapshot運用

`fixtures/sheets-snapshot.json` はオフラインテストと再現用で、正本ではありません。手編集せず、
ライブ取得が成功した状態で `--save-snapshot [path]` を使って更新してください。snapshot指定時は
ネットワークへ接続せず、ライブ取得時はsnapshotを自動利用しません。
