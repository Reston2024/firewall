# Contributing

## Getting Started

1. Clone the repo
2. Install pre-commit: `pip install pre-commit && pre-commit install`
3. Copy secrets template: `cp telemetry/.env.example telemetry/.env`

## Development Workflow

1. Create a branch from `master`
2. Make changes
3. Run `make check` to validate locally
4. Commit — pre-commit hooks run automatically
5. Push and open a PR
6. CI must pass before merge

## Commit Messages

Use conventional format:

```
type(scope): short description

- feat: new feature
- fix: bug fix
- docs: documentation only
- test: validation scripts
- security: hardening changes
- chore: repo maintenance
```

## File Standards

- All text files use LF line endings (enforced by .gitattributes)
- YAML: 2-space indent, validated by yamllint
- Shell: 2-space indent, validated by shellcheck
- No secrets in commits — use .env files

## Deployment Changes

Changes to configs deployed on live hardware require:

1. Validation script update or confirmation of existing coverage
2. Deployment runbook step (if new procedure)
3. Tested on hardware before merging
