# lean-formalization

一套「把链接粘给 agent 就能装好」的 Lean 4 形式化助手：同一份契约、同一组技能、
同一套 Lean MCP 服务器和一条真正会拦人的公理验收门槛，装进你正在用的那个编码 agent。

```text
https://github.com/Yaohua-Leo/lean-formalization —— 把你设置成这个 lean 形式化助手
```

把上面这句发给任意能读文件、能跑命令的 agent。它会照 [`BOOTSTRAP.md`](BOOTSTRAP.md)
执行：拉取仓库 → 探测本机装了什么 → 先打印计划 → 写配置 → 探针断言 MCP 工具真的存在
→ 告诉你哪个 agent 需要重启。

## 你会得到什么

| | |
|---|---|
| **一份契约** | 常驻注入 agent 指令文件（及 DSH preset 的 persona）：不得交付仍在 `sorry`/`admit`/自定义 `axiom`/报错状态的证明；不得为过编译改定义、假设、量词或结论；一次一条 tactic；每个目标最多三条实质不同路线；报告真实命令与退出码；不得自我验收。全文见 [`contract.md`](contract.md) |
| **两个技能** | `lean-formalization`（在实时证明状态、库检索、确定性门槛之间做路由）与 `lean-beam`（Lean Beam 官方技能，按固定提交 vendor） |
| **Lean MCP 服务器** | 始终挂 `lean-lsp-mcp`；检测到 Beam 启动器时改挂 `lean-beam`，并把 Beam 已负责的工具在 LSP 侧关掉——每个能力只有一个归属 |
| **项目验收门槛** | 在你的 Lean 项目里生成 `LeanAudit.lean`、`scripts/leancheck.*` 与 `evidence/` 目录：确定性构建、逐声明公理审计、白名单校验、每次运行留证 |
| **九个上游技能** | `lean-proof`、`lean-setup`、`mathlib-build`、`mathlib-pr`、`mathlib-review`、`lean-bisect`、`lean-mwe`、`lean-pr`、`nightly-testing`——由上游 `leanprover/skills` 自己的安装器安装，本仓库不复制 |

## 安装

```bash
git clone https://github.com/Yaohua-Leo/lean-formalization.git
cd lean-formalization
python install/install.py --project /你的/lean/项目 --scope both --dry-run   # 先看计划
python install/install.py --project /你的/lean/项目 --scope both             # 真正执行
python verify/probe_mcp.py --harnesses --project /你的/lean/项目             # 探针断言
```

`install.ps1` 与 `install.sh` 只是同一个 Python 安装器的薄启动器，所以 PowerShell
与 POSIX 两条路不会各自漂移。

幂等：第二次运行逐字节不写任何东西。可回滚：`--uninstall` 恢复全部备份，只删除自己创建过的
文件，你后来改过的文件会留在原处并报告出来。

## 支持的 harness

Tier 1 = 配置路径在作者机器上核对过（本地检查 / 厂商文档 / stdio 探针）。Tier 2 =
随仓库发布但未端到端实测，只有加 `--include-unverified` 或在 `--harnesses` 里点名才会写。
每条路径的出处与逐 harness 的实测状态列见 [`docs/harness-matrix.md`](docs/harness-matrix.md)。

| Tier | Harness | 指令文件 | 技能根 | MCP |
|---|---|---|---|---|
| 1 | DSH（DeepSeek Harness） | preset persona | `~/.agents/skills` 与项目根 | 渲染后的 preset |
| 1 | Claude Code | `~/.claude/CLAUDE.md`、`CLAUDE.md` | `~/.claude/skills`、`.claude/skills` | `.mcp.json` |
| 1 | Codex CLI | `~/.codex/AGENTS.md`、`AGENTS.md` | `~/.codex/skills` | `~/.codex/config.toml` |
| 1 | OpenCode | `~/.config/opencode/AGENTS.md`、`AGENTS.md` | 4 个根，含 `~/.agents/skills` | 1.x 用 `mcp.<名>`，2.x 用 `mcp.servers`（自动探测） |
| 1 | Gemini CLI | `~/.gemini/GEMINI.md`、`GEMINI.md` | `~/.gemini/skills` | `~/.gemini/settings.json` |
| 1 | Cursor | `AGENTS.md`、`.cursor/rules/*.mdc` | `~/.cursor/skills`、`.cursor/skills` | `~/.cursor/mcp.json` |
| 1 | VS Code / Copilot | `AGENTS.md`、`.github/copilot-instructions.md` | — | `.vscode/mcp.json` |
| 2 | Mistral Vibe | — | — | `~/.vibe/config.toml` |
| 2 | 任何读 AGENTS.md 的 agent | `AGENTS.md` | `.agents/skills` | 用该 agent 自带的 `mcp add` |

本仓库**不**为 Windsurf、Cline、Aider、Amp、Zed、Goose 猜配置文件路径：写错路径等于写了一个
静默无效的文件。要新增一条，按 `docs/harness-matrix.md` 里写的四步来。

## 验收门槛

安装器会把验收流水线搭进你的 Lean 项目，项目相关内容全部从 `lean-formalization.json` 读取：

```bash
pwsh -File scripts/leancheck.ps1         # Windows
bash scripts/leancheck.sh                # POSIX（已发布，但尚未实测）
```

依次执行 `lake --no-cache build` → `lake env lean --run LeanAudit.lean <库> -- <目标…>`
→ 逐声明把公理与 `allowedAxioms`（默认 `propext`、`Classical.choice`、`Quot.sound`）比对。
证据写到 `evidence/lean/runs/<UTC 时间戳>-<id>/`；`LATEST.md` 只是导航副本，
历史只追加不抹除。目标列表为空时它**拒绝**报成功——「没东西可查」永远不会伪装成通过。

数学上唯一的权威是这条链路：MCP 输出、能编译的文件、绿色 checkpoint 都不能替代构建、
公理审计和独立读者的比对。

## 自己验一遍

```bash
node verify/validate_repo.mjs        # schema、技能、vendor 哈希、模板
python verify/smoke.py --with-gate   # 安装→断言→幂等→卸载，外加一次真实 Lean 构建
python install/install.py --doctor   # 逐 harness 探测与文件存在性
```

哪些检查在本版本真跑过、哪些**没跑**因而标为 `unknown`，写在 [`docs/acceptance.md`](docs/acceptance.md)。

## 依赖

`git`；安装器与 POSIX 门槛需要 `python3`；`uv`（`lean-lsp-mcp` 需要）、`elan`/`lake`
（任何 Lean 构建需要），建议装 `ripgrep`（`lean_local_search` 需要）。Beam 可选：
没有 Beam 时进入 `lsp-fallback` 模式，而不是失去证明状态工具。

## 许可与出处

本仓库自有内容为 MIT（`LICENSE`）。Lean Beam 的技能与许可证按 Apache-2.0 vendor；
`lean-lsp-mcp`（MIT）与 `leanprover/skills`（Apache-2.0）是「使用」而非「打包」。
见 [`NOTICE`](NOTICE) 与 [`skills/PROVENANCE.md`](skills/PROVENANCE.md)——每个 vendor
字节都带哈希记录，`validate_repo.mjs` 会在任何一条被改动时失败。
