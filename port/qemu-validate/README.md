# qemu-validate

Prove that a postmarketOS image you just built **actually boots** — userspace, display manager,
and optionally a full GNOME Shell Wayland session — before you risk flashing hardware you may not
be able to recover.

This was written to validate a Moto E4 GNOME Mobile image, but it is device-agnostic: it only needs
an aarch64 rootfs image and a host kernel. See the two findings documents for exactly what it proved
on that image.

## Requirements

- `qemu-system-aarch64` (7.0+), `qemu-img`
- an **aarch64** host kernel and matching initramfs with `virtio_blk`, `virtio_pci`, `ext4` built in
  (any Debian/Ubuntu `linux-image-generic` arm64 works)
- for the GNOME variant: `virtio_gpu` available to the initramfs, and root to edit the overlay

Because it needs an arm64 host kernel, run it on an arm64 Linux machine, an arm64 VM, or inside
`colima`/Docker on Apple Silicon. On macOS directly, QEMU needs an explicit arm64 kernel that macOS
does not provide.

## Quick start

```sh
# 1. Does the userspace come up at all?
./boot-rootfs.sh path/to/motorola-perry.img

# 2. Does the desktop actually start?
./boot-gnome-headless.sh path/to/motorola-perry.img
```

Both scripts copy-on-write the image into a disposable qcow2 overlay and **never modify the source
image** — the overlay is deleted on exit.

## What to look for

For a `pmaports install --single-partition` image the root filesystem is the only partition, so
`root=/dev/vda`. A split image (boot + root) needs `root=/dev/vda2` — pass `-r /dev/vda2`.

A successful userspace boot looks like:

```
OpenRC ... starting
 * Starting local ...
 * Starting Display Manager ...
```

Then, for GNOME, check the session evidence rather than the framebuffer:

```sh
ssh user@127.0.0.1 -p 2222      # if the image has sshd
loginctl list-sessions
echo $XDG_SESSION_TYPE          # wayland
```

## The scanout caveat (read this before concluding it failed)

QEMU `screendump` and the VNC scanout **do not follow the GNOME VT** — they keep showing the tty1
text console while a Wayland session is live on tty7. `chvt 7` does not help. If you judge success
by screenshot you will wrongly conclude GNOME never started. Judge by `loginctl`, the process list,
the session environment, and the mutter log at `/var/log/gdm/` instead. Real measured evidence:

```
gnome-shell running as user, mutter 48.0, Wayland display wayland-1
/dev/dri/card0 (virtio_gpu) using atomic mode setting
gnome-shell RSS 210 MB; total used 352 MB of 1960 MB with llvmpipe
```

## Known-benign failures on QEMU

These appear in logs and are **not** image defects — they are artifacts of QEMU not being the real
hardware:

| Symptom | Cause |
|---|---|
| `can't open /dev/ttyMSM0` flood | QEMU has no MSM serial port |
| `msm-firmware-loader` cannot find bootdev | QEMU virt is not an eMMC with A/B slots |
| `rmtfs` / modem: `Failed to create QRTR socket` | no Qualcomm QRTR or modem |
| `postmarketos-zram-swap` fails | `/dev/zram0` missing in the host initramfs |
| `nftables` module missing | host kernel config, not the pmOS kernel |

## Files

- `boot-rootfs.sh` — minimal boot, serial console only. Fastest "does userspace work" check.
- `boot-gnome-headless.sh` — adds `virtio-gpu`, VNC, virtio-serial and SSH port-forward, and
  force-enables llvmpipe + GDM autologin so a session starts without a physical display.
- `QEMU-ROOTFS-FINDINGS.md`, `GNOME-QEMU-FINDINGS.md` — the real observed results.
