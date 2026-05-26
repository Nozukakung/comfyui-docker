#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
MODEL_STORE_DIR="${MODEL_STORE_DIR:-/opt/comfy-models}"
QWENVL_MODEL_NAME="${QWENVL_MODEL_NAME:-Qwen3-VL-8B-Instruct-abliterated-v2}"
INSTALL_NODES="${INSTALL_NODES:-1}"
INSTALL_MODELS="${INSTALL_MODELS:-1}"
INSTALL_QWENVL="${INSTALL_QWENVL:-1}"
INSTALL_QWENVL_MODEL="${INSTALL_QWENVL_MODEL:-1}"
INSTALL_FLUX_KONTEXT_MODEL="${INSTALL_FLUX_KONTEXT_MODEL:-1}"
INSTALL_PROMPT_SUPPORT_MODELS="${INSTALL_PROMPT_SUPPORT_MODELS:-1}"
INSTALL_LLAMACPP="${INSTALL_LLAMACPP:-1}"

log() { echo "[wan22-verify] $*"; }
warn() { echo "[wan22-verify][warn] $*" >&2; }
fail() { echo "[wan22-verify][error] $*" >&2; exit 1; }

python_cmd() {
  if [ -x "$VENV_DIR/bin/python" ]; then
    echo "$VENV_DIR/bin/python"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "Python not found: python3"
  command -v python3
}

check_file() {
  local path="$1"
  local label="${2:-file}"
  [ -f "$path" ] || fail "Missing $label: $path"
}

check_dir() {
  local path="$1"
  local label="${2:-directory}"
  [ -d "$path" ] || fail "Missing $label: $path"
}

check_non_empty_dir() {
  local path="$1"
  local label="${2:-directory}"
  check_dir "$path" "$label"
  if ! find "$path" -mindepth 1 -maxdepth 1 -print -quit >/dev/null 2>&1; then
    fail "Empty $label: $path"
  fi
}

check_python_module() {
  local module="$1"
  local package="${2:-$1}"
  if ! "$(python_cmd)" - "$module" <<'PY'
import importlib.util
import sys

module = sys.argv[1]
raise SystemExit(0 if importlib.util.find_spec(module) else 1)
PY
  then
    fail "Missing Python module: $module (pip package: $package)"
  fi
}

check_qwenvl_custom_models() {
  local config_path="$COMFY_DIR/custom_nodes/ComfyUI-QwenVL/custom_models.json"
  if [ ! -f "$config_path" ]; then
    fail "Missing QwenVL custom model config: $config_path"
  fi

  "$(python_cmd)" - "$config_path" "$QWENVL_MODEL_NAME" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
model_name = sys.argv[2]
data = json.loads(config_path.read_text(encoding="utf-8"))
models = data.get("hf_models", {})
if model_name not in models:
    raise SystemExit(f"Missing QwenVL model entry: {model_name}")
entry = models[model_name]
repo_id = entry.get("repo_id", "")
if repo_id != "prithivMLmods/Qwen3-VL-8B-Instruct-abliterated-v2":
    raise SystemExit(f"Unexpected QwenVL repo_id: {repo_id}")
PY
}

check_sample_input_files() {
  check_file "$COMFY_DIR/input/example.png" "workflow sample image"
  check_file "$COMFY_DIR/input/ChatGPT Image 20 พ.ค. 2569 17_45_39.png" "workflow reference image"
}

main() {
  log "Checking base paths"
  check_dir "$COMFY_DIR" "ComfyUI directory"
  check_dir "$COMFY_DIR/custom_nodes" "custom_nodes directory"
  check_dir "$MODEL_STORE_DIR" "model store"
  check_dir "$VENV_DIR" "venv directory"

  if [ "$INSTALL_NODES" = "1" ]; then
    log "Checking installed custom nodes"
    check_dir "$COMFY_DIR/custom_nodes/rgthree-comfy" "rgthree-comfy"
    check_dir "$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite" "ComfyUI-VideoHelperSuite"
    check_dir "$COMFY_DIR/custom_nodes/ComfyUI_essentials" "ComfyUI_essentials"
    check_dir "$COMFY_DIR/custom_nodes/ComfyUI-KJNodes" "ComfyUI-KJNodes"
    check_dir "$COMFY_DIR/custom_nodes/ComfyUI-Custom-Scripts" "ComfyUI-Custom-Scripts"
    check_dir "$COMFY_DIR/custom_nodes/ComfyUI_LayerStyle" "ComfyUI_LayerStyle"
    check_dir "$COMFY_DIR/custom_nodes/comfyui-mixlab-nodes" "comfyui-mixlab-nodes"
    check_dir "$COMFY_DIR/custom_nodes/ComfyUI_RH_LLM_API" "ComfyUI_RH_LLM_API"
    check_dir "$COMFY_DIR/custom_nodes/Comfyui-PainterVRAM" "Comfyui-PainterVRAM"
    if [ "$INSTALL_QWENVL" = "1" ]; then
      check_dir "$COMFY_DIR/custom_nodes/ComfyUI-QwenVL" "ComfyUI-QwenVL"
      check_qwenvl_custom_models
      if [ "$INSTALL_LLAMACPP" = "1" ]; then
        check_python_module "llama_cpp" "llama-cpp-python"
      fi
    fi
    check_sample_input_files
  fi

  if [ "$INSTALL_MODELS" = "1" ]; then
    log "Checking core workflow models"
    check_file "$MODEL_STORE_DIR/diffusion_models/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_fp8_e4m3fn_v3.0.safetensors" "Wan high-lighting diffusion model"
    check_file "$MODEL_STORE_DIR/diffusion_models/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_fp8_e4m3fn_v3.0.safetensors" "Wan low-lighting diffusion model"
    check_file "$MODEL_STORE_DIR/text_encoders/nsfw_wan_umt5-xxl_fp8_scaled.safetensors" "Wan text encoder"
    check_file "$MODEL_STORE_DIR/vae/wan_2.1_vae.safetensors" "Wan VAE"

    if [ "$INSTALL_FLUX_KONTEXT_MODEL" = "1" ]; then
      check_file "$MODEL_STORE_DIR/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors" "Flux Kontext diffusion model"
      check_file "$MODEL_STORE_DIR/vae/ae.safetensors" "Flux VAE"
      check_file "$MODEL_STORE_DIR/text_encoders/clip_l.safetensors" "Flux CLIP-L"
      check_file "$MODEL_STORE_DIR/text_encoders/t5xxl_fp8_e4m3fn_scaled.safetensors" "Flux T5-XXL"
    fi

    if [ "$INSTALL_QWENVL_MODEL" = "1" ]; then
      check_non_empty_dir "$MODEL_STORE_DIR/LLM/Qwen-VL/$QWENVL_MODEL_NAME" "QwenVL model snapshot"
    fi

    if [ "$INSTALL_PROMPT_SUPPORT_MODELS" = "1" ]; then
      log "Checking prompt-support models"
      check_non_empty_dir "$MODEL_STORE_DIR/clip_interrogator/Salesforce/blip-image-captioning-base" "clip_interrogator model"
      check_non_empty_dir "$MODEL_STORE_DIR/prompt_generator/text2image-prompt-generator" "text prompt generator model"
      check_non_empty_dir "$MODEL_STORE_DIR/prompt_generator/opus-mt-zh-en" "ZH->EN prompt generator model"
    fi
  fi

  log "Verification completed successfully"
}

main "$@"
