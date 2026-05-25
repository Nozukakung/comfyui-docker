# คู่มือ build ComfyUI image บน Vast.ai แล้ว push ขึ้น Docker Hub

คู่มือนี้เขียนให้ใช้บนเครื่อง Vast.ai ที่เป็น Ubuntu/Debian-based shell ได้เลย
ถ้าคุณเป็น `root` อยู่แล้วให้ตัด `sudo` ออกได้ทั้งหมด

เป้าหมายของ flow นี้คือ:

1. ติดตั้งเครื่องมือที่ต้องใช้
2. ล็อกอิน GitHub ด้วย `gh`
3. ดึง repo นี้ลงมา
4. ล็อกอิน Docker Hub
5. build image แบบ bake model เข้า image เลย
6. push image ขึ้น Docker Hub

## 0) ข้อควรรู้ก่อน

- อย่าใส่ token ลงในไฟล์ หรือ commit ขึ้น git
- ให้ใช้ GitHub Secrets / Docker `--password-stdin` / BuildKit secrets แทน
- ถ้าใช้ image ใหญ่มาก ให้เผื่อเวลา download, build, และ push นานกว่าปกติมาก

## 1) ติดตั้ง git, gh และ Docker

### 1.1 อัปเดตรายการแพ็กเกจ

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
```

### 1.2 ติดตั้ง Git

```bash
sudo apt install -y git
git --version
```

### 1.3 ติดตั้ง GitHub CLI (`gh`)

วิธีที่ง่ายสุดบน Ubuntu คือใช้แพ็กเกจจาก GitHub CLI repository

```bash
type -p curl >/dev/null || sudo apt install -y curl
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
sudo apt update
sudo apt install -y gh
gh --version
```

### 1.4 ติดตั้ง Docker Engine + buildx + compose plugin

ใช้วิธี official repository ของ Docker

```bash
sudo apt remove -y docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc || true

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

docker --version
docker buildx version
```

ถ้า `docker` ยังใช้ไม่ได้เพราะ permission:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
docker ps
```

ถ้า `newgrp docker` ไม่พอ ให้ logout/login shell ใหม่อีกครั้ง

## 2) ล็อกอิน GitHub ด้วย `gh`

### 2.1 เริ่มล็อกอิน

```bash
gh auth login
```

### 2.2 ตอบ prompt ตามนี้

1. `Where do you use GitHub?` เลือก `GitHub.com`
2. `What is your preferred protocol for Git operations on this host?` เลือก `HTTPS`
3. `Authenticate Git with your GitHub credentials?` ตอบ `Y`

### 2.3 ถ้ามันแสดง code ให้ไปยืนยันใน browser

ตัวอย่างที่ `gh` จะพิมพ์ออกมา:

```text
! First copy your one-time code: XXXX-XXXX
Open this URL to continue in your web browser: https://github.com/login/device
```

ให้:

1. เปิด URL ที่มันแสดง
2. ใส่ one-time code
3. กด authorize ให้เรียบร้อย

### 2.4 ตรวจสถานะ

```bash
gh auth status
gh auth setup-git
```

ถ้า `gh auth status` แสดงว่า login แล้ว แปลว่าพร้อมใช้ `git push` ผ่าน GitHub account นี้

## 3) ดึง repo ลงเครื่อง Vast

```bash
cd ~
git clone https://github.com/Nozukakung/comfyui-docker.git
cd comfyui-docker
git status --short --branch
```

ถ้าคุณต้องการให้ remote ชี้ repo นี้แน่นอน:

```bash
git remote set-url origin https://github.com/Nozukakung/comfyui-docker.git
git remote -v
```

## 4) เตรียม Docker Hub login

ให้สร้าง Docker Hub access token ก่อน แล้วเก็บเป็น environment variable บนเครื่อง Vast

```bash
export DOCKERHUB_USERNAME='nozukakung'
export DOCKERHUB_TOKEN='ใส่_token_ของคุณที่นี่'
```

ล็อกอินด้วย token:

```bash
printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
```

ตรวจว่า login ผ่าน:

```bash
docker info | sed -n '/Username/,$p' | head
```

## 5) เตรียม token สำหรับโหลดโมเดลตอน build

ถ้า image ต้องดาวน์โหลดโมเดลจาก Hugging Face หรือ Civitai ตอน build ให้ใช้ secret แบบ BuildKit

```bash
export HF_TOKEN='ใส่_hf_token'
export CIVITAI_TOKEN='ใส่_civitai_token'
export DOCKER_BUILDKIT=1
```

หมายเหตุ:

- token เหล่านี้จะถูกส่งเป็น secret ตอน build
- ไม่ควรใส่ไว้ใน Dockerfile หรือ commit ขึ้น git

## 6) Build image

ชื่อ image ตัวอย่าง:

```bash
export IMAGE_NAME="nozukakung/comfyui-docker"
export IMAGE_TAG="latest"
```

สั่ง build:

```bash
docker build \
  --secret id=hf_token,env=HF_TOKEN \
  --secret id=civitai_token,env=CIVITAI_TOKEN \
  -t "$IMAGE_NAME:$IMAGE_TAG" \
  .
```

ถ้าอยาก tag เพิ่มตาม commit:

```bash
git rev-parse --short HEAD
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE_NAME:$(git rev-parse --short HEAD)"
```

ถ้าต้องการดูขนาด image:

```bash
docker image ls "$IMAGE_NAME"
docker history "$IMAGE_NAME:$IMAGE_TAG" | head -n 20
```

## 7) Push ขึ้น Docker Hub

```bash
docker push "$IMAGE_NAME:$IMAGE_TAG"
```

ถ้า tag เพิ่มตาม commit:

```bash
docker push "$IMAGE_NAME:$(git rev-parse --short HEAD)"
```

## 8) ตรวจผล

```bash
docker pull "$IMAGE_NAME:$IMAGE_TAG"
docker image ls "$IMAGE_NAME"
```

จากนั้นเข้า Docker Hub แล้วเช็กว่า repository มี image และ tag โผล่ครบ

## 9) ถ้าจะแก้โค้ดแล้ว push กลับ GitHub

ถ้าคุณแก้ไฟล์ใน repo บน Vast แล้วอยากส่งกลับ GitHub:

```bash
git status --short
git add Dockerfile comfyui-start.sh Wan2-2-Remix/install_wan22_remix_comfy.sh .github/workflows/docker-build-push.yml README.md
git commit -m "Bake models into image and update build flow"
git push -u origin main
```

## 10) คำสั่งล้างของที่กินพื้นที่

ถ้า build ใหญ่แล้ว disk เริ่มเต็ม:

```bash
docker builder prune -af
docker image prune -af
docker system df
```

ระวัง:

- `docker image prune -af` จะลบ image ที่ไม่ได้ถูกใช้อยู่
- ถ้าเพิ่ง build เสร็จแล้วจะ push ต่อ อย่า prune ก่อน push

## 11) ถ้าบิลด์ไม่ผ่าน

เช็กตามลำดับนี้:

1. `gh auth status`
2. `docker version`
3. `docker info`
4. `docker buildx version`
5. token ที่ใช้ดาวน์โหลดโมเดลยังใช้งานได้
6. พื้นที่ดิสก์ใน Vast ยังพอไหม

คำสั่งดูพื้นที่:

```bash
df -h
docker system df
```

## 12) สรุป flow สั้นมาก

```bash
sudo apt update
sudo apt install -y git gh docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
gh auth login
gh auth setup-git
git clone https://github.com/Nozukakung/comfyui-docker.git
cd comfyui-docker
printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
DOCKER_BUILDKIT=1 docker build \
  --secret id=hf_token,env=HF_TOKEN \
  --secret id=civitai_token,env=CIVITAI_TOKEN \
  -t "$DOCKERHUB_USERNAME/comfyui-docker:latest" .
docker push "$DOCKERHUB_USERNAME/comfyui-docker:latest"
```
