# Security Audit Remediation — 2026-03-01

Summary of changes implemented from the full-repository security audit.

## Changes Made

### 1. CI Check for Dangerous Config Files (NEW)

**File:** `.github/workflows/security-config-check.yml`

Added a GitHub Actions workflow that triggers on PRs modifying:
- `.claude/settings.json`
- `.claude/settings.local.json`
- `.mcp.json`

These are the exact attack vectors for CVE-2025-59536 (RCE via MCP user consent bypass) and CVE-2026-21852 (API key exfiltration via `ANTHROPIC_BASE_URL` override). The workflow posts a comment explaining the risk and fails the check until a security-aware reviewer approves.

### 2. SHA-Pinned All GitHub Actions

Replaced mutable version tags (`@v4`, `@v5`, `@v7`, `@v1`) with immutable commit SHAs across all 6 existing workflow files plus the new one. This prevents supply chain attacks where a compromised tag could point to malicious code.

| Action | Tag | Pinned SHA |
|--------|-----|------------|
| `actions/checkout` | v4 | `34e11487...` |
| `actions/setup-python` | v5 | `a26af69b...` |
| `actions/setup-node` | v4 | `49933ea5...` |
| `actions/github-script` | v7 | `f28e40c7...` |
| `anthropics/claude-code-action` | v1 | `8cfb5053...` |
| `stefanzweifel/git-auto-commit-action` | v5 | `b863ae19...` |

**Files modified:**
- `.github/workflows/ci-quality-gate.yml`
- `.github/workflows/claude-code-review.yml`
- `.github/workflows/claude.yml`
- `.github/workflows/pr-issue-auto-close.yml`
- `.github/workflows/smart-sync.yml`
- `.github/workflows/sync-codex-skills.yml`

### 3. Removed Unused `subprocess` Imports

Removed dead `import subprocess` from two files where it was imported but never used:
- `engineering/dependency-auditor/scripts/dep_scanner.py`
- `engineering/dependency-auditor/scripts/upgrade_planner.py`

### 4. Replaced `__import__('datetime')` with Standard Imports

Two security scripts used `__import__('datetime').datetime.now()` — a functional but unconventional pattern. Replaced with a standard `from datetime import datetime` import at the top of each file:
- `engineering-team/senior-security/scripts/secret_scanner.py`
- `engineering-team/senior-security/scripts/threat_modeler.py`

## Audit Verdict

The full audit (7 parallel agents, every file in the repo) found **no malicious code, backdoors, prompt injections, data exfiltration, or credential theft**. The changes above address the minor code hygiene observations and add proactive defenses against the recently-disclosed CVE-2025-59536 and CVE-2026-21852 attack vectors.
