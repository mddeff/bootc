# c10s-base.ks — deploy ghcr.io/mddeff/bootc/c10s-base via Anaconda ostreecontainer
#
# Boot with:
#   inst.stage2=http://<server>/stream10  inst.ks=http://<server>/ks/c10s-base.ks
#
# NOTE: no %packages section — it cannot be combined with ostreecontainer.
ostreecontainer --url=ghcr.io/mddeff/bootc/c10s-base:latest --transport=registry --no-signature-verification

text
lang en_US.UTF-8
keyboard us
timezone UTC --utc
network --bootproto=dhcp --activate

# --- storage: STIG-compliant partitioning (minus noexec), LVM on xfs ---
# Separate /home /tmp /var/tmp /var /var/log /var/log/audit with nodev,nosuid
# per the RHEL 10 STIG. noexec intentionally omitted (breaks too much tooling;
# add it back per-mount if your assessor requires it).
zerombr
clearpart --all --initlabel --disklabel=gpt
reqpart                       # biosboot on BIOS, /boot/efi on UEFI (verified both ways)
part /boot --fstype=xfs --size=2048 --fsoptions="nodev,nosuid"
part pv.01 --grow --size=1
volgroup vg0 pv.01
logvol /              --fstype=xfs --name=root        --vgname=vg0 --size=10240 --grow
logvol /home          --fstype=xfs --name=home        --vgname=vg0 --size=2048  --fsoptions="nodev,nosuid"
logvol /tmp           --fstype=xfs --name=tmp         --vgname=vg0 --size=2048  --fsoptions="nodev,nosuid"
logvol /var/tmp       --fstype=xfs --name=vartmp      --vgname=vg0 --size=2048  --fsoptions="nodev,nosuid"
# /var holds ALL mutable state on a bootc host (container images, databases, …). Size generously.
logvol /var           --fstype=xfs --name=var         --vgname=vg0 --size=16384 --fsoptions="nodev"
logvol /var/log       --fstype=xfs --name=varlog      --vgname=vg0 --size=4096  --fsoptions="nodev,nosuid"
logvol /var/log/audit --fstype=xfs --name=varlogaudit --vgname=vg0 --size=10240 --fsoptions="nodev,nosuid"
logvol swap           --name=swap --vgname=vg0 --size=4096

bootloader --append="audit=1 audit_backlog_limit=8192"

# --- access: CHANGE THESE before using anywhere real ---
rootpw --plaintext changeme-bootc
# sshkey --username=root "ssh-ed25519 AAAA... you@host"

reboot

%post --erroronfail --log=/root/ks-post.log
# PXE/kickstart installs have no cloud-init datasource; disable it outright.
# (qcow2/cloud builds of the same image skip this kickstart and keep cloud-init live.)
touch /etc/cloud/cloud-init.disabled
# %post writes into the deployed root's /etc (verified). If the registry is private,
# drop a pull secret here so `bootc upgrade` works after first boot:
#   install -D -m0600 /dev/stdin /etc/ostree/auth.json <<'AUTHEOF'
#   {"auths":{"ghcr.io":{"auth":"<base64 user:PAT>"}}}
#   AUTHEOF
true
%end
