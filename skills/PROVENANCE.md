# Provenance ledger

Every byte in this repository is either owned by this repository, or vendored from
an upstream project under its own license. This file records which is which, so a
later update can be checked instead of guessed.

Pinned upstream state at the time this repository was published:

| Upstream | Commit | License |
|---|---|---|
| `https://github.com/leanprover/lean-beam.git` | `6511cd96917d74cf59e03e303c69e2b6785aba78` | Apache-2.0 |
| `https://github.com/leanprover/skills.git` | `7d3da0282e7b724b07620e45cf212f2e05e19334` | Apache-2.0 |

## Owned here

- `contract.md` — the always-on rules (this repository's own text).
- `skills/lean-formalization/SKILL.md` — the four-layer workflow and the
  Beam ↔ lean-lsp routing table.
- `harnesses.json`, `install/`, `verify/`, `gate/`, `dsh/preset/agent.cordis.yml.tmpl`,
  `docs/`, `BOOTSTRAP.md`, the READMEs.

## Vendored from `leanprover/lean-beam` (Apache-2.0, verbatim)

File contents are byte-identical to the upstream commit above, with LF line
endings (the upstream blob hashes were taken from the GitHub API).

| File | sha256 |
|---|---|
| `skills/lean-beam/SKILL.md` | `eeb4f7bf3af7ae9ad4b2b6defdac218d572981caf7347941981d4357c45db8ce` |
| `skills/lean-beam/agents/openai.yaml` | `4cb3bea4b92973aa22318036d1ae686fe6b14f6fe30aaeaa18930b0867a35827` |
| `skills/lean-beam/references/anti-patterns.md` | `8cf85b8c4ada5faee56afd8b48f2b4b050a3e6bf8481380bad76f87b0b605a68` |
| `skills/lean-beam/references/commit-speculative.md` | `e7deeb641a94b5b8bfae365812667e011dd9c5412a1a6ba34b4bff3d88b912b0` |
| `skills/lean-beam/references/lean-run-at-semantics.md` | `49b4900a8aca430e5cb727ef1b9fe90f4d02a522b57619af7f30f128134695ae` |
| `skills/lean-beam/references/mcts-search.md` | `e1c4897c2777d4dd65457cac12e62094519b0060a21699d667bfaa80564ae213` |
| `skills/lean-beam/references/workflow-details.md` | `81ec2bd4e7f3916e7a380616393f0b40d278aba4ac66921132b7d90ca5c2b3b9` |
| `licenses/lean-beam-LICENSE` | `7ef159fd8db5a7a9e8051aac48997353f26d744e25f730a0594a806c126d2114` |

`verify/validate_repo.mjs` fails if any of these files stops matching its recorded
hash, so a silent edit to vendored content cannot pass validation.

## Not vendored here: the nine `leanprover/skills` skills

`lean-bisect`, `lean-mwe`, `lean-pr`, `lean-proof`, `lean-setup`, `mathlib-build`,
`mathlib-pr`, `mathlib-review` and `nightly-testing` are **not** copied into this
repository. Installing them is delegated to upstream's own per-harness installers
(`claude plugin marketplace add ...`, `gemini skills install ...`, Codex
`$skill-installer`, or a pinned clone plus copy as the offline fallback). See
`BOOTSTRAP.md` step 5 for the exact commands.

That decision is deliberate: a second copy here would drift from upstream, and
upstream already publishes one installer per harness. This repository carries only
what upstream does not: the contract, the routing skill, the adapter table and the
acceptance gate.

The upstream commit recorded above is the state the pinned-clone fallback checks
out. `lean-setup` declares `name: lean4-setup` in its frontmatter while its
directory is `lean-setup`; that divergence is upstream's and is left alone.

## Updating

1. Resolve the new upstream commit (`git ls-remote`, or the GitHub API).
2. Re-copy the vendored files with LF endings.
3. Recompute the hashes above and update this file in the same commit.
4. Run `node verify/validate_repo.mjs` and `python verify/smoke.py`.
