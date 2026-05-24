#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
SETUP_SENTINEL="${SETUP_SENTINEL:-$WORKSPACE_DIR/.comfy_wan_setup_done}"
COMFY_PORT="${COMFY_PORT:-8188}"
COMFY_LISTEN="${COMFY_LISTEN:-0.0.0.0}"

mkdir -p "$WORKSPACE_DIR"

if [[ ! -f "$SETUP_SENTINEL" ]]; then
  echo "[entrypoint] First run setup: install ComfyUI base"
  COMFY_DIR="$COMFY_DIR" \
  VENV_DIR="$VENV_DIR" \
  WORKSPACE_DIR="$WORKSPACE_DIR" \
  START_COMFY_AFTER_INSTALL=0 \
  /opt/setup/install_comfyui2.sh

  echo "[entrypoint] First run setup: install Wan2.2 Remix nodes/models"
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

echo "[entrypoint] Starting ComfyUI on ${COMFY_LISTEN}:${COMFY_PORT}"
exec "$VENV_DIR/bin/python" "$COMFY_DIR/main.py" --listen "$COMFY_LISTEN" --port "$COMFY_PORT"
