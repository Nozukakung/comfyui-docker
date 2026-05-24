# Vast.ai ComfyUI (Wan2.2 Remix) Docker

Image นี้ต่อยอดจาก `vastai/pytorch:cuda-12.8.1-auto` และยังใช้ startup/portal ของ Vast.ai base image เดิม โดยเพิ่ม ComfyUI เป็น Supervisor service.

Image นี้จะ:

1. ติดตั้ง ComfyUI + venv + custom nodes/deps ระหว่าง Docker build
2. ตอน container start ครั้งแรก จะโหลดเฉพาะ models ถ้า `INSTALL_MODELS=1`
3. เริ่ม ComfyUI ที่พอร์ต `8188` ผ่าน Supervisor ของ Vast.ai

## Build

```bash
cd /home/jakkrit/Stable-Diffusion/vast-comfyui-docker
docker build -t <dockerhub-username>/comfyui-wan22:latest .
```

## Push

```bash
docker push <dockerhub-username>/comfyui-wan22:latest
```

## Run local test (ต้องมี NVIDIA runtime)

```bash
docker run --gpus all --rm -it \
  -p 8188:8188 \
  -e HF_TOKEN=hf_xxx \
  -e CIVITAI_TOKEN=civitai_xxx \
  -v comfy_workspace:/workspace \
  <dockerhub-username>/comfyui-wan22:latest
```

## Vast.ai Environment Variables

- `HF_TOKEN` : Hugging Face token
- `CIVITAI_TOKEN` : Civitai token (ถ้ามี model ที่ต้องใช้)
- `INSTALL_MODELS` : `1` หรือ `0` (default `1`)
- `INSTALL_NODES` : `1` หรือ `0` (default `1`)
- `UPDATE_REPOS` : `1` หรือ `0` (default `1`)
- `INSTALL_FLUX_KONTEXT_MODEL` : `1` หรือ `0` (default `1`)
- `COMFY_PORT` : default `8188`
- `COMFY_EXTRA_ARGS` : default `--reserve-vram 2`

## Vast.ai Template

- ถ้าไม่จำเป็น ให้ใช้ entrypoint/cmd default ของ base image
- ถ้าตั้งค่า Start command/Entrypoint เอง ให้ใช้ `/opt/instance-tools/bin/entrypoint.sh`
- ถ้า template เดิมใส่ `entrypoint.sh` ไว้ image นี้ยังรองรับ โดย `/entrypoint.sh` จะส่งต่อไปยัง entrypoint ของ Vast.ai base ก่อน
- ComfyUI ถูกลงทะเบียนใน `PORTAL_CONFIG` เป็น `localhost:8188:8188:/:ComfyUI`

หมายเหตุ: Setup แยก sentinel เป็น:

- `/workspace/.comfy_base_setup_done` สำหรับ ComfyUI base
- `/workspace/.comfy_wan_nodes_setup_done` สำหรับ custom nodes/deps
- `/workspace/.comfy_wan_models_setup_done` สำหรับ models
