#!/bin/bash
# Starts the helper. Jev end-of-turn judging is optional: it needs a TypeSafe key from $TYPESAFE_API_KEY,
# or from the command in vox.json's "keyCommand" (a secret manager call); without one, auto-send follows punctuation.
cd "$(dirname "$0")" || exit
if [ -z "$TYPESAFE_API_KEY" ]; then
  cmd=$(jq -r '.keyCommand // empty' ~/.claude/vox.json 2>/dev/null)
  [ -n "$cmd" ] && TYPESAFE_API_KEY=$(bash -c "$cmd" 2>/dev/null | tr -d '[:space:]')
fi
export TYPESAFE_API_KEY
exec "$PWD/vox-helper" "$1"
