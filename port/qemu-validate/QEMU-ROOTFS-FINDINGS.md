# QEMU rootfs boot proof

Date: 2026-11-01
Image under test: `motorola-perry.img` (combined image), copied to a qcow2 overlay.
Host: `moto-pmos` Colima VM, aarch64 Ubuntu 24.04.

## Method

- Kernel: Ubuntu `6.8.0-117-generic` aarch64, decompressed from `/boot/vmlinuz-6.8.0-117-generic`.
- Initramfs: `mkinitramfs` for the same kernel; `VIRTIO_BLK`, `VIRTIO_PCI`, and `EXT4_FS` are built in.
- Disk: `qemu-img create -f qcow2 -F raw -b motorola-perry.img /tmp/perry-rootfs-test.qcow2`; the exported image was never modified.
- Command:

```sh
qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 2048 \
  -kernel /tmp/Image-qemu-test \
  -initrd /tmp/initrd-qemu-test.img \
  -append "root=/dev/vda2 rootfstype=ext4 rw rootwait console=ttyAMA0,115200 loglevel=7" \
  -drive file=/tmp/perry-rootfs-test.qcow2,format=qcow2,if=virtio \
  -display none -serial stdio -monitor none -no-reboot
```

The serial console was captured to `QEMU-ROOTFS-BOOT.log`. The overlay was mounted read-only after shutdown and `/var/log/gdm/greeter.log*` was copied to `QEMU-GDM-LOGS.txt`.

## What was proven

- The image’s ext4 root partition (`/dev/vda2`) passed `fsck` and mounted read-write.
- `OpenRC 0.63.2` started as the init system. This is an OpenRC image, not systemd; there is no `multi-user.target`.
- OpenRC reached its default runlevel and started `local`, `udev`, `dbus`, `polkit`, `NetworkManager`, `Bluetooth`, `CUPS`, `chronyd`, `System login manager`, `Display Manager`, `HKDM`, `q6voiced`, and the rest of the default service set.
- Hostname was set to `perry`.
- `/sbin/init` is BusyBox init; `/etc/runlevels/default` contains `gdm`, `local`, `networkmanager`, `dbus`, and the expected postmarketOS services.
- The rootfs is coherent enough to mount, initialize OpenRC, run udev/tmpfiles/sysusers, start D-Bus and policy services, and attempt the graphical login manager.

## Where it stopped, and why that is QEMU-only

- GDM’s greeter logs contain only `Unable to run X server`. The QEMU command had no GPU/DRM device, so there was no `/dev/dri`; GDM could not start X or a GNOME session.
- `msm-firmware-loader` could not find a bootdev/A-B slot directory; QEMU virt is not an MSM8917 eMMC.
- `rmtfs`/modem services failed with `Failed to create QRTR socket` and `No modem available`; QEMU virt has no Qualcomm QRTR/modem.
- `nftables` failed because the Ubuntu kernel lacks the nftables modules; this is not the postmarketOS kernel.
- `postmarketos-zram-swap` failed in QEMU; the image’s zram configuration needs a real block device.
- The serial console was flooded by `can't open /dev/ttyMSM0`, because QEMU has no MSM serial port. This is expected and does not indicate a rootfs defect.

## What was not proven

- GNOME Shell did not start; only GDM’s attempt was reached. There was no DRM device for a compositor.
- Display, touch, Wi-Fi, charging, suspend, audio, modem, and GPU have not run on MSM8917 hardware.
- The image has not been flashed or booted on the phone.
- This does not prove the Perry DTB or MSM drivers work; it proves the userspace/rootfs side is coherent.

## Verdict

The rootfs userspace boots and initializes correctly under a generic aarch64 kernel. The first failure is the expected absence of a DRM device for GDM, not a broken rootfs. A follow-up with `virtio-gpu` and llvmpipe started GNOME Shell; see `GNOME-QEMU-FINDINGS.md`. Further proof requires the physical phone or a virtual GPU/display stack; the latter would only test software rendering, not the E4 panel.
