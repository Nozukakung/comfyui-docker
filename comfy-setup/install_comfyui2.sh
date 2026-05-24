#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE_DIR/ComfyUI}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
PORT="${PORT:-8188}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
COMFY_REPO="${COMFY_REPO:-https://github.com/comfyanonymous/ComfyUI.git}"
COMFY_REF="${COMFY_REF:-}"
RUN_SCRIPT_PATH="${RUN_SCRIPT_PATH:-$WORKSPACE_DIR/run_comfy.sh}"
COMFY_EXTRA_ARGS="${COMFY_EXTRA_ARGS:---reserve-vram 2}"
USE_SYSTEM_SITE_PACKAGES="${USE_SYSTEM_SITE_PACKAGES:-0}"
UPDATE_REPOS="${UPDATE_REPOS:-1}"
INSTALL_CUSTOM_NODES="${INSTALL_CUSTOM_NODES:-1}"
START_COMFY_AFTER_INSTALL="${START_COMFY_AFTER_INSTALL:-0}"
MANAGER_SECURITY_LEVEL="${MANAGER_SECURITY_LEVEL:-weak}"
MANAGER_NETWORK_MODE="${MANAGER_NETWORK_MODE:-personal_cloud}"
FORCE_TORCH_INSTALL="${FORCE_TORCH_INSTALL:-0}"
PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL:-auto}"
PYTORCH_PACKAGES="${PYTORCH_PACKAGES:-auto}"
LOCK_TORCH_PACKAGES="${LOCK_TORCH_PACKAGES:-1}"
GPU_PREFLIGHT="${GPU_PREFLIGHT:-1}"
ALLOW_BAD_GPU_PREFLIGHT="${ALLOW_BAD_GPU_PREFLIGHT:-0}"
REQUIRE_NVIDIA0="${REQUIRE_NVIDIA0:-1}"
PROMPT_ON_MISSING_NVIDIA0="${PROMPT_ON_MISSING_NVIDIA0:-1}"
PROMPT_ON_BAD_NVIDIA_VISIBLE_DEVICES="${PROMPT_ON_BAD_NVIDIA_VISIBLE_DEVICES:-1}"
GIT_RETRY_COUNT="${GIT_RETRY_COUNT:-4}"
GIT_RETRY_SLEEP="${GIT_RETRY_SLEEP:-5}"
GIT_CLONE_DEPTH="${GIT_CLONE_DEPTH:-1}"
SKIP_APT="${SKIP_APT:-0}"
APT_UPDATE="${APT_UPDATE:-1}"
APT_MIRROR="${APT_MIRROR:-}"
KORNIA_PACKAGE="${KORNIA_PACKAGE:-kornia==0.8.2}"
DISABLE_DUPLICATE_CUSTOM_NODES="${DISABLE_DUPLICATE_CUSTOM_NODES:-1}"
VRGAMEDEVGIRL_PACKAGES="${VRGAMEDEVGIRL_PACKAGES:-librosa av}"

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_CACHE_DIR="${PIP_NO_CACHE_DIR:-1}"
export GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}"
export GIT_ASKPASS="${GIT_ASKPASS:-/bin/false}"
export TMPDIR="${TMPDIR:-$WORKSPACE_DIR/tmp}"
export HF_HOME="${HF_HOME:-$WORKSPACE_DIR/.cache/huggingface}"
export TORCH_HOME="${TORCH_HOME:-$WORKSPACE_DIR/.cache/torch}"

log() { echo "[install] $*"; }
warn() { echo "[install][warn] $*" >&2; }
fail() { echo "[install][error] $*" >&2; exit 1; }

on_error() {
  local exit_code=$?
  local line_no=${1:-unknown}
  echo "[install][error] Failed at line $line_no with exit code $exit_code" >&2
  exit "$exit_code"
}
trap 'on_error "$LINENO"' ERR

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

retry_cmd() {
  local label="$1"
  shift
  local attempt

  for attempt in $(seq 1 "$GIT_RETRY_COUNT"); do
    if "$@"; then
      return 0
    fi

    if [ "$attempt" -lt "$GIT_RETRY_COUNT" ]; then
      warn "$label failed on attempt $attempt/$GIT_RETRY_COUNT; retrying in ${GIT_RETRY_SLEEP}s"
      sleep "$GIT_RETRY_SLEEP"
    fi
  done

  return 1
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "Root privileges or sudo are required to run: $*"
  fi
}

preflight_fail() {
  if [ "$ALLOW_BAD_GPU_PREFLIGHT" = "1" ]; then
    warn "$*"
    warn "Continuing because ALLOW_BAD_GPU_PREFLIGHT=1"
    return 0
  fi

  fail "$*"
}

confirm_missing_nvidia0() {
  local message="$1"
  local answer

  warn "$message"
  warn "Some RunPod pods without /dev/nvidia0 can still work, but this layout has caused PyTorch CUDA init failures before."

  if [ "$PROMPT_ON_MISSING_NVIDIA0" != "1" ]; then
    preflight_fail "$message Use REQUIRE_NVIDIA0=0 to bypass."
    return 0
  fi

  if [ ! -t 0 ]; then
    preflight_fail "$message No interactive terminal is available to ask for confirmation. Use REQUIRE_NVIDIA0=0 to bypass."
    return 0
  fi

  read -r -p "[install] Continue anyway? [y/N] " answer || answer=""
  case "$answer" in
    y|Y|yes|YES)
      warn "Continuing without /dev/nvidia0 because user confirmed."
      return 0
      ;;
    *)
      fail "Stopped because /dev/nvidia0 is missing and user did not confirm."
      ;;
  esac
}

confirm_bad_nvidia_visible_devices() {
  local message="$1"
  local answer

  warn "$message"
  warn "nvidia-smi can sometimes still see the GPU in this state, but PyTorch CUDA may fail. Continuing will set NVIDIA_VISIBLE_DEVICES=all for this process."

  if [ "$PROMPT_ON_BAD_NVIDIA_VISIBLE_DEVICES" != "1" ]; then
    preflight_fail "$message Use ALLOW_BAD_GPU_PREFLIGHT=1 to bypass."
    return 0
  fi

  if [ ! -t 0 ]; then
    preflight_fail "$message No interactive terminal is available to ask for confirmation. Use ALLOW_BAD_GPU_PREFLIGHT=1 to bypass."
    return 0
  fi

  read -r -p "[install] Continue anyway and set NVIDIA_VISIBLE_DEVICES=all? [y/N] " answer || answer=""
  case "$answer" in
    y|Y|yes|YES)
      export NVIDIA_VISIBLE_DEVICES=all
      warn "Continuing with NVIDIA_VISIBLE_DEVICES=all because user confirmed."
      return 0
      ;;
    *)
      fail "Stopped because NVIDIA_VISIBLE_DEVICES is invalid and user did not confirm."
      ;;
  esac
}

gpu_preflight() {
  if [ "$GPU_PREFLIGHT" != "1" ]; then
    log "Skipping GPU preflight because GPU_PREFLIGHT=$GPU_PREFLIGHT"
    return 0
  fi

  log "RunPod GPU preflight"
  echo "[preflight] NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-<unset>}"
  echo "[preflight] CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"
  echo "[preflight] LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}"

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    preflight_fail "nvidia-smi not found. This does not look like a usable NVIDIA GPU pod."
    return 0
  fi

  echo "[preflight] nvidia-smi"
  if ! nvidia-smi; then
    preflight_fail "nvidia-smi failed. Recreate the RunPod pod before installing."
    return 0
  fi

  echo "[preflight] /dev/nvidia*"
  ls -l /dev/nvidia* 2>/dev/null || true
  if [ -d /dev/nvidia-caps ]; then
    ls -l /dev/nvidia-caps 2>/dev/null || true
  fi

  if [ "${NVIDIA_VISIBLE_DEVICES:-}" = "void" ] || [ "${NVIDIA_VISIBLE_DEVICES:-}" = "none" ]; then
    confirm_bad_nvidia_visible_devices "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}. This pod's GPU runtime may not be attached correctly."
    return 0
  fi

  if ! compgen -G "/dev/nvidia[0-9]*" >/dev/null; then
    preflight_fail "No /dev/nvidia[0-9]* GPU device is visible. Recreate the RunPod pod."
    return 0
  fi

  if [ "$REQUIRE_NVIDIA0" = "1" ] && [ ! -e /dev/nvidia0 ]; then
    confirm_missing_nvidia0 "No /dev/nvidia0 found. This pod exposes a non-zero GPU device only."
    return 0
  fi

  if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "[preflight] python torch check"
    "$PYTHON_BIN" - <<'PY' || true
try:
    import torch
except Exception as exc:
    print(f"torch preflight: not importable yet ({exc})")
    raise SystemExit(0)

print(f"torch preflight: version={torch.__version__} cuda={torch.version.cuda} available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"torch preflight: gpu={torch.cuda.get_device_name(0)}")
else:
    print("torch preflight: CUDA is not available in the current Python environment. Installer may replace PyTorch if the GPU device mapping above is healthy.")
PY
  fi

  log "GPU preflight passed"
}

install_apt_packages() {
  if [ "$SKIP_APT" = "1" ]; then
    log "Skipping apt package installation because SKIP_APT=1"
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found; skipping system package installation"
    return 0
  fi

  configure_apt_mirror

  log "Installing system packages"
  if [ "$APT_UPDATE" = "1" ]; then
    run_as_root apt-get update
  else
    log "Skipping apt-get update because APT_UPDATE=$APT_UPDATE"
  fi
  run_as_root apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    ffmpeg \
    aria2 \
    wget \
    curl \
    ca-certificates \
    build-essential \
    ninja-build \
    python3-dev \
    python3-venv \
    pkg-config \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1
  run_as_root apt-get clean
  run_as_root rm -rf /var/lib/apt/lists/*
}

configure_apt_mirror() {
  local mirror
  local file

  if [ -z "$APT_MIRROR" ]; then
    return 0
  fi

  mirror="${APT_MIRROR%/}"
  log "Using Ubuntu apt mirror: $mirror"

  if [ -f /etc/apt/sources.list ]; then
    run_as_root cp -n /etc/apt/sources.list /etc/apt/sources.list.bak-comfy 2>/dev/null || true
    run_as_root sed -i -E \
      -e "s#https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?#${mirror}#g" \
      -e "s#https?://security\.ubuntu\.com/ubuntu/?#${mirror}#g" \
      /etc/apt/sources.list
  fi

  for file in /etc/apt/sources.list.d/*.sources; do
    [ -f "$file" ] || continue
    if grep -Eq 'https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?|https?://security\.ubuntu\.com/ubuntu/?' "$file"; then
      run_as_root cp -n "$file" "$file.bak-comfy" 2>/dev/null || true
      run_as_root sed -i -E \
        -e "s#https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?#${mirror}#g" \
        -e "s#https?://security\.ubuntu\.com/ubuntu/?#${mirror}#g" \
        "$file"
    fi
  done
}

check_python_version() {
  "$PYTHON_BIN" - <<'PY'
import sys
if sys.version_info < (3, 10):
    raise SystemExit(f"Python 3.10+ is required, got {sys.version.split()[0]}")
print(sys.version.split()[0])
PY
}

clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local label="$3"

  if [ -d "$target_dir/.git" ]; then
    if [ "$UPDATE_REPOS" = "1" ]; then
      log "Updating $label at $target_dir"
      retry_cmd "Updating $label" git -C "$target_dir" pull --ff-only
      retry_cmd "Updating $label submodules" git -C "$target_dir" submodule update --init --recursive
    else
      log "Using existing $label at $target_dir"
    fi
    return 0
  fi

  if [ -e "$target_dir" ] && [ ! -d "$target_dir/.git" ]; then
    fail "$label path exists but is not a git checkout: $target_dir"
  fi

  log "Cloning $label into $target_dir"
  if [ "$GIT_CLONE_DEPTH" = "0" ]; then
    retry_cmd "Cloning $label" git clone --recursive "$repo_url" "$target_dir"
  else
    retry_cmd "Cloning $label" git clone --depth "$GIT_CLONE_DEPTH" --recursive --shallow-submodules "$repo_url" "$target_dir"
  fi
}

clone_or_update_custom_node() {
  local repo_url="$1"
  local target_dir="$2"
  local label="$3"
  local required="$4"

  if clone_or_update_repo "$repo_url" "$target_dir" "$label"; then
    return 0
  fi

  if [ "$required" = "required" ]; then
    fail "Required custom node failed to install: $label ($repo_url)"
  fi

  warn "Optional custom node skipped because it could not be installed: $label ($repo_url)"
  return 0
}

checkout_repo_ref() {
  local target_dir="$1"
  local ref="$2"
  local label="$3"

  if [ -z "$ref" ]; then
    return 0
  fi

  log "Checking out $label ref: $ref"
  git -C "$target_dir" fetch --tags --prune origin
  git -C "$target_dir" checkout "$ref"
  git -C "$target_dir" submodule update --init --recursive
}

create_venv() {
  if [ -x "$VENV_DIR/bin/python" ]; then
    log "Using existing venv at $VENV_DIR"
    return 0
  fi

  log "Creating Python venv at $VENV_DIR"
  if [ "$USE_SYSTEM_SITE_PACKAGES" = "1" ]; then
    "$PYTHON_BIN" -m venv --system-site-packages "$VENV_DIR"
  else
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi
}

pip_install() {
  "$VENV_DIR/bin/python" -m pip install "$@"
}

write_torch_constraints() {
  local output_file="$1"

  "$VENV_DIR/bin/python" - "$output_file" <<'PY'
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

  "$VENV_DIR/bin/python" - "$input_file" "$output_file" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
blocked = re.compile(r"^\s*(?:-e\s+)?(?:torch|torchvision|torchaudio|xformers|triton)\b", re.I)

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
  local filtered_file

  if [ ! -f "$requirements_file" ]; then
    log "Skipping $label requirements; file not found"
    return 0
  fi

  filtered_file="$(mktemp)"
  filter_requirements "$requirements_file" "$filtered_file"
  log "Installing $label requirements without torch/xformers/triton"
  if [ "$LOCK_TORCH_PACKAGES" = "1" ]; then
    local constraints_file
    constraints_file="$(mktemp)"
    write_torch_constraints "$constraints_file"
    pip_install -c "$constraints_file" -r "$filtered_file"
    rm -f "$constraints_file"
  else
    pip_install -r "$filtered_file"
  fi
  rm -f "$filtered_file"
}

install_vrgamedevgirl_minimal_requirements() {
  local constraints_file

  log "Installing comfyui-vrgamedevgirl minimal FastFilmGrain dependencies: $VRGAMEDEVGIRL_PACKAGES"
  constraints_file="$(mktemp)"
  write_torch_constraints "$constraints_file"
  pip_install -c "$constraints_file" --upgrade $VRGAMEDEVGIRL_PACKAGES
  rm -f "$constraints_file"
}

install_custom_node_requirements() {
  local requirements_file="$1"
  local label="$2"

  case "$label" in
    comfyui-vrgamedevgirl)
      warn "Skipping full $label requirements because they include heavy/optional packages; installing only what FastFilmGrain needs."
      install_vrgamedevgirl_minimal_requirements
      ;;
    *)
      install_requirements_without_gpu_packages "$requirements_file" "$label"
      ;;
  esac
}

torch_cuda_ok() {
  "$VENV_DIR/bin/python" - <<'PY'
import sys
try:
    import torch
except Exception as exc:
    print(f"torch import failed: {exc}")
    raise SystemExit(1)

print(f"torch: {torch.__version__}")
print(f"cuda: {torch.version.cuda}")
print(f"cuda available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"gpu: {torch.cuda.get_device_name(0)}")
    raise SystemExit(0)
raise SystemExit(1)
PY
}

torch_stack_ok() {
  "$VENV_DIR/bin/python" - <<'PY'
import sys
try:
    import torch
except Exception as exc:
    print(f"torch import failed: {exc}")
    raise SystemExit(1)

def parse(version):
    base = version.split("+", 1)[0]
    return tuple(int(part) for part in base.split(".")[:2])

print(f"torch: {torch.__version__}")
print(f"cuda: {torch.version.cuda}")
print(f"cuda available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"gpu: {torch.cuda.get_device_name(0)}")

if not torch.cuda.is_available():
    raise SystemExit(1)
if parse(torch.__version__) < (2, 8):
    print("torch is lower than 2.8; reinstalling for ComfyUI DynamicVRAM/LTX compatibility")
    raise SystemExit(1)
raise SystemExit(0)
PY
}

probe_cuda_visibility() {
  local candidates
  local candidate
  local dev

  candidates=("unset" "0")
  for dev in /dev/nvidia[0-9]*; do
    [ -e "$dev" ] || continue
    candidates+=("${dev#/dev/nvidia}")
  done

  for candidate in "${candidates[@]}"; do
    if [ "$candidate" = "unset" ]; then
      log "Probing CUDA with CUDA_VISIBLE_DEVICES unset"
      if env -u CUDA_VISIBLE_DEVICES "$VENV_DIR/bin/python" - <<'PY'
import torch
raise SystemExit(0 if torch.cuda.is_available() else 1)
PY
      then
        unset CUDA_VISIBLE_DEVICES
        log "CUDA works with CUDA_VISIBLE_DEVICES unset"
        return 0
      fi
      continue
    fi

    log "Probing CUDA with CUDA_VISIBLE_DEVICES=$candidate"
    if CUDA_VISIBLE_DEVICES="$candidate" "$VENV_DIR/bin/python" - <<'PY'
import torch
raise SystemExit(0 if torch.cuda.is_available() else 1)
PY
    then
      export CUDA_VISIBLE_DEVICES="$candidate"
      log "CUDA works with CUDA_VISIBLE_DEVICES=$candidate"
      return 0
    fi
  done

  return 1
}

print_gpu_diagnostics() {
  log "GPU runtime diagnostics"
  echo "[install] CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"
  echo "[install] NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-<unset>}"
  echo "[install] LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}"

  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || true
    nvidia-smi -L || true
  else
    warn "nvidia-smi not found in this container"
  fi

  ls -l /dev/nvidia* 2>/dev/null || warn "No /dev/nvidia* devices are visible inside the container"
}

nvidia_runtime_ok() {
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1
}

normalize_cuda_env() {
  local devices

  if [ "${NVIDIA_VISIBLE_DEVICES:-}" = "void" ] || [ "${NVIDIA_VISIBLE_DEVICES:-}" = "none" ]; then
    warn "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}; overriding to all for this process"
    export NVIDIA_VISIBLE_DEVICES=all
  fi

  if [ ! -e /dev/nvidia0 ]; then
    mapfile -t devices < <(find /dev -maxdepth 1 -type c -name 'nvidia[0-9]*' | sort)
    if [ "${#devices[@]}" -eq 1 ]; then
      warn "Only ${devices[0]} is present; creating /dev/nvidia0 symlink for CUDA compatibility"
      ln -sf "${devices[0]}" /dev/nvidia0 || true
    fi
  fi
}

detect_driver_cuda_version() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 1
  fi

  nvidia-smi | sed -n 's/.*CUDA Version: \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

cuda_version_at_least() {
  local actual="$1"
  local required="$2"

  "$PYTHON_BIN" - "$actual" "$required" <<'PY'
import sys

def parse(value):
    parts = value.split(".")
    return tuple(int(part) for part in (parts + ["0", "0"])[:2])

raise SystemExit(0 if parse(sys.argv[1]) >= parse(sys.argv[2]) else 1)
PY
}

select_pytorch_stack() {
  local driver_cuda

  if [ "$PYTORCH_INDEX_URL" != "auto" ] && [ "$PYTORCH_PACKAGES" != "auto" ]; then
    return 0
  fi

  driver_cuda="$(detect_driver_cuda_version || true)"
  if [ -z "$driver_cuda" ]; then
    fail "Could not detect NVIDIA driver CUDA version from nvidia-smi. Set PYTORCH_INDEX_URL and PYTORCH_PACKAGES manually."
  fi

  if cuda_version_at_least "$driver_cuda" "12.8"; then
    PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu128"
    PYTORCH_PACKAGES="torch==2.11.0+cu128 torchvision==0.26.0+cu128 torchaudio==2.11.0+cu128"
  elif cuda_version_at_least "$driver_cuda" "12.6"; then
    PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu126"
    PYTORCH_PACKAGES="torch==2.11.0+cu126 torchvision==0.26.0+cu126 torchaudio==2.11.0+cu126"
  elif cuda_version_at_least "$driver_cuda" "12.4"; then
    PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu124"
    PYTORCH_PACKAGES="torch==2.6.0+cu124 torchvision==0.21.0+cu124 torchaudio==2.6.0+cu124"
  else
    fail "Driver CUDA $driver_cuda is too old for this ComfyUI/LTX setup. Use a RunPod image/host with NVIDIA driver CUDA 12.4+; CUDA 12.8+ is preferred."
  fi

  log "Selected PyTorch stack for driver CUDA $driver_cuda: $PYTORCH_INDEX_URL / $PYTORCH_PACKAGES"
}

install_configured_pytorch_stack() {
  select_pytorch_stack
  log "Installing configured PyTorch stack from $PYTORCH_INDEX_URL: $PYTORCH_PACKAGES"
  pip_install --index-url "$PYTORCH_INDEX_URL" --extra-index-url https://pypi.org/simple --upgrade --force-reinstall $PYTORCH_PACKAGES
}

ensure_torch() {
  normalize_cuda_env
  select_pytorch_stack

  if [ "$FORCE_TORCH_INSTALL" != "1" ] && torch_stack_ok; then
    log "Keeping existing CUDA-enabled PyTorch stack"
    return 0
  fi

  if [ "$FORCE_TORCH_INSTALL" != "1" ] && ! nvidia_runtime_ok; then
    print_gpu_diagnostics
    fail "NVIDIA GPU runtime is not available inside the container. Reinstalling PyTorch cannot fix this; restart the RunPod pod or create a new GPU pod/image with NVIDIA runtime attached, then confirm nvidia-smi works."
  fi

  install_configured_pytorch_stack

  if ! torch_cuda_ok && ! probe_cuda_visibility; then
    print_gpu_diagnostics
    fail "PyTorch installed but CUDA is not available. If NVIDIA_VISIBLE_DEVICES is void/none, restart or recreate the RunPod pod because the container GPU runtime was attached incorrectly."
  fi
}

sync_torchaudio_with_torch() {
  local torch_info
  local torch_version
  local cuda_tag
  local index_url
  local torchaudio_spec

  torch_info="$("$VENV_DIR/bin/python" - <<'PY'
import torch
version = torch.__version__.split("+", 1)[0]
cuda = torch.version.cuda
if cuda:
    tag = "cu" + cuda.replace(".", "")
    spec = f"torchaudio=={version}+{tag}"
else:
    tag = "cpu"
    spec = f"torchaudio=={version}"
print(version)
print(tag)
print(spec)
PY
)"
  torch_version="$(printf '%s\n' "$torch_info" | sed -n '1p')"
  cuda_tag="$(printf '%s\n' "$torch_info" | sed -n '2p')"
  torchaudio_spec="$(printf '%s\n' "$torch_info" | sed -n '3p')"
  index_url="https://download.pytorch.org/whl/${cuda_tag}"

  log "Installing $torchaudio_spec for torch $torch_version ($cuda_tag)"
  if ! pip_install --index-url "$index_url" --upgrade --force-reinstall --no-deps "$torchaudio_spec"; then
    warn "No matching $torchaudio_spec wheel was found for $cuda_tag; reinstalling the configured PyTorch stack instead"
    install_configured_pytorch_stack
  fi

  "$VENV_DIR/bin/python" - <<'PY'
import pathlib
import torch
import torchaudio

torch_path = pathlib.Path(torch.__file__).resolve()
torchaudio_path = pathlib.Path(torchaudio.__file__).resolve()
print(f"[install] torch import: {torch.__version__} from {torch_path}")
print(f"[install] torchaudio import: {torchaudio.__version__} from {torchaudio_path}")
torch_base, _, torch_local = torch.__version__.partition("+")
audio_base, _, audio_local = torchaudio.__version__.partition("+")
if torch_base != audio_base:
    raise SystemExit("torch and torchaudio versions do not match")
if torch_local and audio_local != torch_local:
    raise SystemExit("torch and torchaudio CUDA wheel tags do not match")
PY
}

install_ltx_runtime_pins() {
  local constraints_file

  log "Installing LTX runtime compatibility pins: $KORNIA_PACKAGE"
  constraints_file="$(mktemp)"
  write_torch_constraints "$constraints_file"
  pip_install -c "$constraints_file" --upgrade --force-reinstall --no-deps "$KORNIA_PACKAGE"
  rm -f "$constraints_file"
}

install_base_python_packages() {
  log "Upgrading pip tooling"
  pip_install --upgrade pip "setuptools<82" wheel

  ensure_torch

  install_requirements_without_gpu_packages "$COMFY_DIR/requirements.txt" "ComfyUI"

  if [ -f "$COMFY_DIR/manager_requirements.txt" ]; then
    install_requirements_without_gpu_packages "$COMFY_DIR/manager_requirements.txt" "ComfyUI built-in Manager"
  fi

  log "Installing common custom-node runtime packages"
  local constraints_file
  constraints_file="$(mktemp)"
  write_torch_constraints "$constraints_file"
  pip_install -c "$constraints_file" --upgrade \
    ninja \
    packaging \
    accelerate \
    diffusers \
    einops \
    safetensors \
    sentencepiece \
    protobuf \
    huggingface_hub \
    hf_transfer \
    opencv-python \
    imageio \
    imageio-ffmpeg \
    gguf \
    "$KORNIA_PACKAGE" \
    "transformers[timm]"
  rm -f "$constraints_file"

  sync_torchaudio_with_torch
  install_ltx_runtime_pins
}

create_comfy_folders() {
  log "Creating ComfyUI folders"
  mkdir -p \
    "$COMFY_DIR/custom_nodes" \
    "$COMFY_DIR/input" \
    "$COMFY_DIR/output" \
    "$COMFY_DIR/user" \
    "$COMFY_DIR/models" \
    "$COMFY_DIR/models/checkpoints" \
    "$COMFY_DIR/models/clip" \
    "$COMFY_DIR/models/clip_vision" \
    "$COMFY_DIR/models/configs" \
    "$COMFY_DIR/models/controlnet" \
    "$COMFY_DIR/models/diffusers" \
    "$COMFY_DIR/models/diffusion_models" \
    "$COMFY_DIR/models/embeddings" \
    "$COMFY_DIR/models/gligen" \
    "$COMFY_DIR/models/hypernetworks" \
    "$COMFY_DIR/models/loras" \
    "$COMFY_DIR/models/photomaker" \
    "$COMFY_DIR/models/style_models" \
    "$COMFY_DIR/models/text_encoders" \
    "$COMFY_DIR/models/unet" \
    "$COMFY_DIR/models/upscale_models" \
    "$COMFY_DIR/models/vae" \
    "$COMFY_DIR/models/vae_approx" \
    "$COMFY_DIR/models/animatediff_models" \
    "$COMFY_DIR/models/animatediff_motion_lora" \
    "$COMFY_DIR/models/liveportrait" \
    "$COMFY_DIR/models/insightface" \
    "$COMFY_DIR/models/latent_upscale_models" \
    "$COMFY_DIR/models/pulid" \
    "$COMFY_DIR/models/ipadapter" \
    "$COMFY_DIR/models/instantid" \
    "$COMFY_DIR/models/ultralytics" \
    "$COMFY_DIR/models/sams" \
    "$COMFY_DIR/models/grounding-dino" \
    "$COMFY_DIR/models/LLM" \
    "$COMFY_DIR/models/LLM_gguf"
}

write_manager_config() {
  local manager_user_dir="$COMFY_DIR/user/__manager"
  local legacy_manager_dir="$COMFY_DIR/user/default/ComfyUI-Manager"

  log "Writing Manager config for remote RunPod usage"
  mkdir -p "$manager_user_dir" "$legacy_manager_dir"

  cat > "$manager_user_dir/config.ini" <<EOF
[default]
security_level = ${MANAGER_SECURITY_LEVEL}
network_mode = ${MANAGER_NETWORK_MODE}
EOF

  cat > "$legacy_manager_dir/config.ini" <<EOF
[default]
security_level = ${MANAGER_SECURITY_LEVEL}
network_mode = ${MANAGER_NETWORK_MODE}
EOF
}

write_run_script() {
  log "Creating RunPod start script at $RUN_SCRIPT_PATH"
  cat > "$RUN_SCRIPT_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="${COMFY_DIR}"
VENV_DIR="${VENV_DIR}"
PORT="\${PORT:-${PORT}}"
COMFY_EXTRA_ARGS="\${COMFY_EXTRA_ARGS:-${COMFY_EXTRA_ARGS}}"

export HF_HOME="\${HF_HOME:-${HF_HOME}}"
export TORCH_HOME="\${TORCH_HOME:-${TORCH_HOME}}"
export TMPDIR="\${TMPDIR:-${TMPDIR}}"
export HF_XET_HIGH_PERFORMANCE="\${HF_XET_HIGH_PERFORMANCE:-1}"
if [ "\${NVIDIA_VISIBLE_DEVICES:-}" = "void" ] || [ "\${NVIDIA_VISIBLE_DEVICES:-}" = "none" ]; then
  export NVIDIA_VISIBLE_DEVICES=all
fi
if [ -z "\${CUDA_VISIBLE_DEVICES:-}" ]; then
  export CUDA_VISIBLE_DEVICES=0
fi

mkdir -p "\$HF_HOME" "\$TORCH_HOME" "\$TMPDIR"
cd "\$COMFY_DIR"
source "\$VENV_DIR/bin/activate"
exec python main.py --listen 0.0.0.0 --port "\$PORT" --enable-manager \$COMFY_EXTRA_ARGS
EOF

  chmod +x "$RUN_SCRIPT_PATH"
}

disable_duplicate_custom_nodes() {
  local disabled_root="$COMFY_DIR/custom_nodes_disabled"
  local duplicate_sets=(
    "$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite|$COMFY_DIR/custom_nodes/comfyui-videohelpersuite"
    "$COMFY_DIR/custom_nodes/comfyui-essentials|$COMFY_DIR/custom_nodes/comfyui_essentials"
  )
  local pair keep duplicate disabled duplicates

  if [ "$DISABLE_DUPLICATE_CUSTOM_NODES" != "1" ]; then
    log "Skipping duplicate custom-node cleanup because DISABLE_DUPLICATE_CUSTOM_NODES=$DISABLE_DUPLICATE_CUSTOM_NODES"
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
  local patched=0
  local script_path
  local candidates=(
    "$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite/web/js/VHS.core.js"
    "$COMFY_DIR/custom_nodes/comfyui-videohelpersuite/web/js/VHS.core.js"
  )

  for script_path in "${candidates[@]}"; do
    if [ ! -f "$script_path" ]; then
      continue
    fi

    if grep -q 'helpDOM.addHelp(this, nodeType, description)' "$script_path"; then
      log "Patching VideoHelperSuite frontend compatibility: $script_path"
      cp "$script_path" "${script_path}.bak-hotfix-$(date +%Y%m%d-%H%M%S)"
      perl -0pi -e 's/helpDOM\.addHelp\(this, nodeType, description\)/if (typeof helpDOM?.addHelp === "function") { helpDOM.addHelp(this, nodeType, description) }/' "$script_path"
      patched=1
    elif grep -q 'typeof helpDOM?.addHelp === "function"' "$script_path"; then
      log "VideoHelperSuite frontend patch already present: $script_path"
      patched=1
    fi
  done

  if [ "$patched" = "0" ]; then
    warn "VideoHelperSuite VHS.core.js was not found; skipping frontend patch"
  fi
}

install_custom_nodes() {
  if [ "$INSTALL_CUSTOM_NODES" != "1" ]; then
    log "Skipping custom nodes because INSTALL_CUSTOM_NODES=$INSTALL_CUSTOM_NODES"
    return 0
  fi

  log "Installing custom nodes"
  local nodes=(
    "https://github.com/rgthree/rgthree-comfy.git|$COMFY_DIR/custom_nodes/rgthree-comfy|rgthree-comfy|required"
    "https://github.com/yolain/ComfyUI-Easy-Use.git|$COMFY_DIR/custom_nodes/ComfyUI-Easy-Use|ComfyUI-Easy-Use|required"
    "https://github.com/kijai/ComfyUI-KJNodes.git|$COMFY_DIR/custom_nodes/ComfyUI-KJNodes|ComfyUI-KJNodes|required"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git|$COMFY_DIR/custom_nodes/ComfyUI-Custom-Scripts|ComfyUI-Custom-Scripts|required"
    "https://github.com/kosinkadink/ComfyUI-VideoHelperSuite.git|$COMFY_DIR/custom_nodes/ComfyUI-VideoHelperSuite|ComfyUI-VideoHelperSuite|required"
    "https://github.com/Lightricks/ComfyUI-LTXVideo.git|$COMFY_DIR/custom_nodes/ComfyUI-LTXVideo|ComfyUI-LTXVideo|required"
    "https://github.com/city96/ComfyUI-GGUF.git|$COMFY_DIR/custom_nodes/ComfyUI-GGUF|ComfyUI-GGUF|required"
    "https://github.com/vrgamegirl19/comfyui-vrgamedevgirl.git|$COMFY_DIR/custom_nodes/comfyui-vrgamedevgirl|comfyui-vrgamedevgirl|required"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git|$COMFY_DIR/custom_nodes/comfyui-impact-pack|ComfyUI-Impact-Pack|optional"
    "https://github.com/SeanScripts/ComfyUI-Unload-Model.git|$COMFY_DIR/custom_nodes/ComfyUI-Unload-Model|ComfyUI-Unload-Model|optional"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git|$COMFY_DIR/custom_nodes/ComfyUI-Frame-Interpolation|ComfyUI-Frame-Interpolation|optional"
    "https://github.com/comfyorg/comfyui-essentials.git|$COMFY_DIR/custom_nodes/comfyui-essentials|comfyui-essentials|optional"
    "https://github.com/ClownsharkBatwing/RES4LYF.git|$COMFY_DIR/custom_nodes/RES4LYF|RES4LYF|optional"
    "https://github.com/WASasquatch/was-node-suite-comfyui.git|$COMFY_DIR/custom_nodes/was-node-suite-comfyui|was-node-suite-comfyui|optional"
    "https://github.com/kijai/ComfyUI-MelBandRoFormer.git|$COMFY_DIR/custom_nodes/ComfyUI-MelBandRoFormer|ComfyUI-MelBandRoFormer|optional"
  )

  local entry repo_url target_dir label required
  for entry in "${nodes[@]}"; do
    IFS='|' read -r repo_url target_dir label required <<< "$entry"
    clone_or_update_custom_node "$repo_url" "$target_dir" "$label" "$required"
  done

  log "Installing custom-node requirements"
  for entry in "${nodes[@]}"; do
    IFS='|' read -r repo_url target_dir label required <<< "$entry"
    if [ ! -d "$target_dir" ]; then
      log "Skipping $label requirements; node directory not present"
      continue
    fi
    install_custom_node_requirements "$target_dir/requirements.txt" "$label"
  done
}

print_summary() {
  log "Installation complete"
  log "ComfyUI: $COMFY_DIR"
  log "Venv: $VENV_DIR"
  log "Start: $RUN_SCRIPT_PATH"
  log "URL: http://<runpod-host>:${PORT}"
  log "Models were not downloaded by this installer."
}

main() {
  mkdir -p "$WORKSPACE_DIR" "$TMPDIR" "$HF_HOME" "$TORCH_HOME"

  gpu_preflight
  install_apt_packages

  log "Checking required commands"
  require_cmd git
  require_cmd git-lfs
  require_cmd "$PYTHON_BIN"
  log "Python: $(check_python_version)"

  git lfs install --skip-repo

  clone_or_update_repo "$COMFY_REPO" "$COMFY_DIR" "ComfyUI"
  checkout_repo_ref "$COMFY_DIR" "$COMFY_REF" "ComfyUI"
  create_venv

  [ -x "$VENV_DIR/bin/python" ] || fail "Python executable not found in venv: $VENV_DIR/bin/python"
  [ -x "$VENV_DIR/bin/pip" ] || fail "pip executable not found in venv: $VENV_DIR/bin/pip"

  create_comfy_folders
  write_manager_config
  write_run_script
  install_base_python_packages
  install_custom_nodes
  disable_duplicate_custom_nodes
  patch_videohelpersuite_frontend
  sync_torchaudio_with_torch
  install_ltx_runtime_pins
  write_run_script

  log "Final PyTorch CUDA check"
  if ! torch_cuda_ok; then
    print_gpu_diagnostics
    fail "Final PyTorch CUDA check failed after installing ComfyUI/custom-node requirements."
  fi

  df -h "$WORKSPACE_DIR" || true
  print_summary

  if [ "$START_COMFY_AFTER_INSTALL" = "1" ]; then
    log "Starting ComfyUI because START_COMFY_AFTER_INSTALL=1"
    exec "$RUN_SCRIPT_PATH"
  fi
}

main "$@"
