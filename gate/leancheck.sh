#!/usr/bin/env bash
# leancheck.sh — the project gate (POSIX twin of leancheck.ps1).
#
# Reads lean-formalization.json from the project root and runs, in order:
#
#   1.  lake --no-cache build <buildTargets...> <entryModules...>
#   2.  lake env lean --run <leanAuditScript> <library> -- <targets...>
#   3.  an axiom-whitelist check over every reported declaration
#
# Evidence lands in <evidenceDir>/runs/<UTC stamp>-<short id>/ (report.md,
# report.json, command-*.log) and LATEST.md becomes a navigation copy.
# Exit 0 only when every command exited 0, every target was reported, and every
# axiom is in the whitelist. Requires python3 for config parsing only.
#
# Usage:
#   bash scripts/leancheck.sh
#   bash scripts/leancheck.sh --no-build
#   bash scripts/leancheck.sh --config other.json
set -uo pipefail

CONFIG=lean-formalization.json
NOBUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --no-build) NOBUILD=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "leancheck: unknown argument: $1" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$PWD"
case "$CONFIG" in /*) CONFIG_PATH="$CONFIG" ;; *) CONFIG_PATH="$PROJECT_ROOT/$CONFIG" ;; esac
if [ ! -f "$CONFIG_PATH" ]; then echo "leancheck: config not found: $CONFIG_PATH" >&2; exit 2; fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "leancheck: python3 is required to read $CONFIG (install python3, or use leancheck.ps1 on Windows)" >&2
  exit 2
fi

eval "$(python3 - "$CONFIG_PATH" <<'PY'
import json, shlex, sys
cfg = json.load(open(sys.argv[1], encoding='utf-8'))
if not cfg.get('library'):
    sys.exit('leancheck: config has no "library"')
def q(v): return shlex.quote(str(v))print('LIBRARY=%s' % q(cfg['library']))
for key, var in (('targets', 'TARGETS'), ('entryModules', 'ENTRY'), ('buildTargets', 'BUILD'),
                 ('allowedAxioms', 'ALLOWED'), ('gitSafeDirectories', 'SAFEDIRS')):
    vals = cfg.get(key) or []
    if key == 'buildTargets' and not vals:
        vals = [cfg['library']]
    print('%s=(%s)' % (var, ' '.join(q(v) for v in vals)))
print('EVIDENCE_DIR=%s' % q(cfg.get('evidenceDir') or 'evidence/lean'))
print('LAKE=%s' % q(cfg.get('lakeCommand') or 'lake'))
print('AUDIT_SCRIPT=%s' % q(cfg.get('leanAuditScript') or 'LeanAudit.lean'))
PY
)" || { echo "leancheck: could not read config" >&2; exit 2; }

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "leancheck: config lists no targets; refusing to report an empty audit as success" >&2
  exit 2
fi

# `.lake/packages/*` may belong to another account than the one running the build;
# git then fails with "dubious ownership" and exits 128 before Lake builds
# anything. Grant safe.directory for THIS INVOCATION only (never in the user's
# global git config). List the directories in lean-formalization.json.
if [ "${#SAFEDIRS[@]}" -gt 0 ]; then
  export GIT_CONFIG_COUNT="${#SAFEDIRS[@]}"
  i=0
  for d in "${SAFEDIRS[@]}"; do
    export "GIT_CONFIG_KEY_$i=safe.directory"
    export "GIT_CONFIG_VALUE_$i=$d"
    i=$((i + 1))
  done
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SHORT="$(python3 -c 'import secrets;print(secrets.token_hex(3))')"
RUN_DIR="$PROJECT_ROOT/${EVIDENCE_DIR%/}/runs/$STAMP-$SHORT"
mkdir -p "$RUN_DIR"

STATUSES=()
STEP_NAMES=()

run_step() {
  name="$1"; shift
  echo "==> $name"
  start=$(date +%s)
  "$@" > "$RUN_DIR/command-$name.log" 2>&1
  code=$?
  end=$(date +%s)
  echo "    exit $code in $((end - start))s"
  STATUSES+=("$code")
  STEP_NAMES+=("$name")
  return $code
}

if [ "$NOBUILD" -eq 0 ]; then
  run_step build "$LAKE" --no-cache build "${BUILD[@]}" "${ENTRY[@]}"
fi
run_step axiom-audit "$LAKE" env lean --run "$AUDIT_SCRIPT" "$LIBRARY" -- "${TARGETS[@]}"

python3 - "$RUN_DIR" "$LIBRARY" "${EVIDENCE_DIR%/}" "$STAMP" "${ALLOWED[@]}" -- "${TARGETS[@]}" <<'PY'
import json, os, sys

run_dir, library, evidence_dir, stamp = sys.argv[1:5]
rest = sys.argv[5:]
sep = rest.index('--')
allowed, targets = rest[:sep], rest[sep + 1:]

reported = {}
audit_log = os.path.join(run_dir, 'command-axiom-audit.log')
if os.path.exists(audit_log):
    with open(audit_log, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            idx = line.find('LEANCHECK_JSON:')
            if idx >= 0:
                try:
                    rec = json.loads(line[idx + len('LEANCHECK_JSON:'):])
                except json.JSONDecodeError:
                    continue
                reported[rec.get('name', '')] = rec

failures = []
for target in targets:
    rec = reported.get(target)
    if rec is None:
        failures.append('target not reported: %s' % target)
        continue
    extra = [a for a in rec.get('axioms', []) if a not in allowed]
    if extra:
        failures.append('%s depends on axioms outside the whitelist: %s' % (target, ', '.join(extra)))

steps = [name for name in ('build', 'axiom-audit')
         if os.path.exists(os.path.join(run_dir, 'command-%s.log' % name))]

report = {
    'gate': 'leancheck',
    'library': library,
    'timestampUtc': stamp,
    'targets': targets,
    'allowedAxioms': allowed,
    'steps': steps,
    'whitelistFailures': failures,
}
with open(os.path.join(run_dir, 'report.json'), 'w', encoding='utf-8') as fh:
    json.dump(report, fh, indent=2)

lines = ['# leancheck report — %s' % os.path.basename(run_dir), '',
         '- library: `%s`' % library,
         '- targets: %d' % len(targets),
         '- allowed axioms: `%s`' % ', '.join(allowed), '',
         '## axioms per target', '', '| target | kind | axioms |', '|---|---|---|']
for target in targets:
    rec = reported.get(target)
    if rec:
        lines.append('| %s | %s | %s |' % (target, rec.get('kind'), ', '.join(rec.get('axioms', []))))
    else:
        lines.append('| %s | (missing) | |' % target)
if failures:
    lines += ['', '## whitelist failures', ''] + ['- %s' % f for f in failures]
with open(os.path.join(run_dir, 'report.md'), 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(lines) + '\n')

latest = os.path.join(os.path.dirname(os.path.dirname(run_dir)), 'LATEST.md')
with open(latest, 'w', encoding='utf-8') as fh:
    fh.write('# leancheck — latest run\n\nLatest run: `%s`\n\nResult: %s\n\n'
             'History is appended, never erased: every run keeps its own directory.\n'
             % (os.path.basename(run_dir), 'FAIL' if failures else 'inspect report.md'))

if failures:
    for f in failures:
        print(' - %s' % f)
    sys.exit(1)
PY
WHITELIST_CODE=$?

FAILED=0
for code in "${STATUSES[@]:-}"; do [ "$code" -ne 0 ] && FAILED=1; done
echo ""
echo "evidence: $RUN_DIR"
if [ "$FAILED" -ne 0 ]; then echo "FAILED steps: ${STEP_NAMES[*]}" >&2; exit 1; fi
if [ "$WHITELIST_CODE" -ne 0 ]; then echo "leancheck: FAIL (whitelist)" >&2; exit 1; fi
echo "leancheck: PASS"
exit 0
