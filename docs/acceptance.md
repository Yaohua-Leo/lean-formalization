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
| 4 | `python verify/probe_mcp.py --harnesses` | the exact command recorded in the configuration starts a real MCP server over stdio, `initialize` + `tools/list` succeed, and the expected tool names are present while the disabled ones are absent | that a harness has loaded the configuration |
| 5 | `python install/install.py --doctor` | per-harness detection and file presence | nothing about runtime behaviour |
| 6 | the harness's own CLI (`claude mcp list`, …) | that the harness **read** the file the installer wrote | that the user has approved it, or that a model can call the tools |

Steps 1–3 are deterministic and must exit 0. Step 4 needs network/`uv` (the Lean
LSP server is fetched by `uvx` on first use). Step 6 exists for as many harnesses
as can be asked non-interactively.

## What was run for this version

Results are recorded in `evidence/` next to this file, with the raw command output.
The summary at the time of publication:

| Check | Result |
|---|---|
| `node verify/validate_repo.mjs` | see `evidence/…/report.json` |
| `python verify/smoke.py --with-gate` | see `evidence/…/report.json` |
| `python verify/probe_mcp.py --command "uvx lean-lsp-mcp" …` | 21 tools, expected names present, `lean_build`/`lean_run_code` absent |
| `claude mcp list` in the installed fixture | reported `lean-lsp: uvx lean-lsp-mcp` (pending approval) — the harness read the file |
| `python install/install.py --doctor` | see `evidence/…/report.json` |
| Jordan project dry run | plan inspected, no write performed |

Not run, and therefore `unknown`:

- any run against Windsurf, Cline, Aider, Amp, Zed, Goose, Vibe (not installed on
  the authoring machine);
- `gate/leancheck.sh` — Git Bash cannot start in the authoring environment
  (`couldn't create signal pipe, Win32 error 5`), so the POSIX gate is shipped
  unverified. Its PowerShell twin is verified by step 3;
- `opencode mcp list` — OpenCode failed to start under the authoring sandbox
  (`Unknown: FileSystem.open (…opencode.log)`), so no harness-level check exists
  for the OpenCode row;
- a real install into the authoring user's live home directory and Jordan project.
  The plan was produced with `--dry-run` and inspected; executing it is the user's
  call.

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
