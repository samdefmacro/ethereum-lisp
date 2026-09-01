#!/usr/bin/env bash
set -euo pipefail

# Read-only validator-duty evidence around an explicitly authorized state-file
# creation. This broker never enters validator containers or reads their mounts,
# environment, keys, passwords, keystores, or slashing-protection database.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-status}"
host="${HOODI_VALIDATOR_HOST:-test-ethereum-server}"
validator="${HOODI_VALIDATOR_CONTAINER:-}"
indices="${HOODI_VALIDATOR_INDICES:-}"
cl_container="${HOODI_VALIDATOR_CL_CONTAINER:-}"
el_container="${HOODI_VALIDATOR_EL_CONTAINER:-}"
el_revision="${HOODI_VALIDATOR_EL_REVISION:-}"
beacon_url="${HOODI_VALIDATOR_BEACON_URL:-http://127.0.0.1:5052}"
state_file="${HOODI_VALIDATOR_STATE:-}"
required_soak_seconds=1209600

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_clean_checkout() {
    [ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ] ||
        fail "mutation requires a clean checkout"
}

case "$action" in start|status|complete) ;; *) fail "usage: $0 start|status|complete" ;; esac
case "$host" in *[!A-Za-z0-9_.@-]*|'') fail "unsafe SSH host: $host" ;; esac
for name in "$validator" "$cl_container" "$el_container"; do
    case "$name" in *[!A-Za-z0-9_.-]*|'') fail "validator, CL, and EL container names must be explicit safe Docker names" ;; esac
done
case "$indices" in
    ''|,*|*,|*,,*|*[!0-9,]*) fail "HOODI_VALIDATOR_INDICES must be an explicit comma-separated list of decimal validator indices" ;;
esac
case "$beacon_url" in
    http://127.0.0.1:[0-9]*|http://localhost:[0-9]*) ;;
    *) fail "Beacon REST URL must be an explicit loopback http://127.0.0.1:PORT or http://localhost:PORT URL" ;;
esac
beacon_port="${beacon_url##*:}"
case "$beacon_port" in *[!0-9]*|'') fail "Beacon REST port must be decimal" ;; esac
[ "$beacon_port" -ge 1 ] && [ "$beacon_port" -le 65535 ] || fail "Beacon REST port is out of range"
case "$el_revision" in *[!0-9a-f]*|'') fail "HOODI_VALIDATOR_EL_REVISION must be the exact full lowercase hexadecimal live EL revision" ;; esac
[ "${#el_revision}" -eq 40 ] || fail "HOODI_VALIDATOR_EL_REVISION must contain exactly 40 hexadecimal characters"
git -C "$repo_root" merge-base --is-ancestor "$el_revision" HEAD ||
    fail "live EL revision $el_revision is not an ancestor of checkout HEAD"

# Reject duplicate and non-canonical decimal spellings without converting the
# values through a fixed-width shell integer.
IFS=',' read -r -a index_values <<<"$indices"
seen=,
for index in "${index_values[@]}"; do
    case "$index" in 0|[1-9]|[1-9][0-9]*) ;; *) fail "validator index is not canonical decimal: $index" ;; esac
    case "$seen" in *",$index,"*) fail "duplicate validator index: $index" ;; esac
    seen="${seen}${index},"
done
index_count="${#index_values[@]}"

case "$state_file" in
    '') [ "$action" != complete ] || fail "complete requires HOODI_VALIDATOR_STATE from start output" ;;
    /data/hoodi-sec5-validator-soak-*)
        case "$state_file" in *'..'*|*[!A-Za-z0-9_./-]*) fail "unsafe validator soak state path" ;; esac
        ;;
    *) fail "HOODI_VALIDATOR_STATE must be below /data/hoodi-sec5-validator-soak-*" ;;
esac

if [ "$action" = start ]; then
    [ -z "$state_file" ] || fail "start chooses a unique state path; do not set HOODI_VALIDATOR_STATE"
    # The completed seven-day shadow comparison is the first start prerequisite
    # and is intentionally invoked through its existing read-only broker.
    "$repo_root/scripts/hoodi-shadow-gate.sh" complete
    [ "${HOODI_VALIDATOR_ALLOW_MUTATION:-}" = 1 ] ||
        fail "start creates remote state; set HOODI_VALIDATOR_ALLOW_MUTATION=1 only after explicit authorization"
    require_clean_checkout
fi

ssh "$host" bash -s -- "$action" "$validator" "$indices" "$index_count" \
    "$cl_container" "$el_container" "$el_revision" "$beacon_url" \
    "$state_file" "$required_soak_seconds" <<'REMOTE'
set -euo pipefail
action="$1"; validator="$2"; indices="$3"; index_count="$4"; cl="$5"
el="$6"; expected_revision="$7"; beacon_url="$8"; state_file="$9"
required_soak="${10}"

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for fail-closed Beacon REST decoding" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }

running() {
    [ "$(docker container inspect --format '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}
container_fingerprint() {
    docker container inspect --format '{{.Id}}|{{.Image}}' "$1" | sha256sum | awk '{print $1}'
}
image_revision() {
    image_id="$(docker container inspect --format '{{.Image}}' "$1")"
    docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image_id"
}
container_revision() {
    docker container inspect --format '{{ index .Config.Labels "io.ethereum-lisp.gate-revision" }}' "$1"
}
beacon() {
    curl --fail --silent --show-error --max-time 15 --header 'Accept: application/json' "$beacon_url$1"
}
sha_text() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
state_value() {
    key="$1"
    value="$(awk -F= -v wanted="$key" '$1 == wanted {if (seen++) exit 2; print substr($0, index($0, "=") + 1)} END {if (!seen) exit 3}' "$state_file")" || {
        echo "state field is absent or duplicated: $key" >&2; exit 1;
    }
    printf '%s\n' "$value"
}
assert_state_file() {
    [ -f "$state_file" ] && [ ! -L "$state_file" ] || {
        echo "state must be a regular non-symlink file" >&2; exit 1;
    }
    [ "$(stat -c '%a' "$state_file")" = 400 ] || {
        echo "state file must retain reviewed mode 0400" >&2; exit 1;
    }
}
hex64() { case "$2" in *[!0-9a-f]*|'') echo "invalid $1 in state" >&2; exit 1 ;; esac; [ "${#2}" -eq 64 ] || { echo "invalid $1 length in state" >&2; exit 1; }; }
decimal() { case "$2" in *[!0-9]*|'') echo "invalid $1 in state" >&2; exit 1 ;; esac; }

assert_live() {
    running "$validator" || { echo "explicit validator container is not running" >&2; exit 1; }
    running "$cl" || { echo "consensus container is not running" >&2; exit 1; }
    running "$el" || { echo "execution container is not running" >&2; exit 1; }
    [ "$(container_revision "$el")" = "$expected_revision" ] || { echo "live EL container revision mismatch" >&2; exit 1; }
    [ "$(image_revision "$el")" = "$expected_revision" ] || { echo "live EL image revision mismatch" >&2; exit 1; }

    sync_json="$(beacon /eth/v1/node/syncing)"
    printf '%s' "$sync_json" | jq -e '
      (.data | type == "object") and
      (.data.is_syncing == false) and
      (.data.is_optimistic == false) and
      (.data.el_offline == false)' >/dev/null || {
        echo "CL must be synchronized, non-optimistic, and report its EL online" >&2; exit 1;
    }
    genesis_json="$(beacon /eth/v1/beacon/genesis)"
    genesis_time="$(printf '%s' "$genesis_json" | jq -er '.data.genesis_time | select(type == "string" and test("^[0-9]+$"))')"
    genesis_root="$(printf '%s' "$genesis_json" | jq -er '.data.genesis_validators_root | select(type == "string" and test("^0x[0-9a-fA-F]{64}$"))')"
    head_json="$(beacon /eth/v1/beacon/headers/head)"
    printf '%s' "$head_json" | jq -e '
      .execution_optimistic == false and
      .data.canonical == true and
      (.data.header.message.slot | type == "string" and test("^[0-9]+$")) and
      (.data.header.message.proposer_index | type == "string" and test("^[0-9]+$"))' >/dev/null
    head_slot="$(printf '%s' "$head_json" | jq -er '.data.header.message.slot')"
}

assert_live
validator_fingerprint="$(container_fingerprint "$validator")"
cl_fingerprint="$(container_fingerprint "$cl")"
el_fingerprint="$(container_fingerprint "$el")"
indices_digest="$(sha_text "$indices")"
genesis_digest="$(sha_text "$genesis_root")"
now="$(date +%s)"

case "$action" in
start)
    [ "$now" -ge "$genesis_time" ] || { echo "host time precedes Beacon genesis" >&2; exit 1; }
    start_epoch="$(( (now - genesis_time) / 384 ))"
    end_time="$(( now + required_soak ))"
    end_epoch="$(( (end_time - 1 - genesis_time) / 384 ))"
    nonce="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    state_file="/data/hoodi-sec5-validator-soak-${now}-${nonce}"
    umask 077
    set -C
    exec 3>"$state_file" || { echo "refusing existing state path" >&2; exit 1; }
    printf '%s\n' \
        'format=hoodi-validator-soak-v1' \
        "start_time=$now" \
        "end_time=$end_time" \
        "required_seconds=$required_soak" \
        "first_epoch=$start_epoch" \
        "last_epoch=$end_epoch" \
        "validator_count=$index_count" \
        "indices_digest=$indices_digest" \
        "validator_fingerprint=$validator_fingerprint" \
        "cl_fingerprint=$cl_fingerprint" \
        "el_fingerprint=$el_fingerprint" \
        "el_revision=$expected_revision" \
        "genesis_digest=$genesis_digest" >&3
    exec 3>&-
    chmod 0400 "$state_file"
    [ "$(stat -c '%a' "$state_file")" = 400 ] || {
        echo "failed to seal validator soak state mode" >&2; exit 1;
    }
    printf 'validator-soak=started state=%s start=%s end=%s required-seconds=%s validators=%s first-epoch=%s last-epoch=%s\n' \
        "$state_file" "$now" "$end_time" "$required_soak" "$index_count" "$start_epoch" "$end_epoch"
    ;;
status)
    if [ -z "$state_file" ]; then
        printf 'validator-soak=ready timestamp=%s validators=%s cl-synced=true cl-optimistic=false el-online=true identity-pins=unchecked\n' "$now" "$index_count"
        exit 0
    fi
    assert_state_file
    start_time="$(state_value start_time)"; end_time="$(state_value end_time)"
    decimal start_time "$start_time"; decimal end_time "$end_time"
    identity=match
    [ "$(state_value indices_digest)" = "$indices_digest" ] || identity=mismatch
    [ "$(state_value validator_fingerprint)" = "$validator_fingerprint" ] || identity=mismatch
    [ "$(state_value cl_fingerprint)" = "$cl_fingerprint" ] || identity=mismatch
    [ "$(state_value el_fingerprint)" = "$el_fingerprint" ] || identity=mismatch
    [ "$(state_value genesis_digest)" = "$genesis_digest" ] || identity=mismatch
    [ "$(state_value el_revision)" = "$expected_revision" ] || identity=mismatch
    elapsed="$(( now - start_time ))"
    if [ "$now" -ge "$end_time" ]; then phase=awaiting-complete; else phase=soaking; fi
    printf 'validator-soak=%s timestamp=%s start=%s end=%s elapsed-seconds=%s required-seconds=%s validators=%s identities=%s cl-synced=true cl-optimistic=false el-online=true\n' \
        "$phase" "$now" "$start_time" "$end_time" "$elapsed" "$required_soak" "$index_count" "$identity"
    [ "$identity" = match ] || exit 1
    ;;
complete)
    assert_state_file
    [ "$(state_value format)" = hoodi-validator-soak-v1 ] || { echo "unsupported validator soak state format" >&2; exit 1; }
    start_time="$(state_value start_time)"; end_time="$(state_value end_time)"
    stored_required="$(state_value required_seconds)"; first_epoch="$(state_value first_epoch)"
    last_epoch="$(state_value last_epoch)"; stored_count="$(state_value validator_count)"
    for pair in "start_time:$start_time" "end_time:$end_time" "required_seconds:$stored_required" \
        "first_epoch:$first_epoch" "last_epoch:$last_epoch" "validator_count:$stored_count"; do
        decimal "${pair%%:*}" "${pair#*:}"
    done
    [ "$stored_required" -eq "$required_soak" ] || { echo "state duration is not the reviewed fourteen-day duration" >&2; exit 1; }
    [ "$end_time" -eq "$(( start_time + required_soak ))" ] || { echo "state end timestamp is inconsistent" >&2; exit 1; }
    [ "$first_epoch" -eq "$(( (start_time - genesis_time) / 384 ))" ] || { echo "state first epoch is inconsistent" >&2; exit 1; }
    [ "$last_epoch" -eq "$(( (end_time - 1 - genesis_time) / 384 ))" ] || { echo "state last epoch is inconsistent" >&2; exit 1; }
    [ "$stored_count" -eq "$index_count" ] || { echo "validator count mismatch" >&2; exit 1; }
    stored="$(state_value indices_digest)"; hex64 indices_digest "$stored"
    [ "$stored" = "$indices_digest" ] || { echo "pinned identity mismatch: indices_digest" >&2; exit 1; }
    stored="$(state_value validator_fingerprint)"; hex64 validator_fingerprint "$stored"
    [ "$stored" = "$validator_fingerprint" ] || { echo "pinned identity mismatch: validator_fingerprint" >&2; exit 1; }
    stored="$(state_value cl_fingerprint)"; hex64 cl_fingerprint "$stored"
    [ "$stored" = "$cl_fingerprint" ] || { echo "pinned identity mismatch: cl_fingerprint" >&2; exit 1; }
    stored="$(state_value el_fingerprint)"; hex64 el_fingerprint "$stored"
    [ "$stored" = "$el_fingerprint" ] || { echo "pinned identity mismatch: el_fingerprint" >&2; exit 1; }
    stored="$(state_value genesis_digest)"; hex64 genesis_digest "$stored"
    [ "$stored" = "$genesis_digest" ] || { echo "pinned identity mismatch: genesis_digest" >&2; exit 1; }
    [ "$(state_value el_revision)" = "$expected_revision" ] || { echo "pinned EL revision mismatch" >&2; exit 1; }
    [ "$now" -ge "$end_time" ] || { echo "validator soak has not reached 1,209,600 real seconds" >&2; exit 1; }
    final_window_slot="$(( (end_time - 1 - genesis_time) / 12 ))"
    [ "$head_slot" -ge "$final_window_slot" ] || {
        echo "Beacon head has not reached the final slot intersecting the soak window" >&2; exit 1;
    }
    epoch_end_time="$(( genesis_time + (last_epoch + 1) * 384 ))"
    [ "$now" -ge "$epoch_end_time" ] || { echo "last epoch intersecting the soak window has not completed" >&2; exit 1; }

    epoch_count=0; selected_duties=0; verified_headers=0
    epoch="$first_epoch"
    while [ "$epoch" -le "$last_epoch" ]; do
        duties_json="$(beacon "/eth/v1/validator/duties/proposer/$epoch")"
        printf '%s' "$duties_json" | jq -e --argjson epoch "$epoch" '
          .execution_optimistic == false and
          (.dependent_root | type == "string" and test("^0x[0-9a-fA-F]{64}$")) and
          (.data | type == "array") and
          (all(.data[];
            (.slot | type == "string" and test("^[0-9]+$") and ((tonumber / 32 | floor) == $epoch)) and
            (.validator_index | type == "string" and test("^[0-9]+$")))) and
          (([.data[].slot] | length) == ([.data[].slot] | unique | length))' >/dev/null || {
            echo "malformed or inconsistent proposer duties response for epoch $epoch" >&2; exit 1;
        }
        while IFS=$'\t' read -r slot proposer; do
            [ -n "$slot" ] || continue
            case ",$indices," in
                *",$proposer,"*)
                    selected_duties="$(( selected_duties + 1 ))"
                    header_json="$(beacon "/eth/v1/beacon/headers/$slot")"
                    printf '%s' "$header_json" | jq -e --arg slot "$slot" --arg proposer "$proposer" '
                      .execution_optimistic == false and .data.canonical == true and
                      .data.header.message.slot == $slot and
                      .data.header.message.proposer_index == $proposer' >/dev/null || {
                        echo "canonical header/proposer verification failed at selected duty slot $slot" >&2; exit 1;
                    }
                    verified_headers="$(( verified_headers + 1 ))"
                    ;;
            esac
        done < <(printf '%s' "$duties_json" | jq -r '.data[] | [.slot, .validator_index] | @tsv')
        epoch_count="$(( epoch_count + 1 ))"
        epoch="$(( epoch + 1 ))"
    done
    [ "$selected_duties" -gt 0 ] || { echo "configured validators had zero proposer duties in intersecting epochs" >&2; exit 1; }
    [ "$selected_duties" -eq "$verified_headers" ] || { echo "not every selected duty has a verified canonical header" >&2; exit 1; }
    printf 'validator-soak=PASSED start=%s end=%s completed=%s elapsed-seconds=%s epochs=%s validators=%s proposer-duties=%s canonical-headers=%s missed-duties=0 rpc-errors=0\n' \
        "$start_time" "$end_time" "$now" "$(( now - start_time ))" "$epoch_count" "$stored_count" "$selected_duties" "$verified_headers"
    ;;
esac
REMOTE
