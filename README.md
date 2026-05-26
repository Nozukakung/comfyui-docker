# ComfyUI Docker (Wan2.2 Remix)

Image นี้ต่อยอดจาก `vastai/pytorch:cuda-12.8.1-auto` และใช้ ComfyUI + Supervisor เป็นหลัก

สิ่งที่ repo นี้ทำตอน build:

1. ติดตั้ง ComfyUI + venv + custom nodes/deps
2. ติดตั้งระบบให้ตอนรันสามารถดาวน์โหลด models ครั้งแรกไปไว้ที่ `/opt/comfy-models`
3. ตั้งค่าให้ตอนรันสามารถ symlink models กลับเข้า `/workspace/ComfyUI/models`
4. เปิด ComfyUI ที่พอร์ต `8188`

## โครงสร้างหลัก

- [`Dockerfile`](/data/data/com.termux/files/home/Stable-Diffusion/vast-comfyui-docker/Dockerfile)
- [`comfyui-start.sh`](/data/data/com.termux/files/home/Stable-Diffusion/vast-comfyui-docker/comfyui-start.sh)
- [`Wan2-2-Remix/install_wan22_remix_comfy.sh`](/data/data/com.termux/files/home/Stable-Diffusion/vast-comfyui-docker/Wan2-2-Remix/install_wan22_remix_comfy.sh)
- [`.github/workflows/docker-build-push.yml`](/data/data/com.termux/files/home/Stable-Diffusion/vast-comfyui-docker/.github/workflows/docker-build-push.yml)

## Build

ต้องมี Docker ที่รองรับ BuildKit

```bash
docker build -t <dockerhub-username>/comfyui-docker:latest .
```

image นี้จะติดตั้ง dependencies และ custom nodes ตอน build แต่จะดาวน์โหลด models ตอน runtime ครั้งแรก
ตอน runtime จะมี verifier ตรวจ custom nodes, QwenVL config, CUDA stack, และ prompt-support models ที่ workflow ต้องใช้ ถ้าพบว่า model store ขาดไฟล์บางส่วน ระบบจะซ่อมให้ก่อนเริ่ม ComfyUI
workflow นี้ยังต้องใช้ sample images ใน `ComfyUI/input` และระบบจะคัดลอกไฟล์ตัวอย่างจาก `Wan2-2-Remix/assets` ให้อัตโนมัติ

## Push

```bash
docker push <dockerhub-username>/comfyui-docker:latest
```

## Run

```bash
docker run --gpus all --rm -it \
  -p 8188:8188 \
  -v comfy_workspace:/workspace \
  -e HF_TOKEN=$HF_TOKEN \
  -e CIVITAI_TOKEN=$CIVITAI_TOKEN \
  <dockerhub-username>/comfyui-docker:latest
```

## ตัวแปรสำคัญ

- `INSTALL_MODELS` : `1` หรือ `0` (default `1`) ถ้าต้องการควบคุมการดาวน์โหลด models ตอน build/runtime
- `INSTALL_NODES` : `1` หรือ `0` (default `1`)
- `UPDATE_REPOS` : `1` หรือ `0` (default `1`)
- `INSTALL_FLUX_KONTEXT_MODEL` : `1` หรือ `0` (default `1`)
- `INSTALL_PROMPT_SUPPORT_MODELS` : `1` หรือ `0` (default `1`) ดาวน์โหลด `clip_interrogator` และ prompt-generator assets ที่บาง node ใช้
- `INSTALL_LLAMACPP` : `1` หรือ `0` (default `1`) ติดตั้ง `llama-cpp-python` สำหรับ QwenVL prompt enhancer
- `MODEL_STORE_DIR` : ตำแหน่งเก็บ model store ตอน build/runtime (default `/opt/comfy-models`)
- `HF_TOKEN` / `CIVITAI_TOKEN` : ใช้ตอน runtime ถ้าต้องดาวน์โหลด model เพิ่ม
- `COMFY_PORT` : default `8188`
- `COMFY_EXTRA_ARGS` : default `--reserve-vram 2`
- `CUDA_RUNTIME_CHECK` : `1` หรือ `0` (default `1`) ตรวจ torch/CUDA ก่อน start
- `CUDA_RUNTIME_REPAIR` : `1` หรือ `0` (default `1`) ซ่อม PyTorch stack เมื่อ CUDA ใช้ไม่ได้หรือ wheel tag ไม่ตรง driver

## GitHub Actions

Workflow build/push อยู่ที่ [`.github/workflows/docker-build-push.yml`](/data/data/com.termux/files/home/Stable-Diffusion/vast-comfyui-docker/.github/workflows/docker-build-push.yml)

ต้องมี GitHub Secrets อย่างน้อย:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `HF_TOKEN`
- `CIVITAI_TOKEN` ถ้ามีโมเดลที่ต้องใช้ token นี้

## หมายเหตุ

- `/workspace/.comfy_base_setup_done` สำหรับ ComfyUI base
- `/workspace/.comfy_wan_nodes_setup_done` สำหรับ custom nodes/deps
- `/opt/comfy-models/.comfy_wan_models_setup_done` สำหรับ models ที่ดาวน์โหลดตอน runtime ครั้งแรก
