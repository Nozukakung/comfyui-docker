# Vast.ai ComfyUI (Wan2.2 Remix) Docker

Image นี้จะ:

1. รัน `install_comfyui2.sh` ครั้งแรกเพื่อสร้าง ComfyUI + venv
2. รัน `install_wan22_remix_comfy.sh` ครั้งแรกเพื่อดึง nodes/models
3. เริ่ม ComfyUI ที่พอร์ต `8188`

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

หมายเหตุ: Setup จะทำครั้งแรกเท่านั้น โดยมี sentinel ที่ `/workspace/.comfy_wan_setup_done`
