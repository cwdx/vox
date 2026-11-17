#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec "$here/.venv/bin/python" "$here/helper.py" "$@"
