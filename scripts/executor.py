#!/usr/bin/env python3
"""Firewall Executor — processes recommendation artifacts through the gate contract.

Receives recommendation artifacts from the SOC Brain (local-ai-soc),
validates against contracts/recommendation.schema.json, applies the 6-gate
sequence defined in contracts/executor-gate.md, and returns execution receipts
per contracts/execution-receipt.schema.json.

This is a SCAFFOLD — it validates and logs but does NOT apply firewall rules.
Actual iptables/IPFire integration is deferred until the executor is audited.

Runs as a systemd service on supportTAK-server, listening on 127.0.0.1:8300.
The SOC Brain dispatches recommendations via SSH tunnel or direct HTTP.

See: decisions/ADR-E01-executor-failure-taxonomy.md
See: contracts/executor-gate.md
"""

import json
import uuid
import os
import sys
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

PORT = 8300
BIND = '127.0.0.1'  # Localhost only — SOC accesses via SSH tunnel
AUTH_TOKEN = os.environ.get('EXECUTOR_TOKEN', 'executor-gate-token-2026')
RECEIPT_LOG = '/var/log/executor-receipts.jsonl'
CLOCK_SKEW_TOLERANCE = 60  # seconds

# Load recommendation schema for validation
SCRIPT_DIR = Path(__file__).parent.parent
SCHEMA_PATH = SCRIPT_DIR / 'contracts' / 'recommendation.schema.json'

REQUIRED_FIELDS = [
    'schema_version', 'recommendation_id', 'case_id', 'type',
    'proposed_action', 'target', 'scope', 'rationale',
    'evidence_event_ids', 'retrieval_sources', 'inference_confidence',
    'model_id', 'model_run_id', 'prompt_inspection',
    'generated_at', 'analyst_approved', 'approved_by', 'expires_at'
]

VALID_TYPES = ['network_control_change', 'alert_suppression', 'asset_isolation', 'no_action']
VALID_CONFIDENCE = ['high', 'medium', 'low', 'none']


def make_receipt(recommendation_id, case_id, taxonomy, detail='', firewall_rule_id=None):
    """Create an execution receipt per contracts/execution-receipt.schema.json."""
    receipt = {
        'schema_version': '1.0.0',
        'receipt_id': str(uuid.uuid4()),
        'recommendation_id': recommendation_id,
        'case_id': case_id,
        'failure_taxonomy': taxonomy,
        'received_at': datetime.now(timezone.utc).isoformat(),
        'processed_at': datetime.now(timezone.utc).isoformat(),
        'detail': detail
    }
    if firewall_rule_id:
        receipt['firewall_rule_id'] = firewall_rule_id
    return receipt


def log_receipt(receipt):
    """Append receipt to audit log."""
    try:
        with open(RECEIPT_LOG, 'a') as f:
            f.write(json.dumps(receipt) + '\n')
    except Exception as e:
        print(f'WARNING: Could not write receipt log: {e}', file=sys.stderr)


def gate1_schema_validation(artifact):
    """Gate 1: Schema validation — check required fields and types."""
    missing = [f for f in REQUIRED_FIELDS if f not in artifact]
    if missing:
        return False, f'Missing required fields: {", ".join(missing)}'
    if artifact.get('type') not in VALID_TYPES:
        return False, f'Invalid type: {artifact.get("type")}; expected one of {VALID_TYPES}'
    if artifact.get('inference_confidence') not in VALID_CONFIDENCE:
        return False, f'Invalid inference_confidence: {artifact.get("inference_confidence")}'
    if artifact.get('schema_version') != '1.0.0':
        return False, f'Unsupported schema_version: {artifact.get("schema_version")}; expected 1.0.0'
    return True, ''


def gate2_analyst_approval(artifact):
    """Gate 2: Analyst approval check."""
    if artifact.get('analyst_approved') is not True:
        return False, 'analyst_approved is not true; artifact has not been human-approved'
    if not artifact.get('approved_by'):
        return False, 'approved_by is empty; analyst identity required'
    return True, ''


def gate3_expiry_check(artifact):
    """Gate 3: Expiry check with 60s clock skew tolerance."""
    try:
        expires_at = datetime.fromisoformat(artifact['expires_at'].replace('Z', '+00:00'))
        now = datetime.now(timezone.utc)
        if now >= expires_at + timedelta(seconds=CLOCK_SKEW_TOLERANCE):
            return False, f'artifact expired at {artifact["expires_at"]}; firewall clock is {now.isoformat()}; skew tolerance {CLOCK_SKEW_TOLERANCE}s exceeded'
    except (KeyError, ValueError) as e:
        return False, f'Cannot parse expires_at: {e}'
    return True, ''


def gate4_duplicate_check(artifact):
    """Gate 4: Duplicate check — SCAFFOLD: always returns not-duplicate."""
    # TODO: Check existing firewall rules for equivalent rule
    # For now, always pass (no duplicate detection)
    return True, ''


def gate5_apply_rule(artifact):
    """Gate 5: Apply rule — SCAFFOLD: logs intent but does NOT apply."""
    # SCAFFOLD: Log what would be applied
    action = artifact.get('proposed_action', '?')
    target = artifact.get('target', '?')
    scope = artifact.get('scope', '?')
    detail = f'SCAFFOLD: Would apply {action} on {target} scope={scope} — NOT APPLIED (executor not wired to iptables)'
    # Return a synthetic rule ID to indicate the scaffold processed it
    rule_id = f'scaffold-{uuid.uuid4().hex[:8]}'
    return True, detail, rule_id


def gate6_post_validation(artifact, rule_id):
    """Gate 6: Post-apply validation — SCAFFOLD: always passes."""
    # TODO: Run connectivity checks, rule conflict detection
    return True, ''


def process_artifact(artifact):
    """Run the 6-gate sequence. Returns (receipt_dict)."""
    rec_id = artifact.get('recommendation_id', str(uuid.uuid4()))
    case_id = artifact.get('case_id', str(uuid.uuid4()))

    # Gate 1: Schema validation
    ok, detail = gate1_schema_validation(artifact)
    if not ok:
        return make_receipt(rec_id, case_id, 'validation_failed', detail)

    # Gate 2: Analyst approval
    ok, detail = gate2_analyst_approval(artifact)
    if not ok:
        return make_receipt(rec_id, case_id, 'validation_failed', detail)

    # Gate 3: Expiry check
    ok, detail = gate3_expiry_check(artifact)
    if not ok:
        return make_receipt(rec_id, case_id, 'expired_rejected', detail)

    # Gate 4: Duplicate check
    ok, detail = gate4_duplicate_check(artifact)
    if not ok:
        return make_receipt(rec_id, case_id, 'noop_already_present', detail)

    # Gate 5: Apply rule
    ok, detail, rule_id = gate5_apply_rule(artifact)
    if not ok:
        return make_receipt(rec_id, case_id, 'validation_failed', detail)

    # Gate 6: Post-apply validation
    ok, post_detail = gate6_post_validation(artifact, rule_id)
    if not ok:
        return make_receipt(rec_id, case_id, 'rolled_back', post_detail)

    # Success
    return make_receipt(rec_id, case_id, 'applied', detail, firewall_rule_id=rule_id)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        auth = self.headers.get('Authorization', '')
        if auth != f'Bearer {AUTH_TOKEN}':
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        if self.path == '/execute':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            receipt = process_artifact(body)
            log_receipt(receipt)

            status = 200 if receipt['failure_taxonomy'] == 'applied' else 422
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(receipt).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                'status': 'ok',
                'mode': 'scaffold',
                'gates': 6,
                'receipt_log': RECEIPT_LOG
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    print(f'Firewall Executor (SCAFFOLD mode) starting on {BIND}:{PORT}')
    print(f'Receipt log: {RECEIPT_LOG}')
    print('WARNING: Gate 5 (apply rule) is a SCAFFOLD — no firewall changes will be made')
    server = HTTPServer((BIND, PORT), Handler)
    server.serve_forever()
