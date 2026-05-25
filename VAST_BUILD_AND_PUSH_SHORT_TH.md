# Vast.ai Build & Push Cheat Sheet

ใช้ไฟล์นี้บนเครื่อง Vast.ai ได้เลย

## 1) ติดตั้งเครื่องมือ

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release git
```

### GitHub CLI

```bash
type -p curl >/dev/null || sudo apt install -y curl
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
sudo apt update
sudo apt install -y gh
```

### Docker

```bash
sudo apt remove -y docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc || true
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

ถ้า `docker` ใช้ไม่ได้:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## 2) Login GitHub

```bash
gh auth login
```

เลือก:

1. `GitHub.com`
2. `HTTPS`
3. `Y` สำหรับ git auth

ถ้ามี code:

1. เปิด `https://github.com/login/device`
2. ใส่ code ที่ `gh` แสดง
3. กด authorize

เช็ก:

```bash
gh auth status
gh auth setup-git
```

## 3) Clone repo

```bash
cd ~
git clone https://github.com/Nozukakung/comfyui-docker.git
cd comfyui-docker
git remote set-url origin https://github.com/Nozukakung/comfyui-docker.git
```

## 4) Login Docker Hub

```bash
export DOCKERHUB_USERNAME='nozukakung'
export DOCKERHUB_TOKEN='ใส่_token'
printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
```

## 5) เตรียม token สำหรับ build

```bash
export HF_TOKEN='ใส่_hf_token'
export CIVITAI_TOKEN='ใส่_civitai_token'
export DOCKER_BUILDKIT=1
```

## 6) Build image

```bash
cd ~/comfyui-docker
export IMAGE_NAME="nozukakung/comfyui-docker"
export IMAGE_TAG="latest"

docker build \
  --secret id=hf_token,env=HF_TOKEN \
  --secret id=civitai_token,env=CIVITAI_TOKEN \
  -t "$IMAGE_NAME:$IMAGE_TAG" \
  .
```

## 7) Push ขึ้น Docker Hub

```bash
docker push "$IMAGE_NAME:$IMAGE_TAG"
```

## 8) เช็กผล

```bash
docker image ls "$IMAGE_NAME"
docker pull "$IMAGE_NAME:$IMAGE_TAG"
```

## 9) ถ้าแก้โค้ดแล้ว push กลับ GitHub

```bash
git status --short
git add Dockerfile comfyui-start.sh Wan2-2-Remix/install_wan22_remix_comfy.sh .github/workflows/docker-build-push.yml README.md VAST_BUILD_AND_PUSH_TH.md VAST_BUILD_AND_PUSH_SHORT_TH.md
git commit -m "Update build flow"
git push -u origin main
```

## 10) ล้างพื้นที่

```bash
docker builder prune -af
docker image prune -af
docker system df
df -h
```
