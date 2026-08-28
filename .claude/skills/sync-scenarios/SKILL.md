---
name: sync-scenarios
description: Sync conversation scenarios (daily talks, small/large events) from the Google Sheets source of truth into the app's generated JSON. Use when the user asks to sync scenarios, pull scenario changes, run /sync-scenarios, or after they say they edited the scenario spreadsheet.
---

# sync-scenarios

Google スプレッドシート（正本）→ 正規化JSON の一方向同期を実行する。生成物 (`MesugakiRoutine/Resources/GeneratedScenarios/*.generated.json`) は**絶対に手で編集しない**。会話を変えるときはシートを編集してこの同期を回す。

## 手順

1. **作業ディレクトリ**: `tools/scenario-sync/`
2. 依存が未インストールなら `npm install`（`node_modules/` が無ければ）。
3. 同期を実行:
   - 通常: `npm run sync`
     - Sheets 認証情報 (`.env`) があればライブ取得、無ければ `fixtures/sheets-snapshot.json` を使う。
     - 「変更予定ファイル」「差分（テキスト before/after・遷移先・保存値・解放条件・影響大の警告）」を表示し、確認プロンプトが出る。ユーザーに差分を見せて、反映してよいか確認してから `y`。
   - 確認を挟まず反映: `npm run sync -- --write`
   - CI / ずれ検出のみ: `npm run sync:check`（書き込みなし。ずれ or 検証エラーで exit 1）
4. 検証エラーがある場合は**書き込まれない**。エラー（シート名・行番号・列名・値・修正案つき）をユーザーに伝え、シート側を直してもらう。
5. 反映後、`npm run sync` が自動で「型チェック(tsc) → JSON フォーマット確認(prettier) → テスト(vitest)」を実行する（`--no-tests` でスキップ可）。
6. **アプリ側の反映**: 生成JSONが変わったら iOS 側もビルドし直す:
   ```
   cd ../..
   xcodegen generate
   xcodebuild -project MesugakiRoutine.xcodeproj -scheme MesugakiRoutine \
     -destination 'id=00008101-0015315A2ED0001E' -allowProvisioningUpdates build
   ```
7. 問題なければ、変更された `*.generated.json`（＋ライブ取得時は `fixtures/sheets-snapshot.json`）をコミットする。

## 全体フロー

```
Google Sheets を編集 → /sync-scenarios → 差分確認 → 反映 → iOS 型チェック・テスト → コミット
```

## 環境変数（`tools/scenario-sync/.env`、コミット禁止）

- `SCENARIO_SHEET_ID` — スプレッドシートID
- `GOOGLE_APPLICATION_CREDENTIALS` — サービスアカウントJSONのパス（または `SCENARIO_GOOGLE_SA_JSON` にインラインJSON）

詳細は `tools/scenario-sync/README.md`。
