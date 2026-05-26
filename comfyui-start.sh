#!/usr/bin/env bash
set -Eeuo pipefail

export PROC_NAME="${PROC_NAME:-comfyui}"

WORKSPACE_DIR="${WORKSPACE_DIR:-${WORKSPACE:-/workspace}}"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
BASE_SETUP_SENTINEL="${BASE_SETUP_SENTINEL:-$WORKSPACE_DIR/.comfy_base_setup_done}"
WAN_NODES_SENTINEL="${WAN_NODES_SENTINEL:-$WORKSPACE_DIR/.comfy_wan_nodes_setup_done}"
MODEL_STORE_DIR="${MODEL_STORE_DIR:-/opt/comfy-models}"
MODELS_SENTINEL="${MODELS_SENTINEL:-$MODEL_STORE_DIR/.comfy_wan_models_setup_done}"
RUN_SCRIPT_PATH="${RUN_SCRIPT_PATH:-$WORKSPACE_DIR/run_comfy.sh}"
COMFY_PORT="${COMFY_PORT:-${PORT:-8188}}"
COMFY_LISTEN="${COMFY_LISTEN:-0.0.0.0}"
COMFY_EXTRA_ARGS="${COMFY_EXTRA_ARGS:---reserve-vram 2}"
WAN_SETUP_SCRIPT="/opt/setup/install_wan22_remix_comfy.sh"
WAN_VERIFY_SCRIPT="/opt/setup/verify_wan22_remix_ready.sh"
WAN_ASSET_DIR="/opt/setup/assets"
MODEL_INSTALL_LOCK_FILE="${MODEL_INSTALL_LOCK_FILE:-$WORKSPACE_DIR/.comfy_model_install.lock}"

mkdir -p "$WORKSPACE_DIR"

link_preloaded_models() {
  if [[ ! -d "$MODEL_STORE_DIR" ]]; then
    return 0
  fi

  mkdir -p "$COMFY_DIR"

  if [[ -L "$COMFY_DIR/models" ]]; then
    if [[ "$(readlink "$COMFY_DIR/models")" != "$MODEL_STORE_DIR" ]]; then
      ln -sfn "$MODEL_STORE_DIR" "$COMFY_DIR/models"
    fi
    return 0
  fi

  if [[ -e "$COMFY_DIR/models" ]]; then
    if find "$COMFY_DIR/models" \( -type f -o -type l \) -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
    rm -rf "$COMFY_DIR/models"
  fi

  ln -s "$MODEL_STORE_DIR" "$COMFY_DIR/models"
}

ensure_sample_input_files() {
  local asset

  [[ -d "$WAN_ASSET_DIR" ]] || return 0
  mkdir -p "$COMFY_DIR/input"

  for asset in "$WAN_ASSET_DIR"/*; do
    [[ -f "$asset" ]] || continue
    cp -f "$asset" "$COMFY_DIR/input/$(basename "$asset")"
  done
}

repair_or_skip_models() {
  if [[ "${INSTALL_MODELS:-1}" != "1" ]]; then
    echo "[comfyui] Skipping model download because INSTALL_MODELS=${INSTALL_MODELS:-1}"
    return 0
  fi

  (
    exec 9>"$MODEL_INSTALL_LOCK_FILE"
    flock 9

    if [[ -f "$MODELS_SENTINEL" ]]; then
      if COMFY_DIR="$COMFY_DIR" \
        VENV_DIR="$VENV_DIR" \
        WORKSPACE_DIR="$WORKSPACE_DIR" \
        MODEL_STORE_DIR="$MODEL_STORE_DIR" \
        INSTALL_NODES=0 \
        INSTALL_MODELS=1 \
        INSTALL_QWENVL="${INSTALL_QWENVL:-1}" \
        INSTALL_QWENVL_MODEL="${INSTALL_QWENVL_MODEL:-1}" \
        INSTALL_FLUX_KONTEXT_MODEL="${INSTALL_FLUX_KONTEXT_MODEL:-1}" \
        INSTALL_PROMPT_SUPPORT_MODELS="${INSTALL_PROMPT_SUPPORT_MODELS:-1}" \
        INSTALL_LLAMACPP="${INSTALL_LLAMACPP:-1}" \
        "$WAN_VERIFY_SCRIPT" >/dev/null 2>&1; then
        echo "[comfyui] Models already preloaded at $MODEL_STORE_DIR"
        return 0
      fi

      echo "[comfyui] Model store is incomplete; repairing missing files"
    else
      echo "[comfyui] First run setup: download Wan2.2 Remix models"
    fi

    COMFY_DIR="$COMFY_DIR" \
    VENV_DIR="$VENV_DIR" \
    WORKSPACE_DIR="$WORKSPACE_DIR" \
    MODEL_STORE_DIR="$MODEL_STORE_DIR" \
    HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_HUB_TOKEN:-}}" \
    CIVITAI_TOKEN="${CIVITAI_TOKEN:-}" \
    INSTALL_MODELS=1 \
    INSTALL_NODES=0 \
    INSTALL_NODE_REQUIREMENTS=0 \
    UPDATE_REPOS="${UPDATE_REPOS:-1}" \
    INSTALL_QWENVL="${INSTALL_QWENVL:-1}" \
    INSTALL_QWENVL_MODEL="${INSTALL_QWENVL_MODEL:-1}" \
    INSTALL_FLUX_KONTEXT_MODEL="${INSTALL_FLUX_KONTEXT_MODEL:-1}" \
    INSTALL_PROMPT_SUPPORT_MODELS="${INSTALL_PROMPT_SUPPORT_MODELS:-1}" \
    INSTALL_LLAMACPP="${INSTALL_LLAMACPP:-1}" \
    QWENVL_MODEL_NAME="${QWENVL_MODEL_NAME:-Qwen3-VL-8B-Instruct-c_abliterated-v3}" \
    "$WAN_SETUP_SCRIPT"

    touch "$MODELS_SENTINEL"
  )
}

if [[ ! -f "$BASE_SETUP_SENTINEL" ]]; then
  if [[ -f "$COMFY_DIR/main.py" && -x "$VENV_DIR/bin/python" && -x "$RUN_SCRIPT_PATH" ]]; then
    echo "[comfyui] ComfyUI base already exists; marking base setup complete"
  else
    echo "[comfyui] First run setup: install ComfyUI base"
    COMFY_DIR="$COMFY_DIR" \
    VENV_DIR="$VENV_DIR" \
    WORKSPACE_DIR="$WORKSPACE_DIR" \
    START_COMFY_AFTER_INSTALL=0 \
    /opt/setup/install_comfyui2.sh
  fi
  touch "$BASE_SETUP_SENTINEL"
fi

if [[ ! -f "$WAN_NODES_SENTINEL" ]]; then
  echo "[comfyui] First run setup: install Wan2.2 Remix nodes/dependencies"
  COMFY_DIR="$COMFY_DIR" \
  VENV_DIR="$VENV_DIR" \
  WORKSPACE_DIR="$WORKSPACE_DIR" \
  HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_HUB_TOKEN:-}}" \
  CIVITAI_TOKEN="${CIVITAI_TOKEN:-}" \
  INSTALL_MODELS=0 \
  INSTALL_NODES="${INSTALL_NODES:-1}" \
  UPDATE_REPOS="${UPDATE_REPOS:-1}" \
  INSTALL_FLUX_KONTEXT_MODEL="${INSTALL_FLUX_KONTEXT_MODEL:-1}" \
  QWENVL_MODEL_NAME="${QWENVL_MODEL_NAME:-Qwen3-VL-8B-Instruct-c_abliterated-v3}" \
  /opt/setup/install_wan22_remix_comfy.sh

  touch "$WAN_NODES_SENTINEL"
fi

repair_or_skip_models
ensure_sample_input_files

link_preloaded_models

if [[ "${CUDA_RUNTIME_CHECK:-1}" = "1" ]]; then
  echo "[comfyui] Checking CUDA runtime stack"
  /opt/setup/cuda-runtime-check.sh
else
  echo "[comfyui] Skipping CUDA runtime stack check because CUDA_RUNTIME_CHECK=${CUDA_RUNTIME_CHECK:-1}"
fi

if [[ -x "$RUN_SCRIPT_PATH" ]]; then
  echo "[comfyui] Starting with $RUN_SCRIPT_PATH"
  exec "$RUN_SCRIPT_PATH"
fi

echo "[comfyui][warn] Run script not found; starting ComfyUI directly on ${COMFY_LISTEN}:${COMFY_PORT}"
cd "$COMFY_DIR"
exec "$VENV_DIR/bin/python" main.py --listen "$COMFY_LISTEN" --port "$COMFY_PORT" --enable-manager $COMFY_EXTRA_ARGS
