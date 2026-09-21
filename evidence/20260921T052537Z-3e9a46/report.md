# lean-formalization acceptance — 20260921T052537Z-3e9a46

- repository: `D:\新建文件夹\lean-formalization`
- result: **PASS**
- steps not marked required are informational; read their logs, do not assume.

| step | required | exit | seconds | note |
|---|---|---|---|---|
| validate-repo | yes | 0 | 0 |  |
| smoke | yes | 0 | 9 | install → assert → idempotence → uninstall, plus a real Lean build |
| gate-shell | yes | 0 | 0 | the POSIX gate's embedded Python: parses, reads config, enforces the whitelist (the shell wrapper itself needs a real bash and is not covered) |
| provenance-recheck | yes | 0 | 0 | a second, independent implementation of the vendored-hash check |
| probe-lean-lsp | yes | 0 | 9 | the exact command the lsp-fallback configuration records |
| doctor | no | 0 | 1 | per-harness detection and file presence |
| dry-run-target-project | no | 0 | 1 | writes nothing; the plan is inspected by the reviewer |
| install-for-harness-probe | no | 0 | 1 | install into a throwaway Lean project + home |
| claude-mcp-list | no | 0 | 1 | informational: does Claude Code read the .mcp.json we wrote? (.mcp.json is the installer's own surface; .claude.json is not touched) |
| codex-mcp-list | no | 0 | 0 | informational: does Codex read the config.toml we wrote? (CODEX_HOME points at the throwaway home) |
| opencode-mcp-list | no | 0 | 10 | informational: does OpenCode read the opencode.json we wrote? (run outside a git repo: OpenCode itself may be refused permission to spawn git/uvx inside a sandbox — that is not a config failure) |

## raw output

See `command-*.log` next to this file.

Unknowns are written as unknown: a step with exit `None` or a skipped note was not run.
