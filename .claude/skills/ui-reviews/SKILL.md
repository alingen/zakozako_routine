---
name: ui-review
description: ざこざこルーティンのUI/UXを商用アプリ品質の観点からレビューする
---

# UI Review

UIレビューでは、実装を変更する前に必ず現在の画面を確認する。

以下の順番で評価する。

1. Visual hierarchy
2. spacing
3. alignment
4. typography
5. color / contrast
6. component consistency
7. tap target / affordance
8. information density
9. character presence
10. commercial polish
11. AI-generated-looking design
12. device-size robustness

問題は以下で分類する。

- Critical
- High
- Medium
- Low

各問題について、

- 現状
- 問題
- 改善方法
- 関連ファイル

を示す。

レビュー段階ではコードを変更しない。

ユーザーが修正を指示した場合のみ変更する。

修正時は新しい装飾を追加するより、
余白・サイズ・配置・階層・統一性を優先する。
