#!/usr/bin/env bash
set -Eeuo pipefail

utils=/opt/supervisor-scripts/utils
export PROC_NAME="${PROC_NAME:-comfyui}"
if [[ -f "$utils/logging.sh" ]]; then
  # Enables Vast.ai portal log capture when started by Supervisor.
  . "$utils/logging.sh"
fi
if [[ -f "$utils/environment.sh" ]]; then
  . "$utils/environment.sh"
fi

WORKSPACE_DIR="${WORKSPACE_DIR:-${WORKSPACE:-/workspace}}"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
SETUP_SENTINEL="${SETUP_SENTINEL:-$WORKSPACE_DIR/.comfy_wan_setup_done}"
RUN_SCRIPT_PATH="${RUN_SCRIPT_PATH:-$WORKSPACE_DIR/run_comfy.sh}"
COMFY_PORT="${COMFY_PORT:-${PORT:-8188}}"
COMFY_LISTEN="${COMFY_LISTEN:-0.0.0.0}"
COMFY_EXTRA_ARGS="${COMFY_EXTRA_ARGS:---reserve-vram 2}"

mkdir -p "$WORKSPACE_DIR"

if [[ ! -f "$SETUP_SENTINEL" ]]; then
  echo "[comfyui] First run setup: install ComfyUI base"
  COMFY_DIR="$COMFY_DIR" \
  VENV_DIR="$VENV_DIR" \
  WORKSPACE_DIR="$WORKSPACE_DIR" \
  START_COMFY_AFTER_INSTALL=0 \
  /opt/setup/install_comfyui2.sh

  echo "[comfyui] First run setup: install Wan2.2 Remix nodes/models"
  COMFY_DIR="$COMFY_DIR" \
  VENV_DIR="$VENV_DIR" \
  WORKSPACE_DIR="$WORKSPACE_DIR" \
  HF_TOKEN="${HF_TOKEN:-}" \
  CIVITAI_TOKEN="${CIVITAI_TOKEN:-}" \
  INSTALL_MODELS="${INSTALL_MODELS:-1}" \
  INSTALL_NODES="${INSTALL_NODES:-1}" \
  UPDATE_REPOS="${UPDATE_REPOS:-1}" \
  INSTALL_FLUX_KONTEXT_MODEL="${INSTALL_FLUX_KONTEXT_MODEL:-1}" \
  QWENVL_MODEL_NAME="${QWENVL_MODEL_NAME:-Qwen3-VL-8B-Instruct-c_abliterated-v3}" \
  /opt/setup/install_wan22_remix_comfy.sh

  touch "$SETUP_SENTINEL"
fi

if [[ -x "$RUN_SCRIPT_PATH" ]]; then
  echo "[comfyui] Starting with $RUN_SCRIPT_PATH"
  exec "$RUN_SCRIPT_PATH"
fi

echo "[comfyui][warn] Run script not found; starting ComfyUI directly on ${COMFY_LISTEN}:${COMFY_PORT}"
cd "$COMFY_DIR"
exec "$VENV_DIR/bin/python" main.py --listen "$COMFY_LISTEN" --port "$COMFY_PORT" --enable-manager $COMFY_EXTRA_ARGS
