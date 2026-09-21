#!/usr/bin/env python3
"""Deterministic self-test for this repository.

Runs the installer into throwaway directories — never the real home or a real
project — and asserts the properties the repository claims:

  1. install writes the contract block, the owned skills, the MCP entries and the
     gate scaffold, and every JSON/TOML file it touched still parses;
  2. a second install writes nothing (idempotence);
  3. user text outside the delimited block survives a re-install;
  4. uninstall removes what it created, restores what it changed, and leaves the
     project's own config alone;
  5. with --with-gate, the scaffolded gate script really runs: it refuses an empty
     target list, and passes on a project whose axioms are inside the whitelist.

Usage:
    python verify/smoke.py [--work DIR] [--with-gate] [--json]

Exit codes: 0 all checks passed, 1 a check failed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BLOCK_BEGIN = "<!-- lean-formalization:begin v1 -->"
BLOCK_END = "<!-- lean-formalization:end -->"


class Checker:
    def __init__(self) -> None:
        self.results: list[dict] = []

    def check(self, name: str, ok: bool, detail: str = "") -> bool:
        self.results.append({"check": name, "ok": bool(ok), "detail": detail})
        print("%-4s %s%s" % ("PASS" if ok else "FAIL", name, ("  — " + detail) if detail else ""))
        return bool(ok)

    @property
    def failed(self) -> int:
        return sum(1 for r in self.results if not r["ok"])


def child_env() -> dict:
    env = dict(os.environ)
    env.setdefault("PYTHONIOENCODING", "utf-8")
    return env


def run_installer(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(REPO / "install" / "install.py"), *args],
        cwd=str(cwd or REPO), capture_output=True, text=True,
        encoding="utf-8", errors="replace", env=child_env(),
    )


def make_fixture(root: Path) -> Path:
    project = root / "FixtureProj"
    (project / "FixtureProj").mkdir(parents=True, exist_ok=True)
    (project / "lean-toolchain").write_text("leanprover/lean4:v4.34.0\n", encoding="utf-8")
    (project / "lakefile.toml").write_text(
        'name = "FixtureProj"\ndefaultTargets = ["FixtureProj"]\n\n[[lean_lib]]\nname = "FixtureProj"\n',
        encoding="utf-8",
    )
    (project / "FixtureProj.lean").write_text("import FixtureProj.Basic\n", encoding="utf-8")
    (project / "FixtureProj" / "Basic.lean").write_text(
        "namespace FixtureProj\n\n"
        "theorem trivial_eq (a b : Nat) : a + b = b + a := Nat.add_comm a b\n\n"
        "theorem uses_classical (p : Prop) : p ∨ ¬p := Classical.em p\n\n"
        "end FixtureProj\n",
        encoding="utf-8",
    )
    # A pre-existing instruction file with the user's own prose around the block.
    (project / "AGENTS.md").write_text(
        "# FixtureProj\n\nMy own project notes that must survive.\n", encoding="utf-8"
    )
    return project


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="smoke.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work", default=None, help="scratch root (default: <repo>/.smoke)")
    parser.add_argument("--with-gate", action="store_true", help="also build and run the scaffolded gate")
    parser.add_argument("--json", action="store_true", help="print a JSON report")
    args = parser.parse_args(argv)

    work = Path(args.work).resolve() if args.work else REPO / ".smoke"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    home = work / "home"
    home.mkdir()
    project = make_fixture(work)
    checker = Checker()

    common = ["--project", str(project), "--home", str(home),
              "--dsh-home", str(home / "dsh-home"), "--agents-home", str(home / ".agents")]

    # ── 1. install ──────────────────────────────────────────────────────────
    first = run_installer(*common, "--scope", "both")
    checker.check("install exits 0", first.returncode == 0, first.stdout.strip().splitlines()[-1] if first.stdout else "")

    expected_files = [
        project / "AGENTS.md",
        project / "CLAUDE.md",
        project / "GEMINI.md",
        project / ".github" / "copilot-instructions.md",
        project / ".cursor" / "rules" / "lean-formalization.mdc",
        project / ".mcp.json",
        project / ".vscode" / "mcp.json",
        project / ".agents" / "skills" / "lean-formalization" / "SKILL.md",
        project / ".agents" / "skills" / "lean-beam" / "SKILL.md",
        project / "lean-formalization.json",
        project / "LeanAudit.lean",
        project / "scripts" / "leancheck.ps1",
        project / ".lean-formalization" / "manifest.json",
        home / ".codex" / "config.toml",
        home / ".gemini" / "settings.json",
        home / ".cursor" / "mcp.json",
        home / ".claude" / "CLAUDE.md",
        home / ".config" / "opencode" / "AGENTS.md",
        home / "dsh-home" / ".agent-presets" / "lean" / "agent.cordis.yml",
    ]
    missing = [str(p.relative_to(work)) for p in expected_files if not p.is_file()]
    checker.check("every expected file exists", not missing, ", ".join(missing))

    agents = (project / "AGENTS.md").read_text(encoding="utf-8")
    checker.check("contract block present exactly once",
                  agents.count(BLOCK_BEGIN) == 1 and agents.count(BLOCK_END) == 1)
    checker.check("user prose outside the block survives",
                  "My own project notes that must survive." in agents)
    checker.check("contract carries the non-negotiables",
                  "Non-negotiables" in agents and "never the acceptance authority" in agents.split("Non-negotiables")[1])

    # every config file we touched must still parse
    parse_failures = []
    for path in [home / ".gemini" / "settings.json", home / ".cursor" / "mcp.json",
                 home / ".config" / "opencode" / "opencode.json", project / ".mcp.json",
                 project / ".vscode" / "mcp.json", project / "lean-formalization.json",
                 project / ".lean-formalization" / "manifest.json"]:
        if not path.is_file():
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            parse_failures.append("%s: %s" % (path.name, exc))
    try:
        toml = tomllib.loads((home / ".codex" / "config.toml").read_text(encoding="utf-8"))
        if "lean-lsp" not in toml.get("mcp_servers", {}):
            parse_failures.append("codex config.toml has no [mcp_servers.lean-lsp]")
    except tomllib.TOMLDecodeError as exc:
        parse_failures.append("codex config.toml: %s" % exc)
    checker.check("every config file still parses", not parse_failures, "; ".join(parse_failures))

    # OpenCode 1.x and 2.x take different (mutually rejected) MCP config shapes, so
    # the written shape must match the installed major.
    opencode_json = home / ".config" / "opencode" / "opencode.json"
    if opencode_json.is_file():
        doc = json.loads(opencode_json.read_text(encoding="utf-8"))
        mcp = doc.get("mcp", {})
        major = None
        if shutil.which("opencode"):
            try:
                probe = subprocess.run(["opencode", "--version"], capture_output=True, text=True,
                                       timeout=30, encoding="utf-8", errors="replace")
                match = re.search(r"(\d+)\.", (probe.stdout or "") + (probe.stderr or ""))
                major = match.group(1) if match else None
            except (OSError, subprocess.SubprocessError):
                major = None
        if major == "1":
            good = "lean-lsp" in mcp and "servers" not in mcp
        elif major == "2":
            good = "lean-lsp" in mcp.get("servers", {})
        else:
            good = "lean-lsp" in mcp or "lean-lsp" in mcp.get("servers", {})
        checker.check("opencode config shape matches the installed major (%s)" % (major or "undetected"),
                      good, json.dumps(mcp)[:120])

    # ── 2. idempotence ──────────────────────────────────────────────────────
    second = run_installer(*common, "--scope", "both")
    writes = [l for l in second.stdout.splitlines() if l.startswith("    +") or l.startswith("    ~")]
    checker.check("second install writes nothing", second.returncode == 0 and not writes,
                  "; ".join(writes[:3]))

    # ── 3. uninstall ────────────────────────────────────────────────────────
    # The user edits a file the installer created; uninstall must not delete it.
    edited = project / "CLAUDE.md"
    edited.write_text(edited.read_text(encoding="utf-8") + "\nmy own addition\n", encoding="utf-8")

    uninstall = run_installer("--project", str(project), "--home", str(home), "--uninstall")
    leftover = [str(p.relative_to(work)) for p in
                [project / ".mcp.json", project / "LeanAudit.lean",
                 project / ".github" / "copilot-instructions.md",
                 home / ".codex" / "config.toml", home / ".cursor" / "mcp.json",
                 home / "dsh-home" / ".agent-presets" / "lean" / "agent.cordis.yml"]
                if p.exists()]
    checker.check("uninstall removes what it created", uninstall.returncode == 0 and not leftover,
                  ", ".join(leftover))
    # AGENTS.md pre-existed, so uninstall must restore it without our block.
    restored = (project / "AGENTS.md").read_text(encoding="utf-8") if (project / "AGENTS.md").is_file() else ""
    checker.check("uninstall restores a pre-existing file without the block",
                  "My own project notes that must survive." in restored and BLOCK_BEGIN not in restored)
    checker.check("uninstall leaves the project config alone",
                  (project / "lean-formalization.json").is_file())
    checker.check("a file the user edited is left in place, not deleted",
                  edited.is_file() and "edited since install" in uninstall.stdout)

    # ── 4. optionally: the scaffolded gate really runs ──────────────────────
    if args.with_gate:
        gate = run_installer(*common, "--scope", "project")
        if gate.returncode != 0:
            checker.check("re-install for the gate check", False, gate.stderr.strip()[:200])
        else:
            empty = subprocess.run(
                ["pwsh", "-NoProfile", "-File", str(project / "scripts" / "leancheck.ps1")],
                cwd=str(project), capture_output=True, text=True,
            )
            checker.check("gate refuses an empty target list (exit 2)", empty.returncode == 2,
                          empty.stdout.strip().splitlines()[-1] if empty.stdout else "")
            cfg_path = project / "lean-formalization.json"
            cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
            cfg["targets"] = ["FixtureProj.trivial_eq", "FixtureProj.uses_classical"]
            cfg["entryModules"] = ["FixtureProj"]
            cfg_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
            good = subprocess.run(
                ["pwsh", "-NoProfile", "-File", str(project / "scripts" / "leancheck.ps1")],
                cwd=str(project), capture_output=True, text=True,
            )
            checker.check("gate passes a whitelisted project (exit 0)", good.returncode == 0,
                          good.stdout.strip().splitlines()[-1] if good.stdout else "")
            bad = json.loads(cfg_path.read_text(encoding="utf-8"))
            bad["allowedAxioms"] = []
            (project / "lean-formalization.json").write_text(json.dumps(bad, indent=2) + "\n", encoding="utf-8")
            strict = subprocess.run(
                ["pwsh", "-NoProfile", "-File", str(project / "scripts" / "leancheck.ps1"), "-NoBuild"],
                cwd=str(project), capture_output=True, text=True,
            )
            checker.check("gate fails a whitelist violation (exit 1)", strict.returncode == 1,
                          " ".join(strict.stdout.strip().splitlines()[-1:]))

    if args.json:
        print(json.dumps({"work": str(work), "results": checker.results,
                          "failed": checker.failed}, indent=2))
    print("")
    print("smoke: %d checks, %d failed" % (len(checker.results), checker.failed))
    print("scratch tree left at %s" % work)
    return 1 if checker.failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
