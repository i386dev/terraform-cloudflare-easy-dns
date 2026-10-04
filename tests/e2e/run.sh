#!/usr/bin/env bash
# End-to-end test against a real Cloudflare zone: creates records of all types
# under a label of this run, checks updates, import and the v4 to v5 migration,
# and deletes everything at the end.
#
# Requires CLOUDFLARE_API_TOKEN (DNS Edit on the zone), E2E_ZONE_ID and E2E_ZONE_NAME.
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?}" "${E2E_ZONE_ID:?}" "${E2E_ZONE_NAME:?}"
cd "$(dirname "$0")"
E2E_DIR=$(pwd)
LABEL="${E2E_LABEL:-e2e-$(date +%s)}"
export CLOUDFLARE_API_TOKEN E2E_ZONE_ID
export TF_VAR_zone_id="$E2E_ZONE_ID" TF_VAR_zone_name="$E2E_ZONE_NAME" TF_VAR_prefix="$LABEL"
export TF_IN_AUTOMATION=1 TF_INPUT=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}
pass() { echo "ok - $*"; }
tf() { terraform -chdir="${E2E_DIR}/$1" "${@:2}"; }

cleanup() {
    local rc=$?
    set +e
    for dir in v4to5 v4 v5; do
        [ -f "${E2E_DIR}/${dir}/terraform.tfstate" ] && tf "$dir" destroy -auto-approve -no-color >/dev/null
    done
    "${E2E_DIR}/sweep.sh" "$LABEL"
    rm -rf "${E2E_DIR}"/*/terraform.tfstate* "${E2E_DIR}"/*/tfplan "${E2E_DIR}"/ids*
    exit "$rc"
}
trap cleanup EXIT

# Prints how many resources a saved plan creates, deletes, updates, imports and moves
plan_summary() {
    tf "$1" plan -no-color -out=tfplan "${@:2}" >/dev/null
    tf "$1" show -json tfplan | jq -r '
        [.resource_changes[]? | select(.mode == "managed")] as $rc |
        "create=\([$rc[] | select(.change.actions | index("create"))] | length) " +
        "delete=\([$rc[] | select(.change.actions | index("delete"))] | length) " +
        "update=\([$rc[] | select(.change.actions == ["update"])] | length) " +
        "import=\([$rc[] | select(.change.importing)] | length) " +
        "move=\([$rc[] | select(.previous_address and .previous_address != .address)] | length)"'
}

# Prints "<record key> <Cloudflare record ID>" for the records in the state, sorted by key
record_ids() {
    tf "$1" show -json | jq -r '
        [.. | objects | select(.mode? == "managed" and (.type? == "cloudflare_dns_record" or .type? == "cloudflare_record"))]
        | map("\(.index) \(.values.id)") | sort[]'
}

# Fails unless two lists of record IDs are the same: no record was recreated
assert_same_ids() {
    [ -s "$2" ] || fail "$1: no records in the state"
    diff -u "$2" "$3" >"${E2E_DIR}/ids.diff" || fail "$1: record IDs differ: $(head -40 "${E2E_DIR}/ids.diff")"
}

# Fails when the plan has any change: the provider would show a perpetual diff
assert_no_changes() {
    local rc=0
    tf "$1" plan -no-color -detailed-exitcode "${@:2}" >"${E2E_DIR}/plan.log" || rc=$?
    [ "$rc" -eq 0 ] || fail "$1: expected no changes, plan exit code $rc: $(grep -E '^  #|~ |\+ |- ' "${E2E_DIR}/plan.log" | head -40)"
}

echo "Label: ${LABEL}, zone: ${E2E_ZONE_NAME}"
"${E2E_DIR}/sweep.sh" --stale

for dir in v5 import v4 v4to5; do tf "$dir" init -no-color >/dev/null; done

# Scenario 1: create all record types, then check there is no drift
tf v5 apply -auto-approve -no-color >"${E2E_DIR}/apply.log" || fail "apply: $(tail -40 "${E2E_DIR}/apply.log")"
count=$(tf v5 state list | grep -c 'cloudflare_dns_record.record\[')
pass "created ${count} records of all types"
assert_no_changes v5
pass "no drift after apply"

# Changing a value without a key replaces the record, with a key updates it in place
summary=$(plan_summary v5 -var a_value=192.0.2.20 -var txt_value=rotation=2)
[ "$summary" = "create=1 delete=1 update=1 import=0 move=0" ] || fail "value changes: ${summary}"
tf v5 apply -auto-approve -no-color tfplan >/dev/null
assert_no_changes v5 -var a_value=192.0.2.20 -var txt_value=rotation=2
pass "value change: record without key replaced, record with key updated in place"
record_ids v5 >"${E2E_DIR}/ids-v5.txt"

# The report of unmanaged records lists a record created outside the module, and none
# of the records of the module. Only records of this run are compared, since the zone
# has records of other tools. The stray record is deleted by sweep.sh (same comment
# and label)
api="https://api.cloudflare.com/client/v4/zones/${E2E_ZONE_ID}/dns_records"
stray_id=$(curl -fsS -X POST -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "$api" \
    -d "$(jq -n --arg name "stray.${LABEL}.${E2E_ZONE_NAME}" '{type: "TXT", name: $name, content: "\"easy-dns stray\"", ttl: 300, comment: "easy-dns-e2e"}')" | jq -r .result.id)
[ -n "$stray_id" ] && [ "$stray_id" != null ] || fail "could not create the stray record"
tf v5 plan -no-color -out=tfplan -var a_value=192.0.2.20 -var txt_value=rotation=2 -var report_unmanaged=true >"${E2E_DIR}/plan.log" 2>&1 ||
    fail "plan with report_unmanaged: $(grep -E 'Error' "${E2E_DIR}/plan.log" | head -20)"
reported=$(tf v5 show -json tfplan | jq -r --arg label "$LABEL" '[.planned_values.outputs.unmanaged_records.value[] | select(.name | contains($label)) | .id] | sort | join(" ")')
[ "$reported" = "$stray_id" ] || fail "report_unmanaged: expected only ${stray_id} of this run, got '${reported}'"
grep -q "records that the configuration does not describe" "${E2E_DIR}/plan.log" || fail "report_unmanaged: no plan warning"
pass "report_unmanaged lists the stray record and none of the module"

# Scenario 2: the same records are adopted into an empty state. Provider v5 plans a
# one-time update without visible changes for imported structured records (SRV, ...)
summary=$(plan_summary import -var a_value=192.0.2.20 -var txt_value=rotation=2)
case "$summary" in
    "create=0 delete=0 update="*" import=${count} move=0") ;;
    *) fail "import: ${summary}, expected import=${count} and nothing created or deleted" ;;
esac
tf import apply -auto-approve -no-color tfplan >/dev/null
assert_no_changes import -var a_value=192.0.2.20 -var txt_value=rotation=2
# Every record was adopted with the ID of the record created in scenario 1
record_ids import >"${E2E_DIR}/ids-import.txt"
assert_same_ids "import" "${E2E_DIR}/ids-v5.txt" "${E2E_DIR}/ids-import.txt"
# The records stay managed by the state of scenario 1, which deletes them
rm -f "${E2E_DIR}/import/terraform.tfstate"*
pass "all ${count} records imported, no drift afterwards (${summary})"

# Scenario 3: records created with provider v4 are moved to v5 without recreation
tf v4 apply -auto-approve -no-color >"${E2E_DIR}/apply.log" || fail "v4 apply: $(tail -40 "${E2E_DIR}/apply.log")"
assert_no_changes v4
pass "provider v4: created records without drift"
record_ids v4 >"${E2E_DIR}/ids-v4.txt"
cp "${E2E_DIR}/v4/terraform.tfstate" "${E2E_DIR}/v4to5/terraform.tfstate"
rm -f "${E2E_DIR}/v4/terraform.tfstate"
summary=$(plan_summary v4to5)
case "$summary" in
    "create=0 delete=0 "*) ;;
    *) fail "v4 to v5 migration: ${summary}" ;;
esac
# Provider v5 may report an inconsistent modified_on (different precision than in the
# migrated state) for some records on this first apply; the records are updated and
# the next plan is empty, so only this error is tolerated until
# https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387 is fixed
only_modified_on_inconsistency() {
    local attributes
    grep -q "Provider produced inconsistent result after apply" "$1" || return 1
    attributes=$(grep -oE "unexpected new value: \.[a-z_]+" "$1" | sed 's/.*\.//' | sort -u)
    [ "$attributes" = "modified_on" ]
}
if ! tf v4to5 apply -auto-approve -no-color tfplan >"${E2E_DIR}/apply.log" 2>&1; then
    only_modified_on_inconsistency "${E2E_DIR}/apply.log" || fail "v4 to v5 apply: $(tail -40 "${E2E_DIR}/apply.log")"
    echo "note: provider reported the known modified_on inconsistency after the migration"
fi
assert_no_changes v4to5
# The same records under the same keys: moved, not recreated
record_ids v4to5 >"${E2E_DIR}/ids-v4to5.txt"
assert_same_ids "v4 to v5 migration" "${E2E_DIR}/ids-v4.txt" "${E2E_DIR}/ids-v4to5.txt"
pass "v4 to v5 migration without recreating records, same IDs (${summary})"

echo "All end-to-end checks passed"
