#!/usr/bin/env python3
"""Checks schema/records.schema.json: valid documents must pass and documents with
typical mistakes must fail. Requires the jsonschema and pyyaml packages.

With --terraform, the same documents also go through the root module (terraform test
with a mocked provider, yamldecode like examples/yaml), and the module must accept
and reject the same documents as the schema, except for KNOWN_DIFFERENCES."""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml
from jsonschema import Draft7Validator, FormatChecker

ROOT = Path(__file__).resolve().parent.parent
validator = Draft7Validator(json.loads((ROOT / "schema/records.schema.json").read_text()), format_checker=FormatChecker())

VALID = {
    "all record types (tests/fixtures/all-types.yaml)": (ROOT / "tests/fixtures/all-types.yaml").read_text(),
    "null MX": 'records: { "@": { MX: [{ content: ".", priority: 0 }] } }',
    "unquoted N as LOC lat_direction": 'records: { o: { LOC: [{ data: { lat_degrees: 1, lat_minutes: 1, lat_seconds: 1, lat_direction: N, long_degrees: 1, long_minutes: 1, long_seconds: 1, long_direction: E } }] } }',
    "numbers as strings in data": """
records:
  _sip._tcp:
    SRV: [{ data: { priority: "10", weight: "5", port: "5060", target: sip.example.com } }]
""",
    "empty records": "records: {}",
}

INVALID = {
    "misspelled attribute": 'records: { app: { A: [{ content: 192.0.2.10, proxid: true }] } }',
    "misspelled setting": 'records: { app: { AAAA: [{ content: "2001:db8::1", settings: { ipv6_onyl: true } }] } }',
    "unknown record type": 'records: { app: { CNAMe: [{ content: target.example.net }] } }',
    "TTL as text": 'records: { app: { A: [{ content: 192.0.2.10, ttl: 5m }] } }',
    "TTL out of range": 'records: { app: { A: [{ content: 192.0.2.10, ttl: 5 }] } }',
    "proxied as text": 'records: { app: { A: [{ content: 192.0.2.10, proxied: "yes" }] } }',
    "proxied TXT": 'records: { app: { TXT: [{ content: x, proxied: true }] } }',
    "IPv6 in A": 'records: { app: { A: [{ content: "2001:db8::1" }] } }',
    "invalid IPv4": 'records: { app: { A: [{ content: 192.168.1.300 }] } }',
    "IPv4 in AAAA": 'records: { app: { AAAA: [{ content: 192.0.2.1 }] } }',
    "missing content": 'records: { app: { A: [{ ttl: 300 }] } }',
    "MX without priority": 'records: { app: { MX: [{ content: mx.example.com }] } }',
    "CAA with an unknown tag": 'records: { app: { CAA: [{ content: letsencrypt.org, tag: isue }] } }',
    "SRV without port": 'records: { _sip._tcp: { SRV: [{ data: { priority: 10, weight: 5, target: sip.example.com } }] } }',
    "SRV with an unknown field": 'records: { _sip._tcp: { SRV: [{ data: { priority: 10, weight: 5, port: 1, target: x, proto: _tcp } }] } }',
    "data on an A record": 'records: { app: { A: [{ content: 192.0.2.10, data: { target: x } }] } }',
    "URI without priority": 'records: { _ftp._tcp: { URI: [{ data: { weight: 1, target: "ftp://x/" } }] } }',
    "LOC with an invalid direction": 'records: { o: { LOC: [{ data: { lat_degrees: 1, lat_minutes: 1, lat_seconds: 1, lat_direction: X, long_degrees: 1, long_minutes: 1, long_seconds: 1, long_direction: E } }] } }',
    "invalid name": 'records: { "my app": { A: [{ content: 192.0.2.10 }] } }',
    "invalid alias": 'records: { app: { ALIASES: [{ content: -bad }] } }',
    "key with whitespace": 'records: { app: { TXT: [{ content: x, key: "my key" }] } }',
    "record that is not an object": 'records: { app: { A: [192.0.2.10] } }',
    "CNAME to an IP address": 'records: { app: { CNAME: [{ content: 192.0.2.1 }] } }',
    "CNAME with a space": 'records: { app: { CNAME: [{ content: "a b.example.net" }] } }',
    "MX with an IP address": 'records: { "@": { MX: [{ content: 192.0.2.1., priority: 10 }] } }',
    "NS with a label over 63 characters": 'records: { sub: { NS: [{ content: ' + "a" * 64 + '.example.net }] } }',
    "SRV target with a space": 'records: { _sip._tcp: { SRV: [{ data: { priority: 1, weight: 1, port: 1, target: "a b" } }] } }',
    "HTTPS target @": 'records: { "@": { HTTPS: [{ data: { priority: 1, target: "@" } }] } }',
    "NAPTR replacement URL": 'records: { sip: { NAPTR: [{ data: { order: 1, preference: 1, replacement: "http://x/" } }] } }',
    "null MX with a priority other than 0": 'records: { "@": { MX: [{ content: ".", priority: 10 }] } }',
    "unquoted boolean in data": 'records: { svc: { SVCB: [{ data: { priority: 1, target: ".", value: off } }] } }',
    "unquoted boolean in tags": 'records: { app: { A: [{ content: 192.0.2.10, tags: [off] }] } }',
    "fractional TTL": 'records: { app: { A: [{ content: 192.0.2.10, ttl: 60.5 }] } }',
    "fractional priority": 'records: { "@": { MX: [{ content: mail.example.com, priority: 10.5 }] } }',
}

# Documents that only the module can reject: the checks compare records with each other
# or with other inputs, which a schema of single values cannot do
TERRAFORM_ONLY = {
    "duplicate record": 'records: { app: { A: [{ content: 192.0.2.1 }, { content: 192.0.2.1 }] } }',
    "same record in two name forms": 'records: { www: { A: [{ content: 192.0.2.1 }] }, www.example.com: { A: [{ content: 192.0.2.1 }] } }',
    "CNAME next to other records": 'records: { app: { A: [{ content: 192.0.2.1 }], CNAME: [{ content: target.example.net }] } }',
    "CNAME to its own name": 'records: { app: { CNAME: [{ content: app.example.com. }] } }',
    "TTL below minimum_ttl": 'records: { app: { A: [{ content: 192.0.2.1, ttl: 30 }] } }',
    "wildcard after combining a prefix": 'records: { "*": { _acme-challenge.TXT: [{ content: x }] } }',
    "name over 253 characters with the zone": 'records: { ' + '.'.join(['a' * 63] * 3) + ': { ' + 'b' * 63 + '.TXT: [{ content: x }] } }',
}

# Documents that the schema rejects and the module accepts on purpose, with the reason
KNOWN_DIFFERENCES = {}


def terraform_results(documents):
    """Plans each document with the root module; returns {name: (accepted, output)}."""
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp).resolve()
        (work / "tests").mkdir()
        (work / "docs").mkdir()
        (work / "main.tf").write_text(f"""
terraform {{
  required_providers {{
    cloudflare = {{
      source = "cloudflare/cloudflare"
    }}
  }}
}}

variable "yaml" {{
  type = string
}}

module "dns" {{
  source    = "{os.path.relpath(ROOT, work)}"
  zone_id   = "z"
  zone_name = "example.com"
  records   = yamldecode(var.yaml).records
}}
""")
        names = list(documents)
        for i, name in enumerate(names):
            (work / "docs" / f"{i}.yaml").write_text(documents[name])
            (work / "tests" / f"doc{i}.tftest.hcl").write_text(f"""
mock_provider "cloudflare" {{}}

run "document" {{
  command = plan

  variables {{
    yaml = file("docs/{i}.yaml")
  }}
}}
""")
        init = subprocess.run(["terraform", "init", "-backend=false", "-input=false", "-no-color"], cwd=work, capture_output=True, text=True)
        if init.returncode:
            sys.exit(f"terraform init failed:\n{init.stdout}{init.stderr}")
        output = subprocess.run(["terraform", "test", "-json"], cwd=work, capture_output=True, text=True)
        status, diagnostics = {}, {}
        for line in output.stdout.splitlines():
            event = json.loads(line)
            testfile = event.get("@testfile")
            if event.get("type") == "test_run" and event["test_run"].get("status"):
                status[testfile] = event["test_run"]["status"]
            elif event.get("type") == "diagnostic" and testfile:
                diagnostic = event["diagnostic"]
                diagnostics.setdefault(testfile, []).append(f"{diagnostic['summary']}: {diagnostic.get('detail', '')}")
        results = {}
        for i, name in enumerate(names):
            testfile = f"tests/doc{i}.tftest.hcl"
            if testfile not in status:
                sys.exit(f"no result for {name!r} in the terraform test output:\n{output.stdout}{output.stderr}")
            results[name] = (status[testfile] == "pass", "\n".join(diagnostics.get(testfile, [])))
        return results


failures = 0
for name, document in VALID.items():
    errors = list(validator.iter_errors(yaml.safe_load(document)))
    if errors:
        failures += 1
        print(f"FAIL: {name} should be valid: {errors[0].message} at {list(errors[0].absolute_path)}")
    else:
        print(f"ok - valid: {name}")
for name, document in TERRAFORM_ONLY.items():
    errors = list(validator.iter_errors(yaml.safe_load(document)))
    if errors:
        failures += 1
        print(f"FAIL: {name} has only valid values, the schema should accept it: {errors[0].message}")
    else:
        print(f"ok - valid values: {name}")
for name, document in INVALID.items():
    if validator.is_valid(yaml.safe_load(document)):
        failures += 1
        print(f"FAIL: {name} should be invalid")
    else:
        print(f"ok - rejected: {name}")

if "--terraform" in sys.argv:
    results = terraform_results({**VALID, **INVALID, **TERRAFORM_ONLY})
    for name in VALID:
        accepted, output = results[name]
        if accepted:
            print(f"ok - terraform accepts: {name}")
        else:
            failures += 1
            print(f"FAIL: terraform rejects {name}, which the schema accepts:\n{output}")
    for name in INVALID:
        accepted, output = results[name]
        if name in KNOWN_DIFFERENCES:
            if accepted:
                print(f"ok - terraform accepts: {name} (known difference: {KNOWN_DIFFERENCES[name]})")
            else:
                failures += 1
                print(f"FAIL: terraform now rejects {name}; remove it from KNOWN_DIFFERENCES")
        elif accepted:
            failures += 1
            print(f"FAIL: terraform accepts {name}, which the schema rejects")
        # Rejected at plan by the module (validations, preconditions) or by the
        # provider schema (LOC directions, ...); anything else is an error of this test
        elif not re.match(r"(Invalid value for (input )?variable|.*precondition failed|Invalid Attribute Value)", output):
            failures += 1
            print(f"FAIL: terraform rejects {name}, but not in a validation:\n{output}")
        else:
            print(f"ok - terraform rejects: {name}")
    for name in TERRAFORM_ONLY:
        accepted, output = results[name]
        if accepted:
            failures += 1
            print(f"FAIL: terraform accepts {name}")
        else:
            print(f"ok - terraform rejects: {name} (not checked by the schema)")

for path in (a for a in sys.argv[1:] if a != "--terraform"):
    errors = list(validator.iter_errors(yaml.safe_load(Path(path).read_text()) or {}))
    print(f"{'ok' if not errors else 'FAIL'} - {path}" + (f": {errors[0].message}" if errors else ""))
    failures += bool(errors)

sys.exit(1 if failures else 0)
