#!/bin/bash
# Fetch everything the PXE flow needs from the CentOS mirrors (~1.6 GB per stream).
# Resumable; re-run after interruptions. Usage: ./fetch-boot-files.sh [9] [10]
set -euo pipefail
cd "$(dirname "$0")"

fetch() { # fetch <stream>
  local v="$1" base dest
  base="https://mirror.stream.centos.org/${v}-stream/BaseOS/x86_64/os"
  dest="http/stream${v}"
  for p in .treeinfo images/pxeboot/vmlinuz images/pxeboot/initrd.img images/install.img EFI/BOOT/grubx64.efi; do
    mkdir -p "${dest}/$(dirname "$p")"
    until curl -sSfL --retry 10 --retry-delay 5 -C - -o "${dest}/${p}" "${base}/${p}"; do
      echo "retrying ${p}" >&2; sleep 5
    done
    echo "done stream${v}/${p}"
  done
  # Boot-file copies for both UEFI paths (hardlinks; grub.cfg references vmlinuz<v>/initrd<v>.img).
  # TFTP tree serves UEFI PXE; the same files at the HTTP root serve UEFI HTTP Boot —
  # grub loaded from http://.../grubx64.efi resolves grub.cfg and kernels relative to that URL.
  mkdir -p tftp
  for d in tftp http; do
    ln -f "${dest}/images/pxeboot/vmlinuz"    "${d}/vmlinuz${v}"
    ln -f "${dest}/images/pxeboot/initrd.img" "${d}/initrd${v}.img"
    ln -f "${dest}/EFI/BOOT/grubx64.efi"      "${d}/grubx64.efi"
  done
}

for v in "${@:-9 10}"; do fetch "$v"; done

# Stage the boot config and kickstarts next to the payloads
cp -f grub.cfg tftp/grub.cfg
cp -f grub.cfg http/grub.cfg
cp -f boot.ipxe http/boot.ipxe
mkdir -p http/ks && cp -f ../kickstarts/*.ks http/ks/
echo "Serve ./http on :8000 (python3 -m http.server 8000 --directory http) and point dnsmasq's tftp-root at ./tftp"
