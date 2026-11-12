#Tamim Dostyar
#!/usr/bin/env bash
# usage: sudo ./ova-boot.sh file.ova [vm-name]

set -euo pipefail

OVA=${1:?usage: $0 file.ova [vm-name]}
NAME=${2:-$(basename "$OVA" .ova | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')}
IMG=/var/lib/libvirt/images

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> extracting $OVA"
tar -xf "$OVA" -C "$WORK"

mapfile -t VMDKS < <(find "$WORK" -iname '*.vmdk' | sort)
[ ${#VMDKS[@]} -gt 0 ] || { echo "no .vmdk in $OVA"; exit 1; }

DISK_ARGS=()
i=0
for v in "${VMDKS[@]}"; do
  out="$IMG/$NAME-d$i.qcow2"
  echo "==> converting $(basename "$v") -> $out"
  sudo qemu-img convert -f vmdk -O qcow2 "$v" "$out"
  DISK_ARGS+=(--disk "$out,format=qcow2")
  i=$((i+1))
done

echo "==> creating vm: $NAME"
sudo virt-install --name "$NAME" --memory 2048 --vcpus 2 \
  "${DISK_ARGS[@]}" \
  --import --osinfo detect=on,require=off --network default
