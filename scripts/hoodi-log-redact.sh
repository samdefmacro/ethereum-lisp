# shellcheck shell=bash
#
# The one log redaction filter of the Hoodi gate brokers
# (scripts/hoodi-live-gate.sh, scripts/hoodi-geth-benchmark-gate.sh,
# scripts/hoodi-hive-gate.sh).  This file only defines a function.  The
# brokers send it ahead of the remote scripts they run over ssh, so a failure
# path that echoes container log lines to the operator's terminal pipes them
# through it on the remote host.  The full unredacted log never crosses the
# broker: it stays on the remote host, in Docker's container log or the run's
# evidence root, where the read-only actions read it.
#
# hoodi_redact_peer_identities: copy stdin to stdout with peer identities
# masked, one line at a time, and every other byte unchanged:
#   - an enode:// URL keeps its scheme and id, and its host, port and query
#     become <addr>;
#   - a run of 64 or more hex digits (a node id, a public key, an enode id,
#     with or without 0x) keeps its first 8 and last 4 digits around an
#     ellipsis;
#   - an enr: record becomes enr:<redacted> (it encodes an address and a key);
#   - an IPv4 address, and a Lisp address vector #(a b c d), becomes <ip>,
#     except loopback 127.0.0.0/8 and the unspecified 0.0.0.0/8;
#   - an IPv6 address becomes <ip>, except loopback ::1 and the unspecified ::.
# A word that only resembles an address (a version such as v1.2.3.4, a
# time of day, a Lisp PACKAGE::SYMBOL) is left alone: an address must stand
# between non-alphanumeric characters.  The C locale makes the classes
# byte-wise, so the same expressions behave alike under GNU and BSD sed and
# no input byte sequence is refused.
hoodi_redact_peer_identities() {
    LC_ALL=C sed -E \
        -e 's#(enode://[^@[:space:]"<>]*)@[^[:space:]"<>,;)}]*#\1@<addr>#g' \
        -e 's/(^|[^0-9A-Za-z])enr:[A-Za-z0-9_=-]{8,}/\1enr:<redacted>/g' \
        -e 's/(0x)?([0-9A-Fa-f]{8})[0-9A-Fa-f]{52,}([0-9A-Fa-f]{4})/\1\2…\3/g' \
        -e 's/(^|[^0-9A-Za-z.])([1-9]|[1-9][0-9]|1[013-9][0-9]|12[0-689]|2[0-9][0-9])([.][0-9]{1,3}){3}/\1<ip>/g' \
        -e 's/#\(([1-9]|[1-9][0-9]|1[013-9][0-9]|12[0-689]|2[0-9][0-9])( [0-9]{1,3}){3}\)/#(<ip>)/g' \
        -e ':v6' \
        -e 's/(^|[^0-9A-Za-z:.])([0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){7}|[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){0,6}::[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){0,5}|::[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){1,6}|::([02-9A-Fa-f]|[0-9A-Fa-f]{2,4}))([^0-9A-Za-z:.]|$)/\1<ip>\8/' \
        -e 't v6'
}
