# AGENTS.md

Guidance for AI agents (and humans) working in this repo. `CLAUDE.md` is a symlink here.

## What this repo is

CI pipeline producing bootc OS images (`ghcr.io/mddeff/bootc/<name>`) from CentOS Stream bases,
plus kickstarts/PXE config to deploy them via Anaconda `ostreecontainer`. Images are the unit of
OS change: hosts track a tag with `bootc upgrade`; nothing is yum-installed on hosts.

## Conventions (don't break these)

- **Naming:** content dimensions in the image *name* (`<distro>-<flavor>[-gpu][-cis|stig]`,
  fixed suffix order), only version/channel in *tags*. `:latest` is a moving tag; `YYYYMMDD.N` tags
  are immutable. Never make one tag mean different contents over time — bootc treats a moved tag as
  an upgrade, so a tag that changes meaning silently converts hosts.
- **One directory per image** under `images/<name>/Containerfile`; add new images to the matrix in
  `.github/workflows/build.yml`. Keep `RUN bootc container lint` as the last layer.
- **Layer order for future flavors:** distro base → flavor → gpu → hardening. Hardening is
  LAST (profile must see the final package set). GPU/kmod layers must match the image kernel —
  no DKMS at runtime (read-only `/usr`).
- **Nothing in `/var` or `/usr/local` in images.** Image `/var` content ships at *install time only*;
  `bootc upgrade` never touches it. Shippable state goes in `/usr/share/...` + tmpfiles.d. RPMs only
  (no curl|sh installers — they write to `/usr/local`).
- **Kernel args** go in `/usr/lib/bootc/kargs.d/*.toml` so they travel with the image (verified:
  applied at install time too, not just on upgrade).
- Kickstarts: `ostreecontainer` + `%packages` is **invalid** — never add a `%packages` section.
  Per-host config belongs in `%post` (verified: lands in the deployed `/etc`) or first-boot units.

## Verified behaviors (tested 2026-11 in a libvirt sandbox, CentOS Stream 9)

- Anaconda `ostreecontainer --no-signature-verification --transport=registry` works from kickstart;
  explicit `part`/`logvol` and `reqpart` both work; same kickstart installs on UEFI and BIOS.
- All three boot paths in `pxe/dnsmasq.conf` verified: UEFI PXE (grub/TFTP), BIOS iPXE (HTTP),
  and **UEFI HTTP Boot** (vendor class `HTTPClient` arch 16 → grub+cfg+kernels entirely over HTTP;
  the option-60 echo is required). Firmware falls through PXE→HTTP when PXE gets no bootfile.
- The STIG LVM layout in `kickstarts/*.ks` installs and boots: logvols land with `nodev,nosuid`,
  the `/home` logvol is mounted at `/var/home` (ostree symlinks /home there), `audit=1` kargs
  active. Fixed logvols total ~41G — disks need ≥50G or the install fails in partitioning.
- `%pre`-written `/etc/containers/registries.conf.d/` makes an insecure/private registry usable by
  the installer; `%post` writes persist into the deployed host.
- `bootc upgrade --check` / `upgrade` / `rollback` + kargs.d all verified end-to-end.
- Docker-daemon round-trips (`skopeo copy ... docker-daemon:`) change layer digests → full re-pull
  on hosts. Push straight from the build to the registry to preserve layer reuse.

## Known constraints / landmines

- STIG/CIS: official SSG content covers RHEL/CS (profiles identical cs9↔rhel9); Fedora has no STIG
  and only DRAFT CIS. Hardened variants stay on the EL side. `oscap-im` (openscap-utils) is the
  build-time remediation tool; it needs the *image's* repos reachable during build.
- Hardened vs non-hardened is a **name** dimension, never a tag flip: partitioning and FIPS can't be
  retrofitted by `bootc switch`, and `/etc` three-way merge keeps locally-modified files (silent
  compliance drift). Treat plain→hardened as reinstall.
- Partitioning lives in kickstarts, not images. The STIG layout here omits `noexec` on purpose.
- RKE2 (future k8s flavor): RPM install only, pin the version, k8s minor goes in the image *name*
  (`-k8s131`), disable `bootc-fetch-apply-updates.timer`, upgrades orchestrated via
  cordon/drain (system-upgrade-controller) not node-local timers.

## Working here

- Build locally: `docker build -f images/c9s-base/Containerfile images/c9s-base`
- CI pushes only from `main`; PRs build without pushing. Weekly cron rebuilds pick up upstream base updates.
- Test installs: see README quickstart; a libvirt NAT network with no DHCP + the pxe/ configs is
  enough (that's exactly how the verified-behaviors list above was produced).
- Commits/PRs: owner reviews before anything is pushed; don't push or re-point `:latest` without
  being asked.
