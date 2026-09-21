# Acceptance

This file records what was actually run to accept this package, and what each
check does and does not prove. It is a record, not a claim: if a command is not
listed here with its exit code, it was not run.

## The ladder

| # | Command | What it proves | What it does *not* prove |
|---|---|---|---|
| 1 | `node verify/validate_repo.mjs` | the adapter table's schema holds, the skills have valid frontmatter and kebab-case names, the vendored files match their recorded hashes, every documented file exists, the gate and DSH templates are still project-agnostic | that any harness reads any of it |
| 2 | `python verify/smoke.py` | install writes the expected surfaces into a throwaway home+project; every JSON/TOML file still parses; a second install writes nothing; user prose outside the block survives; uninstall removes what it created, restores what it changed, keeps a file the user edited, and leaves the project's own config alone | anything about a real harness instance |
| 3 | `python verify/smoke.py --with-gate` | additionally: the scaffolded `LeanAudit.lean` + `leancheck` really build a Lean project, refuse an empty target list, pass a whitelisted target, and fail a whitelist violation | that another project's gate should behave the same |
| 4 | `python verify/probe_mcp.py --harnesses` (or `--command …`) | the recorded command starts a real MCP server over stdio, `initialize` + `tools/list` succeed, and the expected tool names are present while the disabled ones are absent. `--harnesses` re-derives the command from `harnesses.json` and live detection; it reads no harness config file, so it does not show that a harness loaded anything | that a harness has loaded the configuration |
| 5 | `python install/install.py --doctor` | per-harness detection and file presence | nothing about runtime behaviour |
| 6 | the harness's own CLI (`claude mcp list`, `codex mcp list`, `opencode mcp list`, …) | that the harness **read** the file the installer wrote | that the user has approved it, that a *new session* picks it up, or that a model can call the tools |
| 7 | `python verify/check_gate_shell.py` | that the POSIX gate's embedded Python parses, that its config reader emits what the shell consumes, and that its whitelist check accepts/rejects correctly | that the surrounding **shell** logic runs — only a real bash can show that |

Steps 1–3 are deterministic and must exit 0. Step 4 needs network/`uv` (the Lean
LSP server is fetched by `uvx` on first use). Step 6 exists for as many harnesses
as can be asked non-interactively.

## What was run for this version

Results are recorded in `evidence/` next to this file, with the raw command output.
The summary at the time of publication:

| Check | Result |
|---|---|
| `node verify/validate_repo.mjs` | see `evidence/…/report.json` (tamper controls: editing a vendored skill **or** `licenses/lean-beam-LICENSE` now fails it) |
| `python verify/check_gate_shell.py` | both embedded Python blocks parse; the config reader emits the assignments the shell consumes; the whitelist check accepts a whitelisted target, rejects an out-of-whitelist axiom and a never-reported target, and writes `LATEST.md` |
| `python verify/smoke.py --with-gate` | see `evidence/…/report.json` — **16 checks, 0 failed** in the delivered run, incl. the OpenCode shape assertion, byte-level idempotence, the rendered DSH preset's contract and mode rows, a real Lean build, and a whitelist pass/fail pair |
| `python verify/probe_mcp.py --command "uvx lean-lsp-mcp" …` | 21 tools, expected names present, `lean_build`/`lean_run_code` absent |
| `claude mcp list` in the installed fixture | reported `lean-lsp: uvx lean-lsp-mcp` (pending approval) — the harness read the file |
| `CODEX_HOME=<tmp> codex mcp list` | `lean-lsp` row, status `enabled` — the harness read the file |
| `XDG_*=<tmp> opencode mcp list` | `✓ lean-lsp connected` — the harness read the file (delivered log; earlier runs inside a sandbox saw OpenCode refused permission to spawn `git`/`uvx`, which is why the step runs from a temp directory outside git) |
| `python verify/provenance_recheck.py` | a second, independent implementation of the vendored-hash check: 8/8 ledger rows recomputed and matching |
| `python install/install.py --doctor` | see `evidence/…/report.json` |
| Jordan project dry run | plan inspected, no write performed |

### Findings from the independent review of `98e981c`, and what changed

A reviewer who did not write this repository checked commit `98e981c` against a
`git archive` export of it. It confirmed claims 1, 3 and 7 outright and found the
following, all of which were fixed in the commit that carries this file:

| Finding | Fix |
|---|---|
| `gate/leancheck.sh` had a Python syntax error in its first heredoc, so the POSIX gate could never pass anything (static, not environmental) | repaired, and `verify/check_gate_shell.py` now parses **and runs** both embedded blocks; it is a required acceptance step |
| Mistral Vibe: the two servers collided on one `[mcp_servers]` table, so `lean-beam` was silently dropped in beam mode | array-of-tables support: one `[[mcp_servers]]` per server, matched by its `name` field; `tool_timeout_sec` is written too |
| The published evidence contained no raw `command-*.log` files (`.gitignore` swallowed them) while the docs pointed at them | `.gitignore` negates `evidence/**/*.log`; the current run's logs are committed |
| "a second run writes nothing" was false at byte level (both manifests were rewritten) | manifests are written only when their content changes; `smoke.py` now compares bytes |
| `install.py` printed a next step using `--from-harnesses`, a flag that does not exist | prints `--harnesses` |
| `--harnesses --env …` ignored `--env`, so the documented sandbox workaround did nothing there | `--env` now overrides the recorded env in that mode too |
| `licenses/lean-beam-LICENSE` was in the ledger but not enforced | the validator enforces every ledger row (tamper-controlled) |
| harness matrix documented a "status column" that no table had | the tier-1 table now carries a per-harness status column |
| "the exact command this harness's configuration records" overstated what `--harnesses` does | corrected in the matrix, `acceptance.md` and `BOOTSTRAP.md`: it re-derives the command, it reads no harness config |
| `DSH_HOME`/`DSH_AGENTS_HOME` overrode `--home`, so a scratch run could write into the real DSH home | with an explicit `--home`, both are derived from it |
| Vibe's `arrayOfTables`/`fields` and the beam `detect` entry described behaviour the code did not have | the code now consumes the TOML `fields` template, and the beam entry says what is actually checked |

The review is bound to `98e981c`; its verdicts do not automatically apply to later
commits. Residual unknowns it listed that this work does **not** resolve: no DSH
session was started, `lean-beam-mcp` is not installed here so Beam was never probed
end to end, `gemini mcp` / `code --add-mcp` / `vibe` were never run, and the shell
wrapper of `leancheck.sh` still needs a real bash to exercise.

## Second independent review — `ac8b51d` (the delivered version)

A second reviewer worked from a frozen `git archive` export of `ac8b51d` and
re-ran everything itself (installs into throwaway homes, a real Lean build, the
std.io probe, its own heredoc extractor and tamper controls). Verdicts:

- **All eight fix claims: `fixed`** — gate heredocs parse and behave; Vibe writes
  two `[[mcp_servers]]` blocks with no duplicates across three runs; manifests and
  a 126-file recursive hash snapshot are byte-identical across runs; the printed
  next step is `--harnesses`; `--harnesses --env` genuinely applies the overrides
  (uv visibly populated the scratch cache); license and skill tamper controls both
  exit 1; an explicit `--home` keeps a scratch run out of the real DSH home; a
  missing `fields` template fails the validator.
- **Sanity reruns: all exit 0** — `validate_repo.mjs`, `smoke.py --with-gate`
  (16 checks, real Lean build, gate exit 2/0/1 trio), `--doctor`.

Its nine residual findings were documentation-level; each is addressed in the
commit that carries this file:

| Finding (ac8b51d) | Resolution |
|---|---|
| `acceptance.md` said "13 checks"; the delivered log says 16 | corrected |
| OpenCode health check described as `EPERM uv_spawn`; the delivered log shows `✓ lean-lsp connected` (the old EPERM was a `chdir`, from a different run) | corrected in matrix + acceptance, with the log named |
| "a second run writes nothing, byte for byte" did not hold for the tier-2 Vibe path (file rewritten per server, a new backup stamp per run) | array-of-tables is now planned as ONE action: three consecutive runs leave `config.toml` byte-identical with zero backup stamps |
| "tier-2 is written only with `--include-unverified`" ignored the `--harnesses` force path | wording corrected in both READMEs and the matrix |
| matrix listed `~/.claude/skills` as an OpenCode install root, against `harnesses.json` | reworded: upstream compat root, deliberately not written (the claude-code row covers it) |
| the DSH preset "parses (19/20 rows)" claim had no committed log | `smoke.py` now asserts the rendering (contract + mode rows) in the committed ladder; the js-yaml parse is attributed as a manual authoring-machine check |
| the independent provenance re-check had no `command-*.log` | promoted to a required ladder step: `verify/provenance_recheck.py` |
| `BOOTSTRAP.md` still pointed the DSH preset at `$DSH_HOME` unconditionally | notes the `--home` derivation |
| `AGENTS.md` overstated what the validator enforces | reworded: ledger rows + template presence are enforced; prose paths in `docs/` are not |

Not run, and therefore `unknown`:

- any run against Windsurf, Cline, Aider, Amp, Zed, Goose, Vibe (not installed on
  the authoring machine);
- Gemini CLI's own listing: with `HOME`/`USERPROFILE` pointed at a scratch install
  the CLI read that path and then refused to continue without credentials
  (`Please set an Auth method in … or specify GEMINI_API_KEY …`). Authenticating a
  user's account is not the installer's job, so the written `settings.json` is only
  checked for JSON validity;
- Cursor and VS Code were not restarted, and DSH was not given a new session, so no
  harness-level confirmation exists for those three;
- `gate/leancheck.sh` — Git Bash cannot start in the authoring environment
  (`couldn't create signal pipe, Win32 error 5`), so the POSIX gate is shipped
  unverified. Its PowerShell twin is verified by step 3;
- a real install into the authoring user's live home directory and Jordan project.
  The plan was produced with `--dry-run` and inspected; executing it is the user's
  call. Note that `D:\the_bible_of_Jordan` is **not** a Lean project root today (no
  `lean-toolchain`/`lakefile` at its root), so if it is the intended target, the
  installer must be pointed at the directory that holds the Lake project.

## Evidence layout

```
evidence/<UTC timestamp>-<short id>/
  report.md          readable summary
  report.json        machine-readable results
  command-*.log      raw stdout/stderr of each command
```

Rules taken from the contract and applied here too: record real commands and real
exit codes; write `unknown` for anything not observed; append — never erase —
failed and corrected records; and do not let the agent that produced an artifact
sign off on it (see `docs/harness-matrix.md` for which claims are user-visible).

## Reproducing

```bash
git clone https://github.com/Yaohua-Leo/lean-formalization.git
cd lean-formalization
node verify/validate_repo.mjs
python verify/smoke.py --with-gate          # needs elan/lake with v4.34.0 available
python verify/probe_mcp.py --harnesses      # needs uv; add --env UV_CACHE_DIR=… if sandboxed
python install/install.py --doctor
```

The Lean fixture used by the smoke test pins `leanprover/lean4:v4.34.0` and has no
dependency other than the toolchain, so it builds in seconds once that toolchain is
present. If it is not, either install it
(`elan toolchain install leanprover/lean4:v4.34.0`) or run the smoke test without
`--with-gate`.
