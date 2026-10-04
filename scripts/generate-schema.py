#!/usr/bin/env python3
"""Generates schema/records.schema.json, a JSON Schema for records written in YAML
or JSON (e.g. a dns.yaml passed through yamldecode), for completion and validation
in editors.

The data fields of structured records are read from the validation of the records
module, and the record attributes are checked against its typed records, so the
schema cannot drift from the module."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "modules/dns/records/variables.tf"
OUT = ROOT / "schema/records.schema.json"

LABEL = r"[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?"
NAME = rf"(\*|{LABEL})(\.{LABEL})*"


def hostname(description, *special):
    """A DNS name like the module checks it: labels, at most 253 characters without the
    trailing dot, not an IPv4 address; special values (\"@\", \".\") are allowed as well."""
    name = {
        "pattern": rf"^{LABEL}(\.{LABEL})*\.?$",
        "not": {"pattern": r"^([0-9]{1,3}\.){3}[0-9]{1,3}\.?$"},
        "anyOf": [{"maxLength": 253}, {"maxLength": 254, "pattern": r"\.$"}],
    }
    return {"description": description, "type": "string", "anyOf": [{"enum": list(special)}, name] if special else [name]}


# Data fields that hold a hostname, checked like CNAME targets; "." is the root
DATA_HOSTNAMES = {("SRV", "target"), ("HTTPS", "target"), ("SVCB", "target"), ("NAPTR", "replacement")}

# Data fields with numeric values; Terraform also accepts them as strings
NUMERIC = {
    "priority", "weight", "port", "usage", "selector", "matching_type", "algorithm", "type",
    "key_tag", "digest_type", "protocol", "order", "preference", "lat_degrees", "lat_minutes",
    "lat_seconds", "long_degrees", "long_minutes", "long_seconds", "altitude", "size",
    "precision_horz", "precision_vert",
}
ENUMS = {"lat_direction": ["N", "S"], "long_direction": ["E", "W"]}


def core_text():
    return CORE.read_text()


def data_fields():
    """Returns ({type: allowed fields}, {type: required fields}) from the core validation."""
    text = core_text()

    def parse(marker):
        start = text.index(marker) + len(marker)
        block = text[start:text.index("}, kind, [])", start)]
        fields = {}
        for name, values in re.findall(r"([A-Z]+)\s*=\s*\[([^\]]*)\]", block):
            fields[name] = re.findall(r'"([a-z_0-9]+)"', values)
        return fields

    allowed = parse("[for field in setsubtract(keys(coalesce(rec.data, {})), lookup({")
    required = parse("[for field in setsubtract(lookup({")
    return allowed, required


def core_attributes(indent):
    block = re.search(r'variable "records" \{.*?\n\}', core_text(), re.S).group(0)
    return sorted(re.findall(rf"^ {{{indent}}}([a-z0-9_]+) +=.*optional\(", block, re.M))


def number_or_string():
    return {"type": ["number", "string"]}


def schema():
    allowed, required = data_fields()

    common = {
        "ttl": {
            "description": "TTL in seconds, 1 for automatic (default: default_ttl)",
            "anyOf": [{"const": 1}, {"type": "integer", "minimum": 30, "maximum": 86400}],
        },
        "key": {
            "description": "Stable key instead of the value in the record key, so changing the value updates the record in place",
            "type": "string", "pattern": r"^\S+$",
        },
        "comment": {"description": "Comment shown in the Cloudflare dashboard (default: default_comment)", "type": "string"},
        "tags": {"description": "Tags, added to default_tags", "type": "array", "items": {"type": "string"}},
        "settings": {
            "description": "Record settings (provider v5 only)",
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "flatten_cname": {"type": "boolean"},
                "ipv4_only": {"type": "boolean"},
                "ipv6_only": {"type": "boolean"},
            },
        },
    }
    proxied = {"proxied": {"description": "Proxied by Cloudflare (default: default_proxied)", "type": "boolean"}}

    def record(properties, required_fields, description):
        return {
            "description": description,
            "type": "object",
            "additionalProperties": False,
            "required": required_fields,
            "properties": {**common, **properties},
        }

    types = {
        "A": record({**proxied, "content": {"description": "IPv4 address", "type": "string", "format": "ipv4"}}, ["content"], "A record"),
        "AAAA": record({**proxied, "content": {"description": "IPv6 address", "type": "string", "format": "ipv6"}}, ["content"], "AAAA record"),
        "CNAME": record({**proxied, "content": hostname("Target hostname, @ for the zone apex", "@")}, ["content"], "CNAME record"),
        "ALIASES": record(
            {**proxied, "content": {"description": "Name of a CNAME pointing to this name", "type": "string", "pattern": f"^{NAME}$"}},
            ["content"], "CNAMEs pointing to this name (or to the prefixed name)",
        ),
        "NS": record({"content": hostname("Name server hostname", "@")}, ["content"], "NS record"),
        "PTR": record({"content": hostname("Hostname", "@")}, ["content"], "PTR record"),
        "TXT": record({"content": {"description": "Text value", "type": "string", "maxLength": 2048}}, ["content"], "TXT record"),
        "OPENPGPKEY": record({"content": {"description": "Public key", "type": "string"}}, ["content"], "OPENPGPKEY record (provider v5 only)"),
        "MX": {
            **record(
                {"content": hostname("Mail server hostname, . for a null MX (RFC 7505)", "@", "."), "priority": {"description": "Priority, lower is preferred (0 for a null MX)", "type": "integer"}},
                ["content", "priority"], "MX record",
            ),
            # A null MX (RFC 7505) has preference 0
            "if": {"properties": {"content": {"const": "."}}, "required": ["content"]},
            "then": {"properties": {"priority": {"const": 0}}},
        },
        "CAA": record(
            {
                "content": {"description": "Value, e.g. letsencrypt.org", "type": "string"},
                "tag": {"description": "Property", "enum": ["issue", "issuewild", "iodef"]},
                "flags": {"description": "Flags (default: 0)", "type": "integer"},
            },
            ["content", "tag"], "CAA record",
        ),
    }
    for record_type, fields in sorted(allowed.items()):
        data = {
            "description": f"{record_type} fields",
            "type": "object",
            "additionalProperties": False,
            "required": required.get(record_type, []),
            "properties": {
                field: ENUMS.get(field) and {"enum": ENUMS[field]}
                or ((record_type, field) in DATA_HOSTNAMES and hostname("Hostname, . for none", "."))
                or (number_or_string() if field in NUMERIC and not (record_type == "NAPTR" and field == "flags") else {"type": "string"})
                for field in fields
            },
        }
        if record_type == "DNSKEY":
            data["properties"]["flags"] = number_or_string()
        properties = {"data": data}
        required_fields = ["data"]
        if record_type == "URI":
            properties["priority"] = {"description": "Priority, lower is preferred", "type": "integer"}
            required_fields.append("priority")
        types[record_type] = record(properties, required_fields, f"{record_type} record")

    # The schema must describe exactly the attributes of the typed records of the module
    attributes = sorted({a for t in types.values() for a in t["properties"]})
    if attributes != core_attributes(10):
        sys.exit(f"Record attributes {attributes} differ from the module: {core_attributes(10)}")
    if sorted(common["settings"]["properties"]) != core_attributes(12):
        sys.exit("Settings attributes differ from the module")

    record_types = {
        rf"^({NAME}\.)?{name}$": {"type": "array", "items": {"$ref": f"#/definitions/{name}"}}
        for name in sorted(types)
    }
    return {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": "https://raw.githubusercontent.com/i386dev/terraform-cloudflare-easy-dns/main/schema/records.schema.json",
        "title": "easy-dns records",
        "description": "DNS records of the easy-dns Terraform module: a document with a records key, as passed through yamldecode",
        "type": "object",
        "properties": {"records": {"$ref": "#/definitions/records"}},
        "definitions": {
            "records": {
                "description": "records[NAME][TYPE] = [RECORD, ...]; NAME is a name within the zone (@ for the apex)",
                "type": "object",
                "propertyNames": {"pattern": f"^(@|{NAME})$"},
                "additionalProperties": {
                    "description": "Record types, optionally with a prefix, e.g. _acme-challenge.TXT",
                    "type": "object",
                    "patternProperties": record_types,
                    "additionalProperties": False,
                },
            },
            **types,
        },
    }


if __name__ == "__main__":
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(schema(), indent=2) + "\n")
    print(f"Generated {OUT.relative_to(ROOT)}")
