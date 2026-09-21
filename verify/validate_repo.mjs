// Structural validation of this repository.
//
// Dependency-free on purpose: `node verify/validate_repo.mjs` must work on a
// machine that has nothing but node. It checks the invariants a broken package
// would violate — the adapter table's schema, the skills' frontmatter and names,
// the DSH template's placeholders, the vendored-hash ledger, and the presence of
// every file the documentation tells a user to run.
//
// Exit codes: 0 ok, 1 at least one check failed.

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..')
const failures = []
const notes = []
const check = (ok, message) => { if (!ok) failures.push(message) }

const read = (p) => readFileSync(join(REPO, p), 'utf8')
const sha256 = (p) => createHash('sha256').update(readFileSync(join(REPO, p))).digest('hex')

// ── 1. adapter table ────────────────────────────────────────────────────────
const spec = JSON.parse(read('harnesses.json'))
check(spec.schemaVersion === 1, 'harnesses.json: schemaVersion must be 1')
check(typeof spec.repo?.url === 'string' && spec.repo.url.includes('github.com'), 'harnesses.json: repo.url missing')
check(typeof spec.contract?.blockBegin === 'string' && typeof spec.contract?.blockEnd === 'string',
  'harnesses.json: contract block markers missing')
check(read('contract.md').includes(spec.contract.source) === false || existsSync(join(REPO, spec.contract.source)),
  `harnesses.json: contract.source ${spec.contract.source} does not exist`)

const MCP_METHODS = new Set(['file-json', 'file-toml', 'native-cli', 'dsh-preset', 'none'])
const harnessIds = Object.keys(spec.harnesses ?? {})
check(harnessIds.length >= 8, `harnesses.json: expected at least 8 harnesses, found ${harnessIds.length}`)
for (const [id, h] of Object.entries(spec.harnesses ?? {})) {
  check(/^[a-z0-9]+(-[a-z0-9]+)*$/.test(id), `harness id is not kebab-case: ${id}`)
  check(typeof h.displayName === 'string' && h.displayName.length > 0, `${id}: displayName missing`)
  check(h.tier === 1 || h.tier === 2, `${id}: tier must be 1 or 2`)
  check(h.detect && (Array.isArray(h.detect.commands) || Array.isArray(h.detect.paths) || h.detect.always),
    `${id}: detect block is empty and not marked always`)
  check(Array.isArray(h.instructions), `${id}: instructions must be an array`)
  check(Array.isArray(h.skillRoots), `${id}: skillRoots must be an array`)
  check(h.mcp && MCP_METHODS.has(h.mcp.method), `${id}: mcp.method must be one of ${[...MCP_METHODS].join(', ')}`)
  for (const target of h.instructions ?? []) {
    check(['project', 'user', 'preset'].includes(target.scope), `${id}: instruction scope ${target.scope} is invalid`)
  }
  for (const root of h.skillRoots ?? []) {
    check(['project', 'user'].includes(root.scope), `${id}: skill root scope ${root.scope} is invalid`)
  }
  if (h.tier === 2) {
    notes.push(`${id} is tier 2 (config paths not verified end-to-end on the authoring machine)`)
  }
}

const tier1 = harnessIds.filter((id) => spec.harnesses[id].tier === 1)
check(tier1.length >= 6, `expected at least 6 tier-1 harnesses, found ${tier1.length}`)
for (const required of ['dsh', 'claude-code', 'codex', 'opencode', 'gemini-cli', 'cursor', 'vscode']) {
  check(tier1.includes(required), `tier-1 harness missing: ${required}`)
}

// ── 2. MCP server definitions ───────────────────────────────────────────────
const servers = spec.mcp?.servers ?? {}
check(Object.keys(servers).length >= 2, 'mcp.servers must define lean-lsp and lean-beam')
check(servers['lean-lsp']?.required === true, 'mcp.servers.lean-lsp must be required')
check(servers['lean-beam']?.required === false, 'mcp.servers.lean-beam must be optional (fallback mode)')
for (const mode of ['beam', 'lspFallback']) {
  const disabled = servers['lean-lsp']?.disabledTools?.[mode]
  check(Array.isArray(disabled) && disabled.includes('lean_build') && disabled.includes('lean_run_code'),
    `mcp lean-lsp ${mode}: must always disable lean_build and lean_run_code`)
}
check(!servers['lean-lsp'].disabledTools.lspFallback.includes('lean_goal'),
  'mcp lean-lsp lspFallback must KEEP lean_goal (Beam is absent there)')
check(servers['lean-lsp'].disabledTools.beam.includes('lean_goal'),
  'mcp lean-lsp beam mode must disable lean_goal (Beam owns it)')
check(Array.isArray(servers['lean-beam']?.detect) && servers['lean-beam'].detect.length > 0,
  'mcp.servers.lean-beam: detect probes missing')

// ── 3. skills ───────────────────────────────────────────────────────────────
const skillsRoot = join(REPO, 'skills')
const skillDirs = readdirSync(skillsRoot).filter((name) => statSync(join(skillsRoot, name)).isDirectory())
check(skillDirs.length >= 2, `skills/: expected the two owned skills, found ${skillDirs.length}`)
for (const name of skillDirs) {
  check(/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name), `skills/${name}: directory name is not kebab-case`)
  const file = join(skillsRoot, name, 'SKILL.md')
  check(existsSync(file), `skills/${name}: SKILL.md missing`)
  if (!existsSync(file)) continue
  const text = readFileSync(file, 'utf8')
  check(text.startsWith('---'), `skills/${name}: SKILL.md has no frontmatter`)
  const end = text.indexOf('\n---', 3)
  const front = text.slice(3, end)
  const declared = /(^|\n)name:\s*(\S+)/.exec(front)?.[2]
  check(declared === name, `skills/${name}: frontmatter name is "${declared}"`)
  check(/(^|\n)description:\s*\S/.test(front), `skills/${name}: frontmatter has no description`)
}
for (const owned of spec.skills?.owned ?? []) {
  check(skillDirs.includes(owned), `skills/: owned skill ${owned} is missing`)
}

// ── 4. vendored content ledger ──────────────────────────────────────────────
const provenance = read('skills/PROVENANCE.md')
const hash = (file) => createHash('sha256').update(readFileSync(file)).digest('hex')
const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
  const full = join(dir, entry.name)
  return entry.isDirectory() ? walk(full) : [full]
})
// Every row of the ledger is enforced, not just the skill directory: the license
// text is vendored too, and "validate_repo fails if a vendored byte changes" has to
// be true for all of it.
const ledgerRows = [...provenance.matchAll(/\|\s*`([^`]+)`\s*\|\s*`([0-9a-f]{64})`\s*\|/g)]
  .map((match) => ({ path: match[1], digest: match[2] }))
check(ledgerRows.length >= 8, `PROVENANCE.md lists only ${ledgerRows.length} hashed files`)
for (const row of ledgerRows) {
  const file = join(REPO, row.path)
  check(existsSync(file), `PROVENANCE.md names a file that does not exist: ${row.path}`)
  if (existsSync(file)) {
    check(hash(file) === row.digest, `vendored file does not match its recorded hash: ${row.path}`)
  }
}
for (const file of walk(join(skillsRoot, 'lean-beam'))) {
  const rel = relative(REPO, file).replace(/\\/g, '/')
  check(ledgerRows.some((row) => row.path === rel), `PROVENANCE.md does not record ${rel}`)
}

// Entry shapes: the installer renders them, but the table must still carry one for
// every harness that needs it, or that surface silently writes nothing.
for (const [id, h] of Object.entries(spec.harnesses ?? {})) {
  const mcp = h.mcp ?? {}
  if (mcp.method === 'file-json') {
    check(Boolean(mcp.entry) || Boolean(mcp.shapeByMajor), `${id}: file-json without an entry template`)
    check(Array.isArray(mcp.keyPath) || Boolean(mcp.shapeByMajor), `${id}: file-json without a keyPath`)
    const rendered = JSON.stringify(mcp.entry ?? mcp.shapeByMajor ?? '')
    check(rendered.includes('{command'), `${id}: json entry template does not reference {command}`)
  }
  if (mcp.method === 'file-toml') {
    check(Boolean(mcp.fields), `${id}: file-toml without a fields template`)
    check(Boolean(mcp.table) || Boolean(mcp.arrayOfTables), `${id}: file-toml without a table name`)
    check(JSON.stringify(mcp.fields).includes('{command'), `${id}: toml fields template does not reference {command}`)
  }
}
check(spec.skills.beam.commit.length === 40, 'harnesses.json: beam commit is not a full sha')
check(provenance.includes(spec.skills.beam.commit), 'PROVENANCE.md does not record the pinned lean-beam commit')
check(provenance.includes(spec.skills.upstream.commit), 'PROVENANCE.md does not record the pinned leanprover/skills commit')

// ── 5. required files ───────────────────────────────────────────────────────
const required = [
  'README.md', 'README.zh-CN.md', 'BOOTSTRAP.md', 'AGENTS.md', 'CLAUDE.md', 'GEMINI.md',
  'contract.md', 'harnesses.json', 'LICENSE', 'NOTICE',
  'install/install.py', 'install/install.ps1', 'install/install.sh',
  'gate/LeanAudit.lean', 'gate/leancheck.ps1', 'gate/leancheck.sh',
  'dsh/preset/preset.yml', 'dsh/preset/agent.cordis.yml.tmpl',
  'docs/harness-matrix.md', 'docs/acceptance.md', 'docs/troubleshooting.md',
  'verify/probe_mcp.py', 'verify/smoke.py',
]
for (const file of required) check(existsSync(join(REPO, file)), `missing required file: ${file}`)

// ── 6. templates still parameterised ────────────────────────────────────────
const dshTemplate = read('dsh/preset/agent.cordis.yml.tmpl')
const placeholders = new Set([...dshTemplate.matchAll(/\{\{([A-Z_]+)\}\}/g)].map((m) => m[1]))
const known = new Set(['CONTRACT_BLOCK_YAML', 'MCP_ROWS', 'MCP_MODE', 'MCP_MODE_DETAIL', 'CONTRACT_SOURCE'])
for (const token of placeholders) check(known.has(token), `unknown placeholder in the DSH template: {{${token}}}`)
for (const token of known) check(placeholders.has(token), `DSH template no longer uses {{${token}}}`)
check(!dshTemplate.includes('the_bible_of_Jordan'), 'DSH template still hard-codes a project path')

for (const file of ['gate/LeanAudit.lean', 'gate/leancheck.ps1', 'gate/leancheck.sh']) {
  const text = read(file)
  check(!/Jordan|JordanBook/.test(text), `${file} hard-codes the Jordan project`)
}
check(read('gate/LeanAudit.lean').includes('LEANCHECK_JSON:'), 'LeanAudit.lean does not emit LEANCHECK_JSON lines')
check(read('gate/leancheck.ps1').includes('lean-formalization.json'), 'leancheck.ps1 does not read lean-formalization.json')
check(read('gate/leancheck.sh').includes('lean-formalization.json'), 'leancheck.sh does not read lean-formalization.json')

// ── 7. contract shape ───────────────────────────────────────────────────────
const contract = read('contract.md')
const contractFlat = contract.replace(/\s+/g, ' ')
const bullets = contract.slice(contract.indexOf('## Non-negotiables'), contract.indexOf('## Inner loop'))
  .split('\n').filter((line) => line.startsWith('- ')).length
check(bullets >= 8, `contract.md: expected at least 8 non-negotiable bullets, found ${bullets}`)
for (const phrase of ['sorry', 'axiom', 'quantifier', 'tactic', 'three substantively different routes',
  'exit codes', 'acceptance authority', 'never signs off']) {
  check(contractFlat.includes(phrase), `contract.md lost the rule containing "${phrase}"`)
}
check(read('verify/smoke.py').includes(spec.contract.blockBegin),
  'verify/smoke.py and harnesses.json disagree about the block marker')

// ── report ──────────────────────────────────────────────────────────────────
console.log(`harnesses     : ${harnessIds.length} (tier 1: ${tier1.length})`)
console.log(`skills        : ${skillDirs.join(', ')}`)
console.log(`mcp servers   : ${Object.keys(servers).join(', ')}`)
for (const note of notes) console.log(`note          : ${note}`)
if (failures.length > 0) {
  console.error(`\nFAILED (${failures.length}):`)
  for (const failure of failures) console.error(` - ${failure}`)
  process.exit(1)
}
console.log('\nrepository validation: OK')
