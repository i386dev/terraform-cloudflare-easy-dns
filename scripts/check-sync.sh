#!/usr/bin/env sh
# Checks that the copies of the module interface are the same: the root module
# repeats the variables and outputs of the v5 wrapper, and both wrappers share
# the records variable.
set -eu

cd "$(dirname "$0")/.."
status=0

if ! diff -u modules/dns/v5/variables.tf variables.tf; then
    echo "variables.tf differs from modules/dns/v5/variables.tf" >&2
    status=1
fi

outputs() { grep -E '^output ' "$1"; }
if [ "$(outputs modules/dns/v5/outputs.tf)" != "$(outputs outputs.tf)" ]; then
    echo "outputs.tf does not have the outputs of modules/dns/v5/outputs.tf" >&2
    status=1
fi

records() { awk '/^variable "records"/, /^}/' "$1"; }
# The v4 wrapper has the variables of the v5 wrapper except import_existing and
# report_unmanaged (provider v4 has no lookup of existing records)
without_import() { awk '/^variable "(import_existing|report_unmanaged)"/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0; getline }' "$1"; }
if ! without_import modules/dns/v5/variables.tf | diff -u - modules/dns/v4/variables.tf; then
    echo "The variables of modules/dns/v4 differ from modules/dns/v5 (other than import_existing and report_unmanaged)" >&2
    status=1
fi
# Both wrappers check the text values of records the same way
text_checks() { grep -E '^  text_data_fields' "$1"; awk '/^check "records_text_values_are_strings"/, /^}/' "$1"; }
if [ "$(text_checks modules/dns/v4/main.tf)" != "$(text_checks modules/dns/v5/main.tf)" ]; then
    echo "The check of text values differs between modules/dns/v4/main.tf and modules/dns/v5/main.tf" >&2
    status=1
fi
# The entry points accept records as any and check attribute names themselves; the
# allowed names must be the attributes of the typed records in the core module
core_attributes() { records modules/dns/records/variables.tf | sed -nE "s/^ {$1}([a-z0-9_]+) +=.*optional\(.*/\1/p" | sort; }
allowed() { grep -oE "\\[\"$1\"[^]]*\\]" modules/dns/v5/variables.tf | head -n 1 | grep -oE '[a-z0-9_]+' | sort; }
if [ "$(core_attributes 10)" != "$(allowed content)" ]; then
    echo "The allowed record attributes in modules/dns/v5/variables.tf differ from the records type of modules/dns/records" >&2
    status=1
fi
if [ "$(core_attributes 12)" != "$(allowed flatten_cname)" ]; then
    echo "The allowed settings attributes in modules/dns/v5/variables.tf differ from the records type of modules/dns/records" >&2
    status=1
fi

[ "$status" -eq 0 ] && echo "Module interfaces are in sync"
exit "$status"
