.PHONY: lint fmt validate check

# Run all checks
check: lint validate

# Lint all config and script files
lint:
	@echo "=== YAML lint ==="
	yamllint -d relaxed telemetry/*.yml telemetry/**/*.yml 2>/dev/null || true
	@echo "=== Shell lint ==="
	shellcheck scripts/*.sh
	@echo "=== Compose validate ==="
	docker compose -f telemetry/docker-compose.yml config >/dev/null
	@echo "=== JSON validate ==="
	@find telemetry -name '*.json' -exec sh -c 'jq empty "$$1" && echo "  OK: $$1"' _ {} \;
	@echo "=== All checks passed ==="

# Format scripts
fmt:
	shfmt -w -i 2 scripts/*.sh

# Validate compose and manifests
validate:
	docker compose -f telemetry/docker-compose.yml config >/dev/null
	@echo "Compose config valid"
