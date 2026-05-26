#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
MODEL_STORE_DIR="${MODEL_STORE_DIR:-$COMFY_DIR/models}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
INSTALL_NODES="${INSTALL_NODES:-1}"
INSTALL_NODE_REQUIREMENTS="${INSTALL_NODE_REQUIREMENTS:-1}"
INSTALL_MODELS="${INSTALL_MODELS:-1}"
INSTALL_QWENVL="${INSTALL_QWENVL:-1}"
INSTALL_QWENVL_MODEL="${INSTALL_QWENVL_MODEL:-1}"
INSTALL_FLUX_KONTEXT_MODEL="${INSTALL_FLUX_KONTEXT_MODEL:-1}"
INSTALL_PROMPT_SUPPORT_MODELS="${INSTALL_PROMPT_SUPPORT_MODELS:-1}"
INSTALL_LLAMACPP="${INSTALL_LLAMACPP:-1}"
QWENVL_MODEL_NAME="${QWENVL_MODEL_NAME:-Qwen3-VL-8B-Instruct-c_abliterated-v3}"
QWENVL_REPO_ID="${QWENVL_REPO_ID:-prithivMLmods/Qwen3-VL-8B-Instruct-c_abliterated-v3}"
UPDATE_REPOS="${UPDATE_REPOS:-1}"
GIT_CLONE_DEPTH="${GIT_CLONE_DEPTH:-1}"
GIT_BLOB_FILTER="${GIT_BLOB_FILTER:-1}"
LOCK_TORCH_PACKAGES="${LOCK_TORCH_PACKAGES:-1}"
PATCH_VIDEOHELPERSUITE="${PATCH_VIDEOHELPERSUITE:-1}"
DISABLE_DUPLICATE_CUSTOM_NODES="${DISABLE_DUPLICATE_CUSTOM_NODES:-1}"
HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_HUB_TOKEN:-}}"
CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_CACHE_DIR="${PIP_NO_CACHE_DIR:-1}"
export GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}"
export GIT_ASKPASS="${GIT_ASKPASS:-/bin/false}"
export HF_HOME="${HF_HOME:-$WORKSPACE_DIR/.cache/huggingface}"

log() { echo "[wan22-remix] $*"; }
warn() { echo "[wan22-remix][warn] $*" >&2; }
fail() { echo "[wan22-remix][error] $*" >&2; exit 1; }

on_error() {
  local exit_code=$?
  local line_no=${1:-unknown}
  echo "[wan22-remix][error] Failed at line $line_no with exit code $exit_code" >&2
  exit "$exit_code"
}
trap 'on_error "$LINENO"' ERR

python_cmd() {
  if [ -x "$VENV_DIR/bin/python" ]; then
    echo "$VENV_DIR/bin/python"
  else
    command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python not found: $PYTHON_BIN"
    command -v "$PYTHON_BIN"
  fi
}

pip_install() {
  "$(python_cmd)" -m pip install "$@"
}

hf_cmd() {
  if [ -x "$VENV_DIR/bin/hf" ]; then
    echo "$VENV_DIR/bin/hf"
  elif command -v hf >/dev/null 2>&1; then
    command -v hf
  else
    return 1
  fi
}

require_base_paths() {
  [ -d "$COMFY_DIR" ] || fail "ComfyUI directory not found: $COMFY_DIR"
  mkdir -p \
    "$COMFY_DIR/input" \
    "$COMFY_DIR/custom_nodes" \
    "$MODEL_STORE_DIR/diffusion_models" \
    "$MODEL_STORE_DIR/text_encoders" \
    "$MODEL_STORE_DIR/LLM/Qwen-VL" \
    "$MODEL_STORE_DIR/loras" \
    "$MODEL_STORE_DIR/vae" \
    "$HF_HOME"
  command -v git >/dev/null 2>&1 || fail "git not found"
}

install_sample_input_files() {
  local asset_dir="$SCRIPT_DIR/assets"
  local target_dir="$COMFY_DIR/input"
  local asset

  [ -d "$asset_dir" ] || return 0
  mkdir -p "$target_dir"

  for asset in "$asset_dir"/*; do
    [ -f "$asset" ] || continue
    cp -f "$asset" "$target_dir/$(basename "$asset")"
  done
}

clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local label="$3"

  if [ -d "$target_dir/.git" ]; then
    if [ "$UPDATE_REPOS" = "1" ]; then
      log "Updating $label"
      git -C "$target_dir" pull --ff-only
    else
      log "Using existing $label"
    fi
    return 0
  fi

  if [ -e "$target_dir" ] && [ ! -d "$target_dir/.git" ]; then
    fail "$label path exists but is not a git checkout: $target_dir"
  fi

  log "Cloning $label"
  local clone_args=()
  if [ "$GIT_CLONE_DEPTH" != "0" ]; then
    clone_args+=(--depth "$GIT_CLONE_DEPTH")
  fi
  if [ "$GIT_BLOB_FILTER" = "1" ]; then
    clone_args+=(--filter=blob:none)
  fi

  if [ "${#clone_args[@]}" -gt 0 ]; then
    git clone "${clone_args[@]}" "$repo_url" "$target_dir"
  else
    git clone "$repo_url" "$target_dir"
  fi
}

write_torch_constraints() {
  local output_file="$1"

  "$(python_cmd)" - "$output_file" <<'PY'
import importlib
import sys
from pathlib import Path

packages = ("torch", "torchvision", "torchaudio", "triton")
lines = []
for name in packages:
    try:
        module = importlib.import_module(name)
    except Exception:
        continue
    version = getattr(module, "__version__", "")
    if version:
        lines.append(f"{name}=={version}")

Path(sys.argv[1]).write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
PY
}

filter_requirements() {
  local input_file="$1"
  local output_file="$2"

  "$(python_cmd)" - "$input_file" "$output_file" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
blocked = re.compile(
    r"^\s*(?:-e\s+)?(?:torch|torchvision|torchaudio|xformers|triton|nvidia-[A-Za-z0-9_.-]+)\b",
    re.I,
)

out = []
for line in src.read_text(encoding="utf-8").splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        out.append(line)
        continue
    if blocked.match(stripped):
        continue
    out.append(line)

dst.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

install_requirements_without_gpu_packages() {
  local requirements_file="$1"
  local label="$2"
  local filtered_file constraints_file

  if [ ! -f "$requirements_file" ]; then
    log "Skipping $label requirements; file not found"
    return 0
  fi

  filtered_file="$(mktemp)"
  filter_requirements "$requirements_file" "$filtered_file"
  log "Installing $label requirements without torch/xformers/triton/NVIDIA packages"
  if [ "$LOCK_TORCH_PACKAGES" = "1" ]; then
    constraints_file="$(mktemp)"
    write_torch_constraints "$constraints_file"
    pip_install -c "$constraints_file" -r "$filtered_file"
    rm -f "$constraints_file"
  else
    pip_install -r "$filtered_file"
  fi
  rm -f "$filtered_file"
}

install_custom_nodes() {
  if [ "$INSTALL_NODES" != "1" ]; then
    log "Skipping custom nodes because INSTALL_NODES=$INSTALL_NODES"
    return 0
  fi

  local nodes=(
    "https://github.com/rgthree/rgthree-comfy.git|$COMFY_DIR/custom_nodes/rgthree-comfy|rgthree-comfy"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git|$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite|ComfyUI-VideoHelperSuite"
    "https://github.com/cubiq/ComfyUI_essentials.git|$COMFY_DIR/custom_nodes/ComfyUI_essentials|ComfyUI_essentials"
    "https://github.com/kijai/ComfyUI-KJNodes.git|$COMFY_DIR/custom_nodes/ComfyUI-KJNodes|ComfyUI-KJNodes"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git|$COMFY_DIR/custom_nodes/ComfyUI-Custom-Scripts|ComfyUI-Custom-Scripts"
    "https://github.com/chflame163/ComfyUI_LayerStyle.git|$COMFY_DIR/custom_nodes/ComfyUI_LayerStyle|ComfyUI_LayerStyle"
    "https://github.com/MixLabPro/comfyui-mixlab-nodes.git|$COMFY_DIR/custom_nodes/comfyui-mixlab-nodes|comfyui-mixlab-nodes"
    "https://github.com/HM-RunningHub/ComfyUI_RH_LLM_API.git|$COMFY_DIR/custom_nodes/ComfyUI_RH_LLM_API|ComfyUI_RH_LLM_API"
    "https://github.com/princepainter/Comfyui-PainterVRAM.git|$COMFY_DIR/custom_nodes/Comfyui-PainterVRAM|Comfyui-PainterVRAM"
  )

  if [ "$INSTALL_QWENVL" = "1" ]; then
    nodes+=("https://github.com/1038lab/ComfyUI-QwenVL.git|$COMFY_DIR/custom_nodes/ComfyUI-QwenVL|ComfyUI-QwenVL")
  fi

  local entry repo_url target_dir label
  for entry in "${nodes[@]}"; do
    IFS='|' read -r repo_url target_dir label <<< "$entry"
    clone_or_update_repo "$repo_url" "$target_dir" "$label"
  done

  local story_tools_src="$SCRIPT_DIR/custom_nodes/ComfyUI-WanStoryShotTools"
  local story_tools_dst="$COMFY_DIR/custom_nodes/ComfyUI-WanStoryShotTools"
  if [ -d "$story_tools_src" ]; then
    log "Installing local custom node: ComfyUI-WanStoryShotTools"
    rm -rf "$story_tools_dst"
    mkdir -p "$story_tools_dst"
    cp -a "$story_tools_src/." "$story_tools_dst/"
  else
    warn "Local Story Shot tools not found at $story_tools_src"
  fi

  if [ "$INSTALL_NODE_REQUIREMENTS" != "1" ]; then
    log "Skipping node requirements because INSTALL_NODE_REQUIREMENTS=$INSTALL_NODE_REQUIREMENTS"
    return 0
  fi

  pip_install --upgrade pip "setuptools<82" wheel
  for entry in "${nodes[@]}"; do
    IFS='|' read -r repo_url target_dir label <<< "$entry"
    install_requirements_without_gpu_packages "$target_dir/requirements.txt" "$label"
  done

  if [ "$INSTALL_QWENVL" = "1" ] && [ "$INSTALL_LLAMACPP" = "1" ]; then
    ensure_python_module "llama_cpp" "llama-cpp-python"
  fi
}

write_qwenvl_custom_models() {
  if [ "$INSTALL_QWENVL" != "1" ]; then
    return 0
  fi

  local config_path="$COMFY_DIR/custom_nodes/ComfyUI-QwenVL/custom_models.json"
  [ -d "$(dirname "$config_path")" ] || return 0

  "$(python_cmd)" - "$config_path" "$QWENVL_MODEL_NAME" "$QWENVL_REPO_ID" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
model_name = sys.argv[2]
repo_id = sys.argv[3]

if path.exists():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = {}
else:
    data = {}

hf_models = data.setdefault("hf_models", {})
hf_models[model_name] = {
    "repo_id": repo_id,
    "default": False,
    "quantized": False,
}
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  log "Registered QwenVL custom model: $QWENVL_MODEL_NAME -> $QWENVL_REPO_ID"
}

disable_duplicate_custom_nodes() {
  local disabled_root="$COMFY_DIR/custom_nodes_disabled"
  local keep duplicate disabled
  local duplicate_sets=(
    "$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite|$COMFY_DIR/custom_nodes/comfyui-videohelpersuite"
    "$COMFY_DIR/custom_nodes/ComfyUI_essentials|$COMFY_DIR/custom_nodes/comfyui_essentials"
  )
  local pair duplicates

  if [ "$DISABLE_DUPLICATE_CUSTOM_NODES" != "1" ]; then
    return 0
  fi

  mkdir -p "$disabled_root"

  for pair in "${duplicate_sets[@]}"; do
    IFS='|' read -r keep duplicate <<< "$pair"
    shopt -s nullglob
    duplicates=("$duplicate" "$duplicate".disabled*)
    shopt -u nullglob

    for duplicate in "${duplicates[@]}"; do
      if [ -d "$keep" ] && [ -d "$duplicate" ]; then
        disabled="$disabled_root/$(basename "$duplicate").$(date +%Y%m%d-%H%M%S)"
        warn "Moving duplicate custom node out of scan path: $duplicate -> $disabled"
        mv "$duplicate" "$disabled"
      fi
    done
  done
}

patch_videohelpersuite_frontend() {
  local script_path
  local candidates=(
    "$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite/web/js/VHS.core.js"
    "$COMFY_DIR/custom_nodes/comfyui-videohelpersuite/web/js/VHS.core.js"
  )

  if [ "$PATCH_VIDEOHELPERSUITE" != "1" ]; then
    return 0
  fi

  for script_path in "${candidates[@]}"; do
    [ -f "$script_path" ] || continue
    if grep -q 'helpDOM.addHelp(this, nodeType, description)' "$script_path"; then
      log "Patching VideoHelperSuite frontend compatibility: $script_path"
      cp "$script_path" "${script_path}.bak-wan22-remix-$(date +%Y%m%d-%H%M%S)"
      perl -0pi -e 's/helpDOM\.addHelp\(this, nodeType, description\)/if (typeof helpDOM?.addHelp === "function") { helpDOM.addHelp(this, nodeType, description) }/' "$script_path"
    fi
  done
}

ensure_hf_cli() {
  if hf_cmd >/dev/null 2>&1; then
    return 0
  fi

  log "Installing huggingface_hub CLI"
  pip_install --upgrade huggingface_hub
  hf_cmd >/dev/null 2>&1 || fail "hf CLI not found after installing huggingface_hub"
}

ensure_python_module() {
  local module="$1"
  local package="${2:-$1}"

  if "$(python_cmd)" - "$module" <<'PY'
import importlib.util
import sys

module = sys.argv[1]
raise SystemExit(0 if importlib.util.find_spec(module) else 1)
PY
  then
    return 0
  fi

  log "Installing Python dependency for module $module: $package"
  pip_install "$package"
}

hf_download_to_file() {
  local repo_id="$1"
  local repo_file="$2"
  local target_dir="$3"
  local target_name="$4"
  local tmp_dir
  local token_args=()

  mkdir -p "$target_dir"
  if [ -f "$target_dir/$target_name" ]; then
    log "Model exists, skipping: $target_dir/$target_name"
    return 0
  fi

  tmp_dir="$(mktemp -d)"
  if [ -n "$HF_TOKEN" ]; then
    token_args=(--token "$HF_TOKEN")
  fi

  log "Downloading HF model: $repo_id / $repo_file -> $target_dir/$target_name"
  "$(hf_cmd)" download "$repo_id" "$repo_file" --local-dir "$tmp_dir" "${token_args[@]}"

  local downloaded="$tmp_dir/$repo_file"
  [ -f "$downloaded" ] || fail "Downloaded file not found: $downloaded"
  mv "$downloaded" "$target_dir/$target_name"
  rm -rf "$tmp_dir"
}

hf_snapshot_to_dir() {
  local repo_id="$1"
  local target_dir="$2"
  local token_args=()

  if [ -d "$target_dir" ] && { compgen -G "$target_dir/*.safetensors" >/dev/null || compgen -G "$target_dir/*.bin" >/dev/null; }; then
    log "HF snapshot exists, skipping: $target_dir"
    return 0
  fi

  mkdir -p "$target_dir"
  if [ -n "$HF_TOKEN" ]; then
    token_args=(--token "$HF_TOKEN")
  fi

  log "Downloading HF snapshot: $repo_id -> $target_dir"
  "$(hf_cmd)" download "$repo_id" \
    --local-dir "$target_dir" \
    --exclude="*.md" \
    --exclude=".git*" \
    "${token_args[@]}"
}

civitai_download_to_file() {
  local url="$1"
  local target_dir="$2"
  local target_name="$3"
  local token_header=()

  mkdir -p "$target_dir"
  if [ -f "$target_dir/$target_name" ]; then
    log "Civitai file exists, skipping: $target_dir/$target_name"
    return 0
  fi

  [ -n "$CIVITAI_TOKEN" ] || fail "CIVITAI_TOKEN is required for Civitai download: $target_name"
  token_header=(-H "Authorization: Bearer $CIVITAI_TOKEN")

  log "Downloading Civitai file -> $target_dir/$target_name"
  curl -L --fail --retry 5 --retry-delay 3 "${token_header[@]}" "$url" -o "$target_dir/$target_name"
}

install_models() {
  if [ "$INSTALL_MODELS" != "1" ]; then
    log "Skipping models because INSTALL_MODELS=$INSTALL_MODELS"
    return 0
  fi

  ensure_hf_cli

  hf_download_to_file \
    "FX-FeiHou/wan2.2-Remix" \
    "NSFW/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_fp8_e4m3fn_v3.0.safetensors" \
    "$MODEL_STORE_DIR/diffusion_models" \
    "Wan2.2_Remix_NSFW_i2v_14b_high_lighting_fp8_e4m3fn_v3.0.safetensors"

  hf_download_to_file \
    "FX-FeiHou/wan2.2-Remix" \
    "NSFW/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_fp8_e4m3fn_v3.0.safetensors" \
    "$MODEL_STORE_DIR/diffusion_models" \
    "Wan2.2_Remix_NSFW_i2v_14b_low_lighting_fp8_e4m3fn_v3.0.safetensors"

  hf_download_to_file \
    "NSFW-API/NSFW-Wan-UMT5-XXL" \
    "nsfw_wan_umt5-xxl_fp8_scaled.safetensors" \
    "$MODEL_STORE_DIR/text_encoders" \
    "nsfw_wan_umt5-xxl_fp8_scaled.safetensors"

  hf_download_to_file \
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" \
    "split_files/vae/wan_2.1_vae.safetensors" \
    "$MODEL_STORE_DIR/vae" \
    "wan_2.1_vae.safetensors"

  if [ "$INSTALL_FLUX_KONTEXT_MODEL" = "1" ]; then
    hf_download_to_file \
      "Comfy-Org/flux1-kontext-dev_ComfyUI" \
      "split_files/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors" \
      "$MODEL_STORE_DIR/diffusion_models" \
      "flux1-dev-kontext_fp8_scaled.safetensors"

    hf_download_to_file \
      "Comfy-Org/Lumina_Image_2.0_Repackaged" \
      "split_files/vae/ae.safetensors" \
      "$MODEL_STORE_DIR/vae" \
      "ae.safetensors"

    hf_download_to_file \
      "comfyanonymous/flux_text_encoders" \
      "clip_l.safetensors" \
      "$MODEL_STORE_DIR/text_encoders" \
      "clip_l.safetensors"

    hf_download_to_file \
      "comfyanonymous/flux_text_encoders" \
      "t5xxl_fp8_e4m3fn_scaled.safetensors" \
      "$MODEL_STORE_DIR/text_encoders" \
      "t5xxl_fp8_e4m3fn_scaled.safetensors"
  else
    log "Skipping Flux Kontext models because INSTALL_FLUX_KONTEXT_MODEL=$INSTALL_FLUX_KONTEXT_MODEL"
  fi

  if [ "$INSTALL_QWENVL_MODEL" = "1" ]; then
    hf_snapshot_to_dir \
      "$QWENVL_REPO_ID" \
      "$MODEL_STORE_DIR/LLM/Qwen-VL/$QWENVL_MODEL_NAME"
  else
    log "Skipping QwenVL model because INSTALL_QWENVL_MODEL=$INSTALL_QWENVL_MODEL"
  fi

  if [ "$INSTALL_PROMPT_SUPPORT_MODELS" = "1" ]; then
    hf_snapshot_to_dir \
      "Salesforce/blip-image-captioning-base" \
      "$MODEL_STORE_DIR/clip_interrogator/Salesforce/blip-image-captioning-base"

    hf_snapshot_to_dir \
      "succinctly/text2image-prompt-generator" \
      "$MODEL_STORE_DIR/prompt_generator/text2image-prompt-generator"

    hf_snapshot_to_dir \
      "Helsinki-NLP/opus-mt-zh-en" \
      "$MODEL_STORE_DIR/prompt_generator/opus-mt-zh-en"
  else
    log "Skipping prompt-support models because INSTALL_PROMPT_SUPPORT_MODELS=$INSTALL_PROMPT_SUPPORT_MODELS"
  fi
}

verify_install() {
  local checker="$SCRIPT_DIR/verify_wan22_remix_ready.sh"
  [ -x "$checker" ] || fail "Verification helper not found or not executable: $checker"
  log "Verifying installed files with $checker"
  COMFY_DIR="$COMFY_DIR" \
  VENV_DIR="$VENV_DIR" \
  WORKSPACE_DIR="$WORKSPACE_DIR" \
  MODEL_STORE_DIR="$MODEL_STORE_DIR" \
  INSTALL_NODES="$INSTALL_NODES" \
  INSTALL_MODELS="$INSTALL_MODELS" \
  INSTALL_QWENVL="$INSTALL_QWENVL" \
  INSTALL_QWENVL_MODEL="$INSTALL_QWENVL_MODEL" \
  INSTALL_FLUX_KONTEXT_MODEL="$INSTALL_FLUX_KONTEXT_MODEL" \
  INSTALL_PROMPT_SUPPORT_MODELS="$INSTALL_PROMPT_SUPPORT_MODELS" \
  INSTALL_LLAMACPP="$INSTALL_LLAMACPP" \
  QWENVL_MODEL_NAME="$QWENVL_MODEL_NAME" \
  "$checker"
}

print_summary() {
  log "Done"
  log "ComfyUI: $COMFY_DIR"
  log "Custom nodes: $COMFY_DIR/custom_nodes"
  log "Story Shot tools: $COMFY_DIR/custom_nodes/ComfyUI-WanStoryShotTools"
  log "Diffusion models: $MODEL_STORE_DIR/diffusion_models"
  log "Text encoders: $MODEL_STORE_DIR/text_encoders"
  log "LoRAs: $MODEL_STORE_DIR/loras"
  log "VAE: $MODEL_STORE_DIR/vae"
  log "Model store: $MODEL_STORE_DIR"
  log "QwenVL model: $MODEL_STORE_DIR/LLM/Qwen-VL/$QWENVL_MODEL_NAME"
  if [ "$INSTALL_FLUX_KONTEXT_MODEL" = "1" ]; then
    log "Flux Kontext model: $MODEL_STORE_DIR/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors"
  fi
  log "Restart ComfyUI, then hard refresh browser with Ctrl+F5."
}

main() {
  require_base_paths
  install_custom_nodes
  install_sample_input_files
  write_qwenvl_custom_models
  disable_duplicate_custom_nodes
  patch_videohelpersuite_frontend
  install_models
  verify_install
  if [ "$INSTALL_MODELS" = "1" ]; then
    touch "$MODEL_STORE_DIR/.comfy_wan_models_setup_done"
  fi
  print_summary
}

main "$@"
