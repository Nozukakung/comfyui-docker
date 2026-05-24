#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-${WORKSPACE:-/workspace}}"
VENV_DIR="${VENV_DIR:-$WORKSPACE_DIR/venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL:-auto}"
PYTORCH_PACKAGES="${PYTORCH_PACKAGES:-auto}"
KORNIA_PACKAGE="${KORNIA_PACKAGE:-kornia==0.8.2}"
CUDA_RUNTIME_REPAIR="${CUDA_RUNTIME_REPAIR:-1}"

log() { echo "[cuda-check] $*"; }
warn() { echo "[cuda-check][warn] $*" >&2; }
fail() { echo "[cuda-check][error] $*" >&2; exit 1; }

require_venv() {
  [ -x "$VENV_DIR/bin/python" ] || fail "venv python not found: $VENV_DIR/bin/python"
  [ -x "$VENV_DIR/bin/pip" ] || fail "venv pip not found: $VENV_DIR/bin/pip"
}

detect_driver_cuda_version() {
  command -v nvidia-smi >/dev/null 2>&1 || return 1
  nvidia-smi | sed -n 's/.*CUDA Version: \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

cuda_version_at_least() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
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
  [ -n "$driver_cuda" ] || fail "Could not detect NVIDIA driver CUDA version from nvidia-smi"

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
    fail "Driver CUDA $driver_cuda is too old. Use NVIDIA driver CUDA 12.4+; CUDA 12.8+ is preferred."
  fi

  log "Selected PyTorch stack: $PYTORCH_INDEX_URL / $PYTORCH_PACKAGES"
}

normalize_cuda_env() {
  if [ "${NVIDIA_VISIBLE_DEVICES:-}" = "void" ] || [ "${NVIDIA_VISIBLE_DEVICES:-}" = "none" ]; then
    warn "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES}; overriding to all"
    export NVIDIA_VISIBLE_DEVICES=all
  fi

  if [ -z "${CUDA_VISIBLE_DEVICES:-}" ]; then
    export CUDA_VISIBLE_DEVICES=0
  fi
}

expected_cuda_tag() {
  case "$PYTORCH_INDEX_URL" in
    */cu128) echo "cu128" ;;
    */cu126) echo "cu126" ;;
    */cu124) echo "cu124" ;;
    *) echo "" ;;
  esac
}

torch_stack_ok() {
  local tag
  tag="$(expected_cuda_tag)"

  "$VENV_DIR/bin/python" - "$tag" <<'PY'
import sys

expected_tag = sys.argv[1]

try:
    import torch
    import torchvision
    import torchaudio
except Exception as exc:
    print(f"import failed: {exc}")
    raise SystemExit(1)

print(f"torch={torch.__version__} cuda={torch.version.cuda} available={torch.cuda.is_available()}")
print(f"torchvision={torchvision.__version__}")
print(f"torchaudio={torchaudio.__version__}")
if torch.cuda.is_available():
    print(f"gpu={torch.cuda.get_device_name(0)}")

if not torch.cuda.is_available():
    raise SystemExit(1)

torch_base, _, torch_tag = torch.__version__.partition("+")
audio_base, _, audio_tag = torchaudio.__version__.partition("+")

if expected_tag and torch_tag != expected_tag:
    print(f"torch CUDA tag mismatch: got {torch_tag}, expected {expected_tag}")
    raise SystemExit(1)
if torch_base != audio_base:
    print(f"torch/torchaudio version mismatch: {torch_base} vs {audio_base}")
    raise SystemExit(1)
if torch_tag and audio_tag != torch_tag:
    print(f"torch/torchaudio CUDA tag mismatch: {torch_tag} vs {audio_tag}")
    raise SystemExit(1)
PY
}

repair_torch_stack() {
  if [ "$CUDA_RUNTIME_REPAIR" != "1" ]; then
    fail "CUDA stack check failed and CUDA_RUNTIME_REPAIR=$CUDA_RUNTIME_REPAIR"
  fi

  log "Repairing PyTorch CUDA stack"
  "$VENV_DIR/bin/python" -m pip install \
    --index-url "$PYTORCH_INDEX_URL" \
    --extra-index-url https://pypi.org/simple \
    --upgrade \
    --force-reinstall \
    $PYTORCH_PACKAGES

  log "Refreshing runtime compatibility pin: $KORNIA_PACKAGE"
  "$VENV_DIR/bin/python" -m pip install --upgrade --force-reinstall --no-deps "$KORNIA_PACKAGE"
}

main() {
  require_venv
  normalize_cuda_env
  select_pytorch_stack

  if torch_stack_ok; then
    log "CUDA stack is healthy"
    return 0
  fi

  repair_torch_stack
  torch_stack_ok || fail "CUDA stack is still unhealthy after repair"
  log "CUDA stack repair complete"
}

main "$@"
