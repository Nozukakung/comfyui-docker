FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WORKSPACE_DIR=/workspace
ENV COMFY_DIR=/workspace/ComfyUI
ENV VENV_DIR=/workspace/venv
ENV START_COMFY_AFTER_INSTALL=0
ENV INSTALL_MODELS=1
ENV INSTALL_NODES=1
ENV UPDATE_REPOS=1
ENV INSTALL_FLUX_KONTEXT_MODEL=1
ENV QWENVL_MODEL_NAME=Qwen3-VL-8B-Instruct-c_abliterated-v3
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

WORKDIR /opt/setup

COPY comfy-setup/install_comfyui2.sh /opt/setup/install_comfyui2.sh
COPY Wan2-2-Remix/install_wan22_remix_comfy.sh /opt/setup/install_wan22_remix_comfy.sh
COPY Wan2-2-Remix/custom_nodes /opt/setup/custom_nodes
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /opt/setup/install_comfyui2.sh /opt/setup/install_wan22_remix_comfy.sh /entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
