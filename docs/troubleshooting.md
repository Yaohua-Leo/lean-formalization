# Troubleshooting

Every entry below was observed on the authoring machine unless it says otherwise.
When you hit something new, add it here with the exact error text.

## The installer

**`install.ps1` / `install.sh` exits 2 with "no python interpreter found"**
Both launchers need a Python 3 interpreter (`python3`, `python` or `py` on PATH).
Follow `BOOTSTRAP.md` Appendix B to do the same writes by hand.

**`install.py: … is not a Lean project (no lean-toolchain); use --scope user`**
Project scope means "configure this Lean project". Run it from a Lean project root,
pass `--project <path>`, or use `--scope user` for a machine-wide install.

**A config file is JSON syntax I cannot parse**
The installer refuses to rewrite a file it cannot parse, and says which file and
why. Fix the syntax (or remove the file) and re-run. The exact snippet to add by
hand is in `docs/harness-matrix.md`.

**OpenCode has only `opencode.jsonc`**
JSONC comments cannot be round-tripped safely, so the installer reports it instead
of mangling the file. Add the `mcp` entry from `docs/harness-matrix.md` to the
`.jsonc` file yourself, or create a plain `opencode.json`.

**`opencode mcp list` says `Configuration is invalid … mcp.servers`**
The installed OpenCode is 1.x, which names servers directly under `mcp` and
requires `enabled: true`; the 2.x shape (`mcp.servers`) is rejected outright.
Re-run the installer (`--opencode-major 1` if `opencode --version` cannot be read);
it writes the matching shape and removes our own stale `mcp.servers` entries while
leaving servers you added there. Full shapes: `docs/harness-matrix.md`.

**`opencode mcp list` shows the server but with `✗ … EPERM: uv_spawn 'uvx'`**
That is OpenCode's health check being refused permission to spawn `uvx` — a
sandbox restriction on the process, not a configuration error. The server itself
starts fine; confirm with
`python verify/probe_mcp.py --command "uvx lean-lsp-mcp" …`.

**`opencode` fails outright with `EPERM: operation not permitted, uv_spawn 'git'`**
Observed when OpenCode is started inside a sandboxed shell in (or under) a git
repository: it walks up looking for the repository and is refused permission to
spawn `git`. Run it from a directory outside any git checkout, or start it
normally outside the sandbox. Not a configuration problem.

**I want to undo everything**
`python install/install.py --uninstall`. It restores every file it backed up,
deletes the files it created, and keeps `lean-formalization.json` (your config).
A file the user edited *after* installation is left in place and reported: deleting
it would destroy work.

## MCP servers

**`Failed to initialize cache at …: access denied (os error 5)`**
`uvx` cannot write its cache/tool directories — typical in a sandboxed shell. Either
run the installer with `--uv-cache-dir`/`--uv-tool-dir` pointing at writable paths,
or set those variables in the MCP server's `env` so the launching process inherits
them. (The DSH host itself launches MCP servers outside the session sandbox, so this
usually matters only for probes run from inside an agent's shell.)

**The tools do not appear in a new session**
1. Confirm the file was written: `python install/install.py --doctor`.
2. Confirm the server actually starts:
   `python verify/probe_mcp.py --harnesses`.
3. Confirm the harness restarted *after* the write (see Appendix A of
   `BOOTSTRAP.md`). A session created before the install will not pick the preset up.
4. Claude Code marks servers that come from a project `.mcp.json` as
   **"Pending approval"** — run `claude` once and approve it; this is Claude Code's
   own security gate, not a failed install.

**`gemini mcp …` hangs**
Observed on the authoring machine: the subcommand hung for 180 s in a
non-interactive shell. The installer writes `~/.gemini/settings.json` directly
instead. Verify with the stdio probe.

**Beam mode was not selected even though Beam is installed**
The detection probes, in order: `lean-beam-mcp` on PATH, `~/.local/bin/lean-beam-mcp`,
`<project>/tools/beam-mcp.ps1`, `<project>/tools/beam.ps1`. If your launcher is
somewhere else, add it to the `detect` list in `harnesses.json` — or set the mode by
re-running the installer from a shell where `lean-beam-mcp` is on PATH. The mode is
recorded in `lean-formalization.json`, so a stale value is visible rather than
silent.

**`lsp-fallback` was selected and now there is no goal tool**
That would be a bug: in fallback mode the installer explicitly *keeps* the
goal/diagnostic tools on `lean-lsp` and only disables `lean_build` and
`lean_run_code`. Check the `LEAN_MCP_DISABLED_TOOLS` value the configuration
records.

## Lean side

**`git: dubious ownership` + exit 128 before Lake builds anything**
`.lake/packages/*` belongs to a different OS account than the one running the build.
Grant `safe.directory` for that one invocation only, via `GIT_CONFIG_COUNT`,
`GIT_CONFIG_KEY_<i>` and `GIT_CONFIG_VALUE_<i>`. Do **not** rewrite ownership of the
dependency checkouts and do **not** edit the global git config. The scaffolded
`leancheck.ps1` does this when `gitSafeDirectories` is non-empty in
`lean-formalization.json`.

**`lean_local_search` is unavailable**
It needs `ripgrep` (`rg`) on PATH. Every other tool still works. The installer
reports `rg=missing` rather than installing a system package for you.

**`LeanAudit: no targets given; refusing to report an empty audit as success` (exit 2)**
`lean-formalization.json` still has `"targets": []`. Fill it with the declarations
you want audited — the gate deliberately will not turn "nothing to check" into a
PASS.

**`LeanAudit: not found in <lib>: <name>` (exit 1)**
The name is not in the built environment: wrong namespace, not imported by the
library, or the build is stale. Run `lake build` first.

**`<target> depends on axioms outside the whitelist: …`**
That is the gate doing its job. Either the axiom belongs in the project's
`allowedAxioms`, or the proof is using something it should not (a `sorry` shows up
as `sorryAx`).

**Beam's toolchain pin disagrees with the project's `lean-toolchain`**
Stop and report it. Reconfigure or reinstall Beam from
<https://github.com/leanprover/lean-beam>; do not edit the launcher to bypass the
check.

## Fetching this repository

Observed network behaviour on the authoring machine, and the reason
`BOOTSTRAP.md` step 1 has a ladder rather than one command:

| Command | Observed |
|---|---|
| `gh api repos/…` | works (authenticated transport) |
| `gh api …/contents/<path> -H "Accept: application/vnd.github.raw"` | works — this is what `BOOTSTRAP.md` recommends when cloning fails |
| `git -c http.sslBackend=openssl clone …` | works |
| plain `git clone https://…` | failed: `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS` |
| `curl https://github.com/…` | failed with the same schannel error |
| `curl https://raw.githubusercontent.com/…` | timed out |

If every path fails, say so — do not reconstruct the repository from memory.
