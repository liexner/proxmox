#!/bin/bash

export storage=local
STORAGE="${1:-local}"

# Only download if missing
IMG="ubuntu-24.04-server-cloudimg-amd64.img"
if [[ ! -f "$IMG" ]]; then
  echo "Downloading $IMG…"
  wget "https://cloud-images.ubuntu.com/releases/24.04/release/$IMG"
else
  echo "$IMG already present, skipping download."
fi

create_template() {
  local id="$1" name="$2" img="$3" pool="$4"
  echo "Creating template '$name' (VMID $id) on storage '$pool'"
  qm create "$id" --name "$name" --ostype l26
  qm set "$id" --net0 virtio,bridge=vmbr0 \
                --serial0 socket --vga serial0 \
                --memory 1024 --cores 1 --cpu host \
                --scsi0 "${pool}:0,import-from=$(pwd)/$img",discard=on \
                --boot order=scsi0 --scsihw virtio-scsi-single \
                --agent enabled=1,fstrim_cloned_disks=1 \
                --ide2 "${pool}":cloudinit \
                --ipconfig0 "ip6=auto,ip=dhcp"
  qm disk resize "$id" scsi0 8G || true
  qm template "$id"
  qm set "$id" --cicustom "vendor=${pool}:snippets/vendor.yaml"
}

mkdir -p /var/lib/vz/snippets
cat << EOF | tee /var/lib/vz/snippets/vendor.yaml
#cloud-config


apt:
  sources:
    docker.list:
      source: deb [arch=amd64] https://download.docker.com/linux/ubuntu noble stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - ssh-import-id
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-compose-plugin

groups:
  - docker

system_info:
  default_user:
    groups: [docker]

runcmd:
  - systemctl enable --now qemu-guest-agent
  - systemctl enable --now docker
EOF


create_template 912 "temp-ubuntu-24-04" "$IMG" "$STORAGE"



