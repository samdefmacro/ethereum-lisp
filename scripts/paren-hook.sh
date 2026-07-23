#!/bin/bash
# Claude Code PostToolUse hook: delimiter-balance check on edited Lisp files.
# stdin: hook JSON. Exit 2 + stderr => fed back to the agent for a same-turn fix.
# The checker is a pure lexical scan (scripts/check-parens.lisp): no READ, so it
# is safe against #. and does not depend on packages existing. ~30ms per file.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
payload=$(cat)
f=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -z "$f" ] && exit 0
case "$f" in
  *.lisp|*.asd) ;;
  *) exit 0 ;;
esac
[ -f "$f" ] || exit 0
if ! err=$(sbcl --script "$DIR/check-parens.lisp" "$f" 2>&1); then
  echo "$err" >&2
  exit 2
fi
exit 0
