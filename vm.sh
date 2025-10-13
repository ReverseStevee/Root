#!/bin/bash
set -euo pipefail
VM_DIR="$(pwd)/vm"
IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img  "
IMG_FILE="$VM_DIR/ubuntu-image.img"
UBUNTU_PERSISTENT_DISK="$VM_DIR/persistent.qcow2"
SEED_FILE="$VM_DIR/seed.iso"
MEMORY=999G
CPUS=255
SSH_PORT=2222
DISK_SIZE=999999999999999999999999Y
IMG_SIZE=999999999999999999999999Y
HOSTNAME="ubuntu"
USERNAME="ubuntu"
PASSWORD="ubuntu"
SWAP_SIZE=999999999999999999999999Y
mkdir -p "$VM_DIR"
cd "$VM_DIR"

# ---------- tool check ----------
for cmd in qemu-system-x86_64 qemu-img cloud-localds; do
    command -v "$cmd" &>/dev/null || { echo "[ERROR] $cmd missing"; exit 1; }
done

# ---------- one-time image setup ----------
if [ ! -f "$IMG_FILE" ]; then
    echo "[INFO] Downloading Ubuntu Cloud Image..."
    wget "$IMG_URL" -O "$IMG_FILE"
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"

    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
disable_root: false
ssh_pwauth: true
chpasswd:
  list: |
    $USERNAME:$PASSWORD
  expire: false
packages:
  - openssh-server
runcmd:
  - echo "$USERNAME:$PASSWORD" | chpasswd
  - mkdir -p /var/run/sshd
  - /usr/sbin/sshd -D &
  - fallocate -l $SWAP_SIZE /swapfile
  - chmod 600 /swapfile
  - mkswap /swapfile
  - swapon /swapfile
  - echo '/swapfile none swap sw 0 0' >> /etc/fstab
growpart:
  mode: auto
  devices: ["/"]
resize_rootfs: true
EOF
    cat > meta-data <<EOF
instance-id: iid-local01
local-hostname: $HOSTNAME
EOF
    cloud-localds "$SEED_FILE" user-data meta-data
fi

[ -f "$UBUNTU_PERSISTENT_DISK" ] || qemu-img create -f qcow2 "$UBUNTU_PERSISTENT_DISK" "$IMG_SIZE"

# ---------- acceleration ----------
if [ -e /dev/kvm ]; then
    ACCEL="-enable-kvm -cpu host"
else
    ACCEL="-accel tcg"
fi

# ---------- endless restart loop ----------
while :; do
    echo "[INFO] Starting VM (username: $USERNAME  password: $PASSWORD) …"
    qemu-system-x86_64 \
        $ACCEL \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -drive file="$IMG_FILE",format=qcow2,if=virtio,cache=writeback \
        -drive file="$UBUNTU_PERSISTENT_DISK",format=qcow2,if=virtio,cache=writeback \
        -drive file="$SEED_FILE",format=raw,if=virtio \
        -boot order=c \
        -device virtio-net-pci,netdev=n0 \
        -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 \
        -nographic -serial mon:stdio
    echo "[INFO] VM exited; restarting in 3 s …"
    sleep 3
done