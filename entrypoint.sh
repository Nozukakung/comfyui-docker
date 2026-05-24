#!/usr/bin/env bash
set -Eeuo pipefail

# Compatibility wrapper for templates that still set "entrypoint.sh".
# Default to the Vast.ai boot path so portal/auth/supervisor startup is preserved.
if [[ "${1:-}" == "comfyui" ]]; then
  shift
  exec /opt/supervisor-scripts/comfyui-start.sh "$@"
fi

if [[ -x /opt/instance-tools/bin/entrypoint.sh ]]; then
  exec /opt/instance-tools/bin/entrypoint.sh "$@"
fi

echo "[entrypoint][warn] Vast.ai base entrypoint not found; starting ComfyUI directly" >&2
exec /opt/supervisor-scripts/comfyui-start.sh "$@"
