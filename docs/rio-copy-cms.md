# 莉央のセリフの管理場所

正本は [シナリオCMS](https://docs.google.com/spreadsheets/d/1Ifkw0X4TIOxe0f9EpZpZEGIexLg-xoXG8c-ro4I5MBM/edit)。

| タブ | 用途 |
| --- | --- |
| `senarios` / `daily` | ストーリー・日常会話のセリフ |
| `interactions` | 通常のタッチ会話（日替わり候補） |
| `reaction_conditions` / `reaction_lines` | 状況・操作に応じたセリフ、達成ポップアップ、ホームのミニ莉央 |
| `rio_lines` | 初回案内、通知、莉央からのお題 |

## rio_lines

2026-09-27にコード内の固定文35件とローカルのお題39件を移した。文言はそのまま。
初回案内の読み上げ用ラベルも本文と同じ行を参照する。

ホームの追加機能分も含む91件のうち、状況・操作に対応する32件を `reaction_lines` へ移管した。
`rio_lines` の有効な行は59件（お題39件＋初回案内・通知など20件）。
移管した旧行は `active=FALSE` とし、移管先をnoteに記録して履歴として残す。再有効化せず、移管先を編集する。
文言・ID・重みはシートの最新値を維持し、未登録の予備文へのフォールバックは廃止した。

## reaction_lines への集約

`condition_id` が発生条件、追加した `display_target` 列が表示先。既存行の空欄は `general` と同じ。
通常表示では専用の短文や約束名入りテンプレートを抽選しない。
条件・行のactiveとweightを反映し、ミニ莉央の出現回数・1日1回などの制限は従来どおり。

| 旧group_id（IDは維持） | condition_id | display_target | 件数 |
| --- | --- | --- | --- |
| home_routine_completed | routine_completed_just_now | general | 3 |
| home_all_completed | routine_all_completed | general | 3 |
| home_timer_finished | routine_timer_finished | general | 3 |
| blocked_struggling | prohibition_urge | general | 3 |
| blocked_defeated | prohibition_failed | general | 3 |
| home_peek_unfinished | routine_remaining | home_peek_unfinished | 5 |
| home_peek_unfinished_top | routine_remaining | home_peek_unfinished_top | 3 |
| home_idle_above | home_idle_tapped | home_idle_above | 2 |
| home_idle_above_routine | routine_remaining | home_idle_above | 2 |
| home_idle_right | routine_all_completed | home_idle_right | 2 |
| home_routine_added | routine_added | home_routine_added | 3 |

未達成の共通条件 `routine_remaining` と、約束追加・タイマー完走・放置中のタップの操作条件を追加。
既存の達成・禁止行動の条件は再利用する。操作条件は現在の操作IDにだけ反応し、過去の操作を再生しない。
`home_peek_unfinished_top` は1行・10文字以内・約束名なし。
`{routine_title}` は `home_routine_added` / `home_peek_unfinished` / `home_idle_above` でのみ使える。
編集はシート上で行い、IDを変えたりコードへ予備文を追加したりしない。

## 固定セリフの編集

| 列 | 編集方法 |
| --- | --- |
| `line_id` | アプリから参照する一意のID。既存のIDは変更しない |
| `group_id` | 使用場所・抽選グループ。既存行では変更しない |
| `text` | 本文。`[br]`で改行、`[sp]`で半角空白 |
| `weight` | 抽選の重み。0は対象外。固定案内では正の値なら表示 |
| `active` | チェックを外すと対象外 |
| `note` | 使用場所の説明。アプリには表示しない |

通知・約束の案内では `{routine_title}` を約束名に置換する。
ユーザーの入力した約束名そのものに含まれる `[br]` は改行として扱わない。

初回案内はIDで1件を指定。状況・操作に応じたセリフは `reaction_lines` の重み付き抽選。
お題は `challenge_カテゴリ名` のグループ。カテゴリ比率は既存のまま、カテゴリ内はweightで抽選する。
`challenge_intro` はお題表示前の固定セリフで、抽選対象のお題ではない。

候補を全件無効にしてもクラッシュしないが、固定案内が空欄になるため、必要な案内行は有効のまま本文を編集する。
アプリに日本語の予備文を再びハードコードせず、オフラインでは同梱済みのシート生成データを使う。

## 反映手順

シート編集 → `npm --prefix tools/scenario-sync run sync -- --write --save-snapshot` → ビルド・端末インストール。
アプリ起動時のオンライン自動取得ではない。すでに予約されている通知はアプリで再予約された時点で更新される。

ボタン名・説明文・「みんなのざこ速報」でユーザーが押す反応ラベルは莉央の発話ではないため対象外。
開発用サンプルシナリオ・テストのサンプル文も本番CMSの対象外。
