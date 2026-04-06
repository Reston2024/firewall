---
phase: 11
slug: foundation-sec-8b-ai-analyst
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-06
---

# Phase 11 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts + SSH remote commands |
| **Quick run command** | `ssh opsadmin@192.168.1.22 "ollama list && ss -tlnp \| grep 11434"` |
| **Full suite command** | `bash scripts/validate-phase11.sh` |
| **Estimated runtime** | ~30 seconds |

## Per-Task Verification Map

| Task ID | Plan | Requirement | Test Type | Status |
|---------|------|-------------|-----------|--------|
| 11-01-01 | 01 | AI-01 | integration | ⬜ pending |
| 11-01-02 | 01 | AI-02 | integration | ⬜ pending |
| 11-01-03 | 01 | AI-03 | integration | ⬜ pending |
| 11-01-04 | 01 | AI-04 | integration | ⬜ pending |

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| AI response quality | AI-04 | Subjective assessment of security analysis quality | Ask a security question, evaluate answer relevance |

**Approval:** pending
