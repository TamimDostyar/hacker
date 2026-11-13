#!/usr/bin/env bash
# Tamim Dostyar
# usage: sudo ./boot_ova.sh file.ova|file.ovf [vm-name]

set -euo pipefail

[ "$EUID" -eq 0 ] || { echo "run as root"; exit 1; }

OVA=${1:?usage: $0 file.ova|file.ovf [vm-name]}
NAME=${2:-$(basename "$OVA" | sed 's/\.[oO][vV][aAfF]$//' | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')}
IMG=/var/lib/libvirt/images

virsh dominfo "$NAME" &>/dev/null && { echo "vm '$NAME' already exists"; exit 1; }
grep -qx default <<<"$(virsh net-list --name)" || virsh net-start default

case "$OVA" in
  *.ova|*.OVA)
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    echo "==> extracting $OVA"
    tar -xf "$OVA" -C "$WORK"
    ;;
  *.ovf|*.OVF)
    WORK=$(dirname "$(realpath "$OVA")")
    ;;
  *) echo "expected .ova or .ovf"; exit 1 ;;
esac

mapfile -t VMDKS < <(find "$WORK" -maxdepth 1 -iname '*.vmdk' | sort)
[ ${#VMDKS[@]} -gt 0 ] || { echo "no .vmdk found in $WORK"; exit 1; }

DISK_ARGS=()
i=0
for v in "${VMDKS[@]}"; do
  out="$IMG/$NAME-d$i.qcow2"
  [ -e "$out" ] && { echo "$out exists, refusing to overwrite"; exit 1; }
  echo "==> converting $(basename "$v") -> $out"
  qemu-img convert -p -f vmdk -O qcow2 "$v" "$out"
  DISK_ARGS+=(--disk "$out,format=qcow2,bus=sata")
  i=$((i+1))
done

echo "==> creating vm: $NAME"
virt-install --name "$NAME" --memory 2048 --vcpus 2 \
  "${DISK_ARGS[@]}" \
  --import --osinfo detect=on,require=off \
  --network network=default,model=e1000 \
  --noautoconsole
