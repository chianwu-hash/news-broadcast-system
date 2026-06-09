# Agent Handoff

這是 Codex、Claude Code、使用者共同使用的交接文件。
任何 agent 接手任務前，先讀這份文件。
任何重要狀態，不只寫在聊天裡，也要寫在這份文件裡。

## Current Goal

No active handoff.

## Current State

- 最後更新日期：2026-04-15 16:01 CST by Codex
- 目前焦點：`question-bank-wayground-workflow` 已安裝到 `cian` repo root，`package.json` 已建立，安裝結果已 commit + push。

### Wayground Skill 化盤點

**Standalone repo**
- 路徑：`/tmp/question-bank-wayground-workflow-export/`（同步至 GitHub `chianwu-hash/question-bank-wayground-workflow`）
- git 狀態：`## main...origin/main`，working tree clean
- 最新 commit：`0ee78a8 fix: add skills/ copy to install-module.ps1 (Windows parity with .sh)`

**完成項目（evidence 確認）：**

| 項目 | 狀態 | Evidence |
|---|---|---|
| `SKILL.md` | ✅ 完成 | `./references/` 路徑 19 處，無任何 `../../` 依賴 |
| `skills/question-bank-wayground/references/` | ✅ 完成 | 含 11 份文件：README、END_TO_END_FLOW、SOP×3、quality-spec、routing、tooling、troubleshooting + prompts/ |
| `troubleshooting.md` in references/ | ✅ 完成 | `ls references/ | grep trouble` → 存在 |
| `agents/openai.yaml` | ✅ 完成 | 含 display_name、short_description、default_prompt |
| `lib/browser.js` 抽出 | ✅ 完成 | `automation/lib/browser.js` 存在，所有腳本已使用 |
| `install-module.sh` 複製 skills/ | ✅ 完成 | line 62：`cp -R "$module_root/skills/." "$target_root/skills/"` |
| `install-module.ps1` 複製 skills/ | ✅ 完成 | lines 71–73：`Copy-Item -Path ... skills\* -Recurse -Force` |
| 推送至 GitHub | ✅ 完成 | `git remote -v` → `git@github.com:chianwu-hash/question-bank-wayground-workflow.git` |
| Cian 快照同步 | ✅ 完成 | `tools/question-bank-wayground-workflow/skills/question-bank-wayground/SKILL.md` diff standalone → IDENTICAL |

**尚未完成 / 待決定：**

| 項目 | 狀態 | 說明 |
|---|---|---|
| `codex-skill-plan.md` 進度備註過時 | ✅ 已更新 | Codex 已在 standalone repo 修正並同步回 cian snapshot |
| Cian 根目錄未安裝 skill | ⚠️ 待決定 | `cian/skills/` 不存在；`cian/automation/*.js` 不存在（腳本在 `tools/` 內，未安裝到 cian 根目錄）|
| Cian 無 package.json | ⚠️ 待決定 | cian 無 `package.json`，npm 腳本無法使用 |
| `references/` vs `docs/workflow/` 重複 | ℹ️ 接受 | 設計上接受此重複；更新文件時需同步兩處 |

更新：2026-04-15 15:52，Codex 已依 handoff 與使用者確認執行 root install。`cian/skills/`、`cian/automation/*.js`、`cian/docs/workflow/`、`cian/templates/`、`cian/project.config.md`、`cian/PACKAGE_SCRIPTS_SNIPPET.question-bank-wayground.json` 已建立。

**Cian 安裝狀態說明：**

```
cian/
  tools/question-bank-wayground-workflow/   ← 模組快照（含 skills/）
    skills/question-bank-wayground/         ← skill 在這裡
    automation/*.js                         ← 腳本在這裡
  automation/
    output/                                 ← 只有 output/，無腳本
  skills/                                   ← 不存在
```

若要讓 Codex 在 cian 專案中觸發 skill，需先執行：
```bash
bash tools/question-bank-wayground-workflow/scripts/install-module.sh /home/vboxuser/projects/cian
```
但**是否執行需請示使用者**，因為 install 會在 cian 根目錄建立新目錄與檔案。

## File Ownership

- Codex: `docs/development/agent-handoff.md`
- Claude Code: requested to review install strategy only; no file ownership yet
- User: existing unrelated working tree changes

若可能同時工作，必須先登記 File Ownership，避免改到同一批檔案。

## Codex Notes

- Codex 會用實際檔案、`rg`、`git status`、`git diff`、驗證指令來確認資訊。
- Codex 接手任務前會先讀本文件，再讀 `CLAUDE.md`、`SHARED.md` 與任務相關 docs。
- Codex 承諾只 stage 與任務相關檔案，不提交無關未追蹤檔。
- Codex 不會任意覆蓋 Claude Code 或使用者改動。
- 若 Codex 不同意 Claude Code 的判斷，會附上 evidence，例如檔案路徑、行為差異、命令輸出或 git diff。
- 若發現衝突，Codex 會先在本文件記錄 evidence，再請使用者或下一個 agent 決定。

## Claude Notes

- Claude Code 應用實際檔案、`grep` / `rg`、關鍵函式名稱、git diff 或驗證指令回報 evidence。
- Claude Code 不應要求 Codex 讀聊天歷史；需要 Codex 接手時，請把下一步寫在本文件。
- Claude Code 完成交接時應列出已驗證項目與待驗證項目。
- 若資訊可能過時，請標記為「待驗證」。
- 若 Claude Code 與 Codex 判斷不同，先比對實際檔案與 evidence，不直接否定對方。

## Verification Log

2026-04-15 15:16
Agent: Codex
Checked: Existing collaboration docs and project entry docs.
Result: Found existing `CLAUDE.md`, `SHARED.md`, and `README.md`; no existing `AGENTS.md` or `docs/development/agent-handoff.md` in this repo.
Evidence: `find .. -maxdepth 3 (...)` returned `../news-broadcast-system/CLAUDE.md`; direct reads of `CLAUDE.md`, `SHARED.md`, and `README.md`.

2026-04-15 (Claude Code, VSCode session)
Checked: Wayground skill-ification status across standalone repo and cian snapshot.
Commands run:
  - `ls /tmp/question-bank-wayground-workflow-export/skills/question-bank-wayground/` → SKILL.md, references/, agents/
  - `ls references/` → 11 files including troubleshooting.md
  - `grep -c "\./references/" SKILL.md` → 19 (no ../../ deps)
  - `cat agents/openai.yaml` → display_name, short_description, default_prompt present
  - `diff standalone/SKILL.md cian/.../SKILL.md` → IDENTICAL
  - `grep -n "skills" install-module.sh` → line 62 copies skills/
  - `ls cian/skills/` → NOT FOUND
  - `ls cian/automation/` → only output/ (no .js scripts)
  - `ls cian/package.json` → NOT FOUND
  - `git log --oneline -7` (standalone) → clean, latest commit is install-module.ps1 fix
Result: Skill 完成度高，standalone + cian 快照均已同步。唯一缺口：cian 根目錄尚未執行 install，skill 不在 cian/skills/，codex-skill-plan.md 有一個過時的「尚未完成」備註。

2026-04-15 15:42
Agent: Codex
Checked: Claude Code Wayground skill handoff claims against standalone repo and cian snapshot.
Result: Claude Code's claims were mostly correct. `codex-skill-plan.md` had an outdated troubleshooting item; Codex updated it in standalone repo and synced it back to cian snapshot. Standalone latest commit: `4731c81 docs: update skill progress after troubleshooting reference`. Cian latest commit: `8d902d8 docs: sync Wayground skill progress`.
Evidence: `ls skills/question-bank-wayground/references/ | grep trouble` returned `troubleshooting.md`; `grep -n "troubleshooting\\|目前尚未完成" docs/codex-skill-plan.md` showed the stale item before patch; `diff -u /tmp/question-bank-wayground-workflow-export/docs/codex-skill-plan.md /home/vboxuser/projects/cian/tools/question-bank-wayground-workflow/docs/codex-skill-plan.md` returned no diff after sync.

2026-04-15 15:46
Agent: Codex
Checked: Actual `install-module.sh` behavior and current `cian` root state before deciding whether to install.
Result: Direct install would not delete files, but it would create root-level `automation/*.js`, `automation/lib/`, `docs/workflow/`, `docs/references/`, `templates/`, `wayground/`, `skills/`, and `PACKAGE_SCRIPTS_SNIPPET.question-bank-wayground.json`. It would overwrite same-named files in those target locations. Current `cian/automation/` appears to contain only `output/` artifacts, so immediate conflict looks low, but root install may still make `cian` more cluttered.
Evidence: `/home/vboxuser/projects/cian/tools/question-bank-wayground-workflow/scripts/install-module.sh` uses `cp` / `cp -R` into root-level target folders; `find automation docs skills templates wayground -maxdepth 3 ...` in `cian` showed `automation/output/*` only among those roots; `git -C /home/vboxuser/projects/cian status -sb` still shows unrelated untracked files.

2026-04-15 15:52
Agent: Codex
Checked: Preview install and root install of `question-bank-wayground-workflow` into `cian`.
Result: Preview install succeeded in `/tmp/cian-install-preview`; root install completed in `/home/vboxuser/projects/cian`. Key files now exist: `skills/question-bank-wayground/SKILL.md`, `automation/wayground-import-from-bank.js`, `PACKAGE_SCRIPTS_SNIPPET.question-bank-wayground.json`, and `docs/workflow/DEPLOYMENT_CHECKLIST.md`.
Evidence: `test -f skills/question-bank-wayground/SKILL.md && echo skill-ok`; `test -f automation/wayground-import-from-bank.js && echo automation-ok`; `test -f PACKAGE_SCRIPTS_SNIPPET.question-bank-wayground.json && echo snippet-ok`; `test -f docs/workflow/DEPLOYMENT_CHECKLIST.md && echo workflow-docs-ok`.

2026-04-15 16:01
Agent: Codex
Checked: `cian` package setup, staged install scope, syntax checks, commit and push.
Result: Created root `package.json` with Wayground scripts and Playwright devDependency, staged only root install/module files, committed and pushed to `chianwu-hash/cian`.
Evidence: `node -e "JSON.parse(...package.json...)"` returned `json-ok`; `for f in automation/*.js automation/lib/*.js; do node --check "$f"; done` passed; commit `db9b763 Install Wayground workflow skill at project root` pushed `8d902d8..db9b763 main -> main`.

## Next Action

No pending action.

Optional user decision:

No pending action.

---

### Claude Code 建議（2026-04-15，VSCode session）

**建議：Option 4（暫不 root install）+ 一個前提確認**

**Evidence：**
- `cian/automation/output/` 已有真實 output：`wayground-generated-check.md`、`wayground-imported-from-bank.json`、`browser-smoke.png` 等 → 流程 IS 在跑，且可用
- `cian/automation/question-banks/` 不存在 → 題庫可能存在其他路徑（待驗證），或流程是從 tools/ 子目錄執行後再手動搬移
- `cian/skills/` 不存在，`cian/package.json` 不存在
- `cian/` 根目錄只有：`automation/`、`g8s2/`、`tools/`、`scripts/`、`index.html`、`Makefile` 等 — 結構簡潔

**判斷：**

| 問題 | 現況 | 影響 |
|---|---|---|
| 腳本能不能執行 | ✅ 可用（從 tools/ 跑） | 低，不影響日常使用 |
| npm script 快捷方式 | ❌ 無 package.json | 低，手動 `node automation/xxx.js` 可替代 |
| Codex skill 在 cian 自動觸發 | ❌ skills/ 不在根目錄 | **中**，若使用者要在 cian 裡用 `/question-bank-wayground` 指令才有影響 |

**結論：**

若使用者 **不需要** 在 cian 裡讓 Codex 自動觸發 skill，Option 4 最佳 — 現狀可用，不需 root install。

若使用者 **需要** Codex 在 cian 裡自動辨識 skill，再執行：
```bash
# 先 preview，不動 repo
bash tools/question-bank-wayground-workflow/scripts/install-module.sh /tmp/cian-install-preview
ls /tmp/cian-install-preview/skills/question-bank-wayground/SKILL.md
# 確認無衝突後，使用者同意才執行 root install
```

**不建議** Option 2（加 --dry-run flag）— 工程量大，現有 preview 方式已夠用。

**使用者確認（2026-04-15）：**
> 使用者確認會在 cian 裡對 Codex 說「幫我出二段自然第三章20題」這類指令。
> → 需要 skill 在 cian 根目錄自動觸發。**請執行 root install。**

## Handoff Template

每次正式交接時，使用以下格式：

```text
Date:
From:
To:

Goal:

Changed Files:

Files Intentionally Not Touched:

Current Findings:

Validation Done:

Validation Still Needed:

Risks / Open Questions:

Requested Next Action:
```
