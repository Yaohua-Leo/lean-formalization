# lean-formalization

A Lean 4 formalization assistant you install by pasting a link: it puts the same
contract, the same skills, the same Lean MCP servers and a working axiom gate into
whichever coding agent you use.

```text
https://github.com/Yaohua-Leo/lean-formalization  —  become this Lean formalization assistant
```

Paste that into any agent that can read files and run commands. It follows
[`BOOTSTRAP.md`](BOOTSTRAP.md): fetches this repository, detects what is installed,
shows its plan, writes the configuration, probes the MCP servers, and tells you
which agent needs a restart.

## What you get

| | |
|---|---|
| **A contract** | the always-on rules injected into your agent's instruction file: never deliver a `sorry`/`admit`/custom `axiom`, never change a statement to make it compile, one tactic at a time, three routes per target, report real exit codes, never self-accept. See [`contract.md`](contract.md). |
| **Two skills** | `lean-formalization` (routes work between live proof state, library search and the deterministic gate) and `lean-beam` (Lean Beam's own skill, vendored at a pinned commit). |
| **Lean MCP servers** | `lean-lsp-mcp` always; `lean-beam` when a Beam launcher is detected. In that case the tools Beam owns are switched off on the LSP server so exactly one server owns each capability. |
| **A project gate** | `LeanAudit.lean` + `scripts/leancheck.*` + an `evidence/` layout in your Lean project: deterministic build, per-declaration axiom audit, whitelist enforcement, evidence written per run. |
| **Nine upstream skills** | `lean-proof`, `lean-setup`, `mathlib-build`, `mathlib-pr`, `mathlib-review`, `lean-bisect`, `lean-mwe`, `lean-pr`, `nightly-testing` — installed by `leanprover/skills`' own per-harness installers, never re-vendored here. |

## Install

```bash
git clone https://github.com/Yaohua-Leo/lean-formalization.git
cd lean-formalization
python install/install.py --project /path/to/your/lean/project --scope both --dry-run   # read the plan
python install/install.py --project /path/to/your/lean/project --scope both             # do it
python verify/probe_mcp.py --harnesses --project /path/to/your/lean/project             # assert it works
```

`install.ps1` and `install.sh` are thin launchers for the same Python installer, so
the PowerShell and POSIX paths cannot drift apart.

Idempotent: running it twice writes nothing the second time. Reversible:
`--uninstall` restores every backup and deletes only what it created.

## Harnesses

Tier 1 = the configuration paths were verified on the authoring machine (by local
inspection, by each harness's own documentation, and by the stdio probe). Tier 2 =
shipped but not verified end-to-end; written only with `--include-unverified`.
The full table, with the provenance of every path, is in
[`docs/harness-matrix.md`](docs/harness-matrix.md).

| Tier | Harness | Instructions | Skills | MCP |
|---|---|---|---|---|
| 1 | DSH (DeepSeek Harness) | preset persona | `~/.agents/skills`, project roots | rendered preset |
| 1 | Claude Code | `~/.claude/CLAUDE.md`, `CLAUDE.md` | `~/.claude/skills`, `.claude/skills` | `.mcp.json` |
| 1 | Codex CLI | `~/.codex/AGENTS.md`, `AGENTS.md` | `~/.codex/skills` | `~/.codex/config.toml` |
| 1 | OpenCode | `~/.config/opencode/AGENTS.md`, `AGENTS.md` | 4 roots incl. `~/.agents/skills` | `mcp.<name>` on 1.x, `mcp.servers` on 2.x (probed) |
| 1 | Gemini CLI | `~/.gemini/GEMINI.md`, `GEMINI.md` | `~/.gemini/skills` | `~/.gemini/settings.json` |
| 1 | Cursor | `AGENTS.md`, `.cursor/rules/*.mdc` | `~/.cursor/skills`, `.cursor/skills` | `~/.cursor/mcp.json` |
| 1 | VS Code / Copilot | `AGENTS.md`, `.github/copilot-instructions.md` | — | `.vscode/mcp.json` |
| 2 | Mistral Vibe | — | — | `~/.vibe/config.toml` |
| 2 | any AGENTS.md-aware agent | `AGENTS.md` | `.agents/skills` | use the agent's own `mcp add` |

This repository does not include guessed config paths for Windsurf, Cline, Aider,
Amp, Zed or Goose: a wrong path writes a file that silently does nothing. Adding
one is a four-step procedure documented in `docs/harness-matrix.md`.

## The gate

The installer scaffolds the acceptance pipeline into your Lean project, and reads
everything project-specific from `lean-formalization.json`:

```bash
pwsh -File scripts/leancheck.ps1         # Windows
bash scripts/leancheck.sh                # POSIX (shipped, not yet verified)
```

It runs `lake --no-cache build`, then `lake env lean --run LeanAudit.lean <lib> -- <targets>`,
then checks every reported declaration's axioms against `allowedAxioms`
(`propext`, `Classical.choice`, `Quot.sound` by default). Evidence lands in
`evidence/lean/runs/<UTC stamp>-<id>/`; `LATEST.md` is navigation only — history is
appended, never erased. It refuses to report success on an empty `targets` list, so
"nothing to check" can never look like a pass.

This is the only authority for *mathematics*: MCP output, a compiling file, or a
green checkpoint never replace the build, the audit and an independent reader.

## Verify it yourself

```bash
node verify/validate_repo.mjs        # schema, skills, vendored hashes, templates
python verify/smoke.py --with-gate   # install → assert → idempotent → uninstall, plus a real Lean build
python install/install.py --doctor   # per-harness detection and file presence
```

[`docs/acceptance.md`](docs/acceptance.md) states which of these were run for this
version, and — explicitly — what was **not** run and is therefore `unknown`.

## Requirements

`git`, and either `python3` (for the installer and the gate's POSIX path), plus
`uv` (for `lean-lsp-mcp`), `elan`/`lake` (for any Lean build), and ideally `ripgrep`
(for `lean_local_search`). Beam is optional; without it the assistant runs in
`lsp-fallback` mode rather than losing its proof-state tools.

## Credits and license

MIT for this repository's own files (`LICENSE`). Lean Beam's skill and license are
vendored under Apache-2.0; `lean-lsp-mcp` (MIT) and `leanprover/skills`
(Apache-2.0) are used, not bundled. See [`NOTICE`](NOTICE) and
[`skills/PROVENANCE.md`](skills/PROVENANCE.md) — every vendored byte is recorded
there with its hash, and `validate_repo.mjs` fails if one of them changes.
