#!/bin/bash

STORAGE="${1:-local-lvm}"

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

  qm destroy "$id" --purge || echo "VM $id doesn't exist or already cleaned"
  echo "Creating template '$name' (VMID $id) on storage '$pool'"
    qm create "$id" --name "$name" --ostype l26
    qm set "$id" --net0 virtio,bridge=vmbr0 \
                --serial0 socket --vga serial0 \
                --memory 2048 --cores 2 --cpu host \
                --scsihw virtio-scsi-single \
                --agent enabled=1,fstrim_cloned_disks=1 \
                --ide2 "${pool}:cloudinit" \
                --ipconfig0 "ip6=auto,ip=dhcp"

    # import the disk image
    qm importdisk "$id" "$img" "$pool"
    qm set "$id" --scsi0 "$pool:vm-$id-disk-0",discard=on
    
    # Set boot order AFTER the disk is attached
    qm set "$id" --boot order=scsi0

    # resize
    qm disk resize "$id" scsi0 50G || true

    # mark as template
    qm template "$id"

    # set cicustom from local snippets
    qm set "$id" --cicustom "vendor=local:snippets/vendor.yaml"

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

# Fix filesystem labeling and disable problematic services
runcmd:
  - systemctl enable --now qemu-guest-agent
  - systemctl enable --now docker
  - systemctl disable mdadm
  - systemctl disable mdmonitor
  - update-initramfs -u
EOF


create_template 912 "temp-ubuntu-24-04" "$IMG" "$STORAGE"
