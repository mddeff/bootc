# bootc

CI-built [bootc](https://bootc-dev.github.io/bootc/) OS images (CentOS Stream 9 & 10) plus the
kickstarts and PXE scaffolding to install them over the network with Anaconda's
`ostreecontainer` — no `%packages`, no RPM repos at install time. The OS *is* the container image;
day-2 updates are `bootc upgrade`.

## Images

| Image | Base | Tags |
|---|---|---|
| `ghcr.io/mddeff/bootc/c9s-base` | `quay.io/centos-bootc/centos-bootc:stream9` | `latest` (moving), `YYYYMMDD.N` (immutable) |
| `ghcr.io/mddeff/bootc/c10s-base` | `quay.io/centos-bootc/centos-bootc:stream10` | same |

Naming scheme (as flavors land): `<distro>-<flavor>[-gpu][-cis|stig]`, content dimensions in
the **name**, only version/channel in the **tag** — a tag must always point at "the same thing, newer."
Hosts follow `:latest`; promoting a build = re-pointing `:latest` at a tested date tag.


## No PXE? Boot ISOs

CI publishes `c9s-base-boot.iso` / `c10s-base-boot.iso` on the rolling
[boot-isos release](https://github.com/mddeff/bootc/releases/tag/boot-isos): the upstream netinstall
boot.iso with `inst.ks=` pointed at this repo's kickstart on `raw.githubusercontent.com`. Write it to
USB / mount it in a BMC, boot, done. The ISO contains **no OS image and no kickstart** — kickstart
comes from this repo at install time and the OS from GHCR, so a kickstart or image change needs no
new ISO (but the machine needs internet, and a kickstart edit on `main` changes what existing ISOs do).

## Network install: what you need

Four files per stream from the mirror, plus this repo's config. `pxe/fetch-boot-files.sh` grabs it all (~1.6 GB/stream, resumable):

| What | Where it goes | Served via |
|---|---|---|
| `images/pxeboot/vmlinuz`, `initrd.img` | `pxe/tftp/` + `pxe/http/stream<v>/` | TFTP (UEFI) / HTTP (BIOS-iPXE) |
| `images/install.img` + `.treeinfo` (Anaconda stage2) | `pxe/http/stream<v>/` | HTTP |
| `EFI/BOOT/grubx64.efi` | `pxe/tftp/` | TFTP |
| `kickstarts/*.ks`, `boot.ipxe`, `grub.cfg` | staged by the script | HTTP / TFTP |

### Quickstart

```bash
./pxe/fetch-boot-files.sh                  # or `9` / `10` for one stream
# edit pxe/dnsmasq.conf: interface, ranges, tftp-root, server IP
sudo dnsmasq --keep-in-foreground --conf-file=pxe/dnsmasq.conf
python3 -m http.server 8000 --bind <server-ip> --directory pxe/http
# PXE-boot a blank machine on that segment; grub menu (UEFI) or boot.ipxe (BIOS) takes it from there
```

The dnsmasq config runs DHCP+TFTP only (`port=0`) so it coexists with an existing resolver, and
detects the client type:

| Client | How it's detected | What it gets |
|---|---|---|
| UEFI HTTP Boot | vendor class `HTTPClient` (arch 16) | `grubx64.efi` + `grub.cfg` + kernels, all over HTTP — no TFTP |
| UEFI PXE | client-arch 7 | `grubx64.efi` → `grub.cfg` over TFTP (fallback for older firmware) |
| BIOS + iPXE NIC ROM | iPXE user class (option 175) | `boot.ipxe` over HTTP (qemu virtio) |

No pxelinux anywhere. Prefer enabling UEFI HTTP Boot in firmware where available — it's the
fastest path; TFTP remains for firmware that only speaks PXE.

## Kickstarts

`kickstarts/c9s-base.ks` / `c10s-base.ks`:

- `ostreecontainer --url=ghcr.io/mddeff/bootc/<name>:latest` — deploys the OCI image; the installed
  host's origin is this ref, so `bootc upgrade` pulls from GHCR afterward.
- **STIG-compliant partitioning** on LVM/xfs: separate `/boot`, `/home`, `/tmp`, `/var/tmp`, `/var`,
  `/var/log`, `/var/log/audit` with `nodev,nosuid` — **`noexec` deliberately omitted** (re-add
  per-mount if your assessor insists). `reqpart` makes the same file work on UEFI *and* BIOS.
- `/var` is where all mutable state lives on a bootc host (container images included) — resize to fit.
- **Change `rootpw` and add your `sshkey` line before using.**

Day-2, on the installed host:

```bash
bootc status            # what's booted / staged / rollback
bootc upgrade           # pull + stage whatever :latest points at now; applies on reboot
bootc switch ghcr.io/mddeff/bootc/c9s-base:20261113.42   # pin / move to another ref
bootc rollback          # boot the previous deployment (its /etc snapshot included)
```

## Repo layout

```
images/<name>/Containerfile    one per published image; CI matrix builds all of them
.github/workflows/build.yml    build + push on main, PR builds don't push, weekly rebuild cron
kickstarts/*.ks                one per image
pxe/                           dnsmasq.conf, grub.cfg, boot.ipxe, fetch-boot-files.sh
```

See `AGENTS.md` for conventions, verified behaviors, and the gotcha list.
