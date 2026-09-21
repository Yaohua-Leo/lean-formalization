# Harness matrix

`harnesses.json` is the machine-readable source of this table; this document
explains what each row means, where each path came from, and — honestly — what was
and was not verified.

## How to read the status column

| Status | Meaning |
|---|---|
| **verified (files)** | the installer's writes were executed and asserted on the authoring machine (temp home + fixture project), and every config file still parses |
| **verified (MCP)** | the exact command this harness's configuration records was launched over stdio, `initialize` + `tools/list` succeeded, and the expected tool names were present/absent (`verify/probe_mcp.py`) |
| **harness-reads-it** | the harness's own CLI listing confirmed it read the written configuration |
| **unverified** | the path/format comes from documentation or convention only. Nothing was run against that harness |

**A file being present is not proof that a harness loaded it.** Where the "harness
reads it" column is empty, treat the installation as *configured but unconfirmed*
until the user starts a new session in that harness.

## Tier 1 — verified on the authoring machine

| Harness | Instruction file(s) | Skill roots | MCP configuration | Config format |
|---|---|---|---|---|
| DSH (DeepSeek Harness) | rendered preset (`persona.prefix`) | `<agents>/skills`, `<DSH_HOME>/skills`, `<project>/.agents/skills`, `<project>/.dsh/skills` | `<DSH_HOME>/.agent-presets/lean/agent.cordis.yml` | YAML rows, two `dsh-mcp-client` rows |
| Claude Code | `~/.claude/CLAUDE.md`, `<project>/CLAUDE.md` | `~/.claude/skills`, `<project>/.claude/skills` | `<project>/.mcp.json` | JSON, `mcpServers` |
| Codex CLI | `~/.codex/AGENTS.md`, `<project>/AGENTS.md` | `~/.codex/skills` | `~/.codex/config.toml` | TOML, `[mcp_servers.<name>]` |
| OpenCode | `~/.config/opencode/AGENTS.md`, `<project>/AGENTS.md` | `~/.config/opencode/skills`, `~/.agents/skills`, `<project>/.opencode/skills`, `<project>/.agents/skills` | `~/.config/opencode/opencode.json`, `<project>/opencode.json` | JSON, `mcp.servers` with `type: local` and an **array** `command` |
| Gemini CLI | `~/.gemini/GEMINI.md`, `<project>/GEMINI.md` | `~/.gemini/skills` | `~/.gemini/settings.json` | JSON, top-level `mcpServers` |
| Cursor | `<project>/AGENTS.md`, `<project>/.cursor/rules/lean-formalization.mdc` | `~/.cursor/skills`, `<project>/.cursor/skills` | `~/.cursor/mcp.json`, `<project>/.cursor/mcp.json` | JSON, `mcpServers` |
| VS Code / GitHub Copilot | `<project>/AGENTS.md`, `<project>/.github/copilot-instructions.md` | — | `<project>/.vscode/mcp.json` | JSON, `servers` |

### Where those paths came from

| Harness | Evidence |
|---|---|
| DSH | local source inspection: `packages/preset/agent-presets/src/discovery.ts` (`USER_PRESET_DIR = '.agent-presets'`) and `packages/skill/skill-filesystem/src/index.ts` (project roots `.dsh/skills`, `.agents/skills`; user roots `<dshHome>/skills`, `<agentsHome>/skills`) |
| Claude Code | `claude mcp add --help` observed on the authoring machine (`--scope local\|user\|project`, `-e KEY=value`); project `.mcp.json` shape from the lean-lsp-mcp README; memory-file locations from the Claude Code memory documentation |
| Codex CLI | the real `~/.codex/config.toml` on the authoring machine uses `[mcp_servers.<name>]` with `command`/`args`/`env`; `~/.codex/AGENTS.md` and `~/.codex/skills` exist there |
| OpenCode | upstream documentation for instructions, skills and MCP servers (V2: `mcp.servers.<name>`, `type: local`, `environment`, `command` as an array; global `~/.config/opencode/AGENTS.md`; compatibility roots `~/.claude/skills`, `~/.agents/skills`) |
| Gemini CLI | the real `~/.gemini/settings.json` on the authoring machine has a top-level `mcpServers` object; `gemini skills install <repo> --path skills` is upstream's documented install command. `gemini mcp --help` hung for 180 s in a non-interactive shell there, which is why the installer writes the file instead of calling the CLI |
| Cursor | the real `~/.cursor/mcp.json` uses top-level `mcpServers`; `~/.cursor/skills` exists on the authoring machine |
| VS Code / Copilot | `code --help` lists `--add-mcp <json>`; workspace `mcp.json` uses `{"servers": {...}}` per the lean-lsp-mcp README |

## Tier 2 — shipped, not verified end-to-end

These are written only with `--include-unverified`, and their status must be
reported as unverified.

| Harness | What is written | Evidence | Not verified |
|---|---|---|---|
| Mistral Vibe | `~/.vibe/config.toml` `[[mcp_servers]]` | lean-lsp-mcp README documents the shape, including the need to delete a bare `mcp_servers = []` first | nothing was run against Vibe; it is not installed on the authoring machine |
| any AGENTS.md-aware agent (Amp, Zed, Goose, Qwen Code, Crush, …) | `<project>/AGENTS.md`, `<project>/.agents/skills`, `~/.agents/skills` | the `.agents/skills` convention is documented by OpenCode V2 as a compatibility root | no universal MCP config path exists; use the agent's own `mcp add` or settings UI |

### Deliberately not shipped

Windsurf, Cline, Aider, Kiro, Amp, Zed and Goose each have their own MCP
configuration path. They are **not** in `harnesses.json` because no path was
verified from a primary source on the authoring machine, and a guessed path would
write a config file that silently does nothing. To add one:

1. find the path in that vendor's own documentation;
2. add a `harnesses.json` row with `docUrl` pointing at it and `tier: 2`;
3. run the installer with `--include-unverified` and
   `python verify/probe_mcp.py --harnesses` on that machine;
4. promote the row to `tier: 1` only after the probe and the harness's own listing
   both agree.

## MCP servers written

Both modes always disable `lean_build` and `lean_run_code`: builds must run as the
deterministic `lake --no-cache build` the gate verifies, and `lean_run_code` is an
arbitrary-code-execution surface.

**`beam` mode** (a `lean-beam-mcp` launcher, or `<project>/tools/beam-mcp.ps1`, was
detected): mount `lean-beam`, and disable on `lean-lsp` everything Beam owns —
`lean_goal`, `lean_term_goal`, `lean_diagnostic_messages`, `lean_hover_info`,
`lean_file_outline`, `lean_completions`, `lean_code_actions`, `lean_get_widgets`,
`lean_get_widget_source` — plus the two above. One owner per capability, and fewer
tool schemas in the model's context.

**`lsp-fallback` mode** (no Beam launcher): mount `lean-lsp` alone and **keep** the
goal, diagnostic, hover, outline, completion and code-action tools. Without this
the machine would have no proof-state tool at all.

All other `lean-lsp` tools are kept in both modes: `lean_local_search`,
`lean_loogle`, `lean_leansearch`, `lean_leanfinder`, `lean_state_search`,
`lean_hammer_premise`, `lean_multi_attempt`, `lean_minimal_hypotheses`,
`lean_profile_proof`, `lean_verify`, `lean_declaration_file`, `lean_references`.

### Native CLI equivalents

The installer edits configuration files (so it can back them up, stay idempotent
and be uninstalled exactly). If you prefer the harness's own command, these are
the ones observed to exist — use them instead, and note that uninstall will not
manage what they wrote:

```bash
claude mcp add --scope user lean-lsp uvx lean-lsp-mcp \
  -e LEAN_LOG_LEVEL=NONE -e LEAN_MCP_DISABLED_TOOLS=lean_build,lean_run_code
opencode mcp add lean-lsp --global -- uvx lean-lsp-mcp
code --add-mcp '{"name":"lean-lsp","command":"uvx","args":["lean-lsp-mcp"]}'
```

## Prerequisites

| Tool | Needed for | Behaviour when missing |
|---|---|---|
| `python3` | the installer itself | `install.ps1` / `install.sh` exit 2 with a message; `BOOTSTRAP.md` Appendix B says what to do by hand |
| `uvx` (from `uv`) | the Lean LSP MCP server | the server cannot start; the installer reports `uvx=MISSING (required)` — install uv, then re-run |
| `rg` (ripgrep) | `lean_local_search`, and source scanning in `lean_verify` | reported as a warning; every other tool still works |
| `elan` / `lake` | any Lean build, the gate, Beam | the gate fails at its first step with lake's own error |
| Beam | `beam` mode | the installer falls back to `lsp-fallback` and records that; install Beam from <https://github.com/leanprover/lean-beam> and re-run to switch modes |

### Restricted shells

If the process that launches the MCP server cannot write `uv`'s default cache or
tool directory, pass the flags the installer provides for exactly this case:

```bash
python install/install.py --uv-cache-dir /writable/cache --uv-tool-dir /writable/tools
```

This was observed on the authoring machine: `uvx` failed with
`Failed to initialize cache at ...: 拒绝访问。 (os error 5)` inside the agent's
sandboxed shell, while the same command worked once `UV_CACHE_DIR`/`UV_TOOL_DIR`
pointed at a writable directory.
