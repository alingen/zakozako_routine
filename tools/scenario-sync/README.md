# scenario-sync

会話シナリオ（今日の会話 / 小イベント / 大イベント）を **Google スプレッドシート（唯一の正本）** で編集し、
アプリが読み込む正規化済みJSONへ一方向に同期するツール。

```
Google Sheets（正本）
  → fetch（取得）
  → normalize（トリム・型変換・正規化・無効行除外）
  → validate（検証：エラーがあれば中止）
  → diff（差分表示）
  → generate（正規化JSON生成 / 一時ファイル → アトミック置換）
  → format / typecheck / test
  → アプリが MesugakiRoutine/Resources/GeneratedScenarios/*.generated.json を読み込む
```

**生成物 (`*.generated.json`) は直接編集しないこと。** 会話を変更するときは必ずスプレッドシートを更新してから同期する。
生成物の先頭には `_generated` フィールドで「自動生成・直接編集禁止」と明記される。

---

## 1. 初回セットアップ

```bash
cd tools/scenario-sync
npm install
```

対象スプレッドシートID はコードにデフォルト値（`src/config.ts` の `DEFAULT_SHEET_ID`）を持たせているので、
**公開（リンクを知っている全員が閲覧可）なら `.env` は不要**。

### 取得方法は2通り（自動選択）

| 状況 | 取得方法 |
| --- | --- |
| スプレッドシートが公開（閲覧リンク共有） | **公開XLSXエクスポート**（`https://docs.google.com/.../export?format=xlsx`）。認証不要 |
| 非公開 | **Google Sheets API v4**（サービスアカウント）。`.env` に認証情報が必要 |

### 非公開シートの場合（サービスアカウント）

1. Google Cloud Console で **Google Sheets API** を有効化。
2. **サービスアカウント**を作成し JSON キーをダウンロード → `tools/scenario-sync/secrets/service-account.json`（git 無視）。
3. スプレッドシートをサービスアカウントのメール（`xxxx@xxxx.iam.gserviceaccount.com`）に **閲覧者** で共有。
4. `.env`（`cp .env.example .env`、コミットされない）:
   ```
   SCENARIO_SHEET_ID=<スプレッドシートURLの /d/ と /edit の間>
   GOOGLE_APPLICATION_CREDENTIALS=./secrets/service-account.json
   # または SCENARIO_GOOGLE_SA_JSON に JSON を1行で（こちらが優先）
   ```

認証情報が無くシートも非公開なら、`fixtures/sheets-snapshot.json`（コミット済みのシート内容スナップショット）に対して
検証・生成・差分チェックは実行できる（`--snapshot`）。

### スプレッドシート冒頭のタイトル行

各シートの1〜2行目に説明文（マージセル）が入っていても、`scenario_id` / `choice_id` / `event_id` を
含む行を実ヘッダーとして自動検出するので、そのまま扱える。

### スプレッドシートのひな形

```bash
npm run make-template
```
`template/scenario-template.xlsx` が生成される。Google Sheets の「ファイル > インポート」で取り込むと、
3シート・全列・列挙値のドロップダウン・現行サンプル行が入った状態から始められる。

### 既存の会話データを一括投入（初回シード）

```bash
npm run seed
```
STEP 2〜7 で作った会話（daily Day 1〜3 + 小イベント3 + 大イベント1）を `seed/` に出力する。

- `seed/scenario-data.xlsx` … 「ファイル > インポート > アップロード > スプレッドシートを置換する」
- `seed/{scenarios,choices,events}.tsv` … 各タブの **A3 セル**に貼り付け（1〜2行目のタイトル行は残る）

取り込んだら `npm run sync` で生成JSONに反映する。

---

## 2. 同期のしかた

| コマンド | 用途 |
| --- | --- |
| `npm run sync` | 取得 → 検証 → 差分表示 → **確認プロンプト** → 書き込み → 型チェック・テスト |
| `npm run sync -- --write` | 確認なしで書き込み |
| `npm run sync:check` | CI 用。書き込みなし。差分 or 検証エラーで exit 1 |
| `npm run sync -- --snapshot` | ライブ取得せずスナップショットを使う |
| `npm run sync -- --no-tests` | 書き込み後の型チェック・テストをスキップ |

ライブ取得で書き込んだ場合、`fixtures/sheets-snapshot.json` も更新される（CI のオフライン `--check` の基準になる）。

### 反映後にアプリへ

```bash
cd ../..
xcodegen generate
xcodebuild -project MesugakiRoutine.xcodeproj -scheme MesugakiRoutine \
  -destination 'id=<デバイスID>' -allowProvisioningUpdates build
```

### 手順まとめ

```
Google Sheets を編集 → npm run sync（/sync-scenarios）→ 差分確認 → 反映
  → xcodegen + xcodebuild（型チェック・動作確認）→ *.generated.json をコミット
```

---

## 3. 差分確認

`npm run sync` は反映前に次を表示する:

- 追加 / 更新 / 削除された scenario・choice・event の件数と ID
- 会話テキスト変更の before / after
- 遷移先（next）・保存値（saveFact）・解放条件の変更
- 削除・無効化など影響の大きい変更（`⚠️ 影響の大きい変更` セクション）

認証情報や秘密は差分に含まれない。

---

## 4. スプレッドシートの構造

### `scenarios` シート — 1行 = 1会話ノード

| 列 | 必須 | 説明 |
| --- | --- | --- |
| `scenario_id` | ✓ | 会話のまとまり。`daily` はこの ID の昇順が Day 番号になる |
| `scenario_type` | ✓ | `daily` / `small_event` / `large_event` |
| `line_order` | ✓ | 同一 `scenario_id` 内の並び順（整数・重複不可） |
| `node_id` | ✓ | **全シナリオ横断で一意** |
| `speaker` | ✓ | `character` / `user` / `system`（`system` はアプリ上 `character` として表示） |
| `message_type` | ✓ | `text` / `choice` / `system` / `image` |
| `text` | ✓ | 本文。`image` の場合はキャプション（空可）。`{{fact:キー}}` / `{{fact:キー|代替}}` で保存済み情報を参照 |
| `choice_id` |  | `message_type=choice` のとき必須。`choices` シートの `choice_id` を参照 |
| `next_node_id` |  | 次のノード。空なら `line_order` 順で次の行へ |
| `save_key` / `save_value` |  | このノード表示時にユーザー情報を保存（両方セット） |
| `asset_id` |  | `message_type=image` の画像名（Assets.xcassets） |
| `min_phase` / `max_phase` |  | 関係性フェーズ条件。範囲外なら丸ごとスキップ |
| `speaker_name` |  | （大イベント）名前ウィンドウの表示名 |
| `background` / `portrait` / `cg` |  | （大イベント）背景 / 立ち絵 / 一枚絵 の画像名 |
| `enabled` |  | 空欄は `TRUE`。`FALSE` の行は生成物から除外 |
| `notes` |  | メモ（生成物には出ない） |

### `choices` シート — 1行 = 1選択肢

| 列 | 必須 | 説明 |
| --- | --- | --- |
| `choice_id` | ✓ | 同じ ID の複数行で選択肢群を作る |
| `choice_order` | ✓ | 同一 `choice_id` 内の並び順（整数・重複不可） |
| `label` | ✓ | 画面に出す選択肢テキスト |
| `next_node_id` |  | 選択後に進むノード（`scenarios.node_id` を参照） |
| `save_key` / `save_value` |  | 選択時に保存するユーザー情報 |
| `required_key` / `required_operator` / `required_value` |  | 表示条件。演算子は空 or `eq` `ne` `gt` `gte` `lt` `lte` `exists` |
| `enabled` |  | `FALSE` の行は除外 |
| `notes` |  | メモ |

### `events` シート — 1行 = 1イベント条件

| 列 | 必須 | 説明 |
| --- | --- | --- |
| `event_id` | ✓ | 同じ `event_id` の複数行は **AND 条件** |
| `event_type` | ✓ | `small_event` / `large_event`（参照先シナリオの `scenario_type` と一致必須） |
| `title` | ✓ | イベント名（同一 `event_id` 内で一致必須） |
| `entry_scenario_id` | ✓ | 台本となる `scenarios.scenario_id`（同上） |
| `priority` | ✓ | 小さいほど優先（同上）。生成物はこの順にソートされる |
| `repeatable` / `cooldown_days` |  | 空欄は `FALSE` / `0`（※現状アプリ側は未使用・生成物には保持） |
| `condition_type` | ✓ | グルーピング用の自由ラベル（`user_state` / `streak` / `event` / …）。実際の判定は `condition_key` で決まる |
| `condition_key` | ✓ | `trust` / `continuous_days`(=`streak_days`) / `blocked_protected_count` / `mastered_count` / `relationship_phase` / `event_completed`（別名可） |
| `operator` | ✓ | メトリクスは `gte` / `gt` のみ対応。`event_completed` は `exists` |
| `threshold` | ✓ | しきい値（メトリクスは非負整数、`event_completed` は前提イベントID） |
| `background` / `advances_to_phase` |  | （大イベント）初期背景 / 完了時に進める関係性フェーズ |
| `enabled` |  | `FALSE` のイベント / 条件は除外 |
| `notes` |  | メモ |

---

## 5. 検証ルール

エラー（**同期中止**）:

- 必須列・必須値の欠落、許可されない列挙値、数値・真偽値の型不正
- `node_id` の重複、同一 `scenario_id` 内 `line_order` 重複、同一 `choice_id` 内 `choice_order` 重複
- `choices.next_node_id` / `scenarios.choice_id` / `events.entry_scenario_id` の参照切れ
- `event_type` と参照先 `scenario_type` の不一致
- 到達不能ノード、存在しない遷移先、出口の無い無限ループ
- choice ノードに有効な選択肢が0件
- 同一イベント内で `title` / `entry_scenario_id` / `priority` 等が不一致
- アプリが解釈できない条件演算子

警告（続行）:

- 未知の列、`priority` の重複、`image` 以外での `asset_id`、その他

すべてのメッセージに **シート名・行番号・列名・問題の値・修正案** が付く。

---

## 6. 生成物

`MesugakiRoutine/Resources/GeneratedScenarios/`:

- `daily_conversations.generated.json` — `{ _generated, scenarios: [{ scenarioId, dayIndex, messages }] }`
- `events.generated.json` — `{ _generated, events: [EventDefinition] }`

`messages` の各要素は Swift の `ScriptMessage`、`unlockConditions` は `EventCondition` にそのままデコードされる。
出力は入力の行順に依存せず安定（scenario は `scenario_id`、choice は `choice_order`、event は `priority, event_id` でソート）。

---

## 7. 型・テスト・CI

- 入力型 (`Raw*`)、正規化型 (`Normalized*`)、アプリ出力型 (`App*`) を `src/types.ts` に定義。列挙・列契約は `src/schema.ts`。
- `npm test`（vitest）: 正常系・重複ID・参照切れ・不正な列挙値・条件AND・無効行除外・安定ソート・無限ループ検出・スナップショットのドリフト検出。
- `npm run typecheck`（`tsc --noEmit`）。
- CI（`.github/workflows/scenario-sync.yml`）: `typecheck` + `format:check` + `test` + `sync:check`。
  Sheets 認証をリポジトリ Secrets（`SCENARIO_SHEET_ID` / `SCENARIO_GOOGLE_SA_JSON`）に入れればライブ取得で照合、
  無ければスナップショット検証＋生成物ドリフトチェックにフォールバックする。

---

## 8. トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| `ログイン画面が返されました` | シートが非公開。「リンクを知っている全員が閲覧可」にするか、サービスアカウント認証を設定 |
| `公開XLSXの取得に失敗` | ネットワーク／共有設定を確認。`--snapshot` でオフライン実行も可 |
| `The caller does not have permission` | 非公開シートをサービスアカウントのメールに共有 |
| 検証エラーで中止 | エラーメッセージの行・列・修正案に従ってシートを直し、再実行 |
| `sync:check` が CI で落ちる | ローカルで `npm run sync -- --write` して `*.generated.json` をコミット |
| アプリに反映されない | `xcodegen generate` を実行してから再ビルド（新規ファイルはプロジェクト再生成が必要） |
