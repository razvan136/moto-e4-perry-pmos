# GNOME Shell on QEMU — 2 GB, virtio-gpu, llvmpipe

Date: 2026-11-01
Image under test: `motorola-perry-single.img` (SSH-enabled, SHA-256 `ac9bdb...cfbfb`) in a disposable qcow2 overlay.
Kernel: Ubuntu `6.8.0-117-generic` aarch64; initramfs rebuilt with `virtio_gpu`.

## QEMU command

```sh
qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 2048 \
  -kernel /tmp/Image-qemu-test \
  -initrd /tmp/initrd-gnome.img \
  -append "root=/dev/vda rootfstype=ext4 rw rootwait console=ttyAMA0,115200 loglevel=6" \
  -drive file=/tmp/perry-gnome.qcow2,format=qcow2,if=virtio \
  -device virtio-gpu-pci,xres=1024,yres=768 \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-serial-pci \
  -chardev file,id=vc0,path=/tmp/gnome-virtio-serial-vnc.log \
  -device virtserialport,chardev=vc0,nr=1,name=pmos-console \
  -serial file:/tmp/gnome-serial-vnc.log \
  -display vnc=127.0.0.1:1 \
  -monitor unix:/tmp/gnome-monitor-vnc.sock,server,nowait -no-reboot
```

Software rendering was forced with `/etc/environment`:

```text
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
MESA_LOADER_DRIVER_OVERRIDE=swrast
```

GDM auto-login was enabled for `user`.

## What was proven

- OpenRC reached the default runlevel; `Display Manager`, `sshd`, `usb-signaller`, and `local` started.
- DRM exists: `/dev/dri/card0`, `/dev/dri/renderD128`, connector `card0-Virtual-1` is `connected`.
- GDM started a Wayland session and auto-logged in `user`:
  - `loginctl` session `c6`, seat0, tty7, active.
  - Environment: `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=GNOME`, `XDG_VTNR=7`, `WAYLAND_DISPLAY=wayland-1`.
- `gnome-shell` is running as `user`; `gnome-session`, `Xwayland`, AT-SPI, GNOME Shell Screencast, Notifications, ScreenSaver, and Calendar services are running.
- `QEMU-GNOME-SESSION.log` records mutter 48.0:
  - `Running GNOME Shell (using mutter 48.0) as a Wayland display server`
  - `Added device '/dev/dri/card0' (virtio_gpu) using atomic mode setting`
  - `Failed to initialize accelerated iGPU/dGPU framebuffer sharing: Not hardware accelerated`
  - `Created gbm renderer for '/dev/dri/card0'`
  - `Using Wayland display name 'wayland-1'`
  - `Xwayland glamor: GBM Wayland interfaces not available`
  - `Failed to initialize glamor, falling back to sw`
- SSH fallback worked over QEMU user networking: `ssh user@127.0.0.1 -p 2222` with password `1234`.

## Memory at 2 GB

`free -m` during the active user session:

| Metric | Value |
|---|---:|
| Total | 1960 MB |
| Used | 352 MB |
| Free | 1178 MB |
| Buff/cache | 429 MB |
| Available | 1524 MB |
| Swap | 0 MB |

Key RSS values:

| Process | RSS |
|---|---:|
| `gnome-shell` | 210 MB |
| `gnome-shell` screencast gjs | 89 MB |
| `Xwayland` | 48 MB |
| Notifications gjs | 29 MB |
| ScreenSaver gjs | 29 MB |
| Calendar server | 19 MB |
| `gnome-session-binary` | 16 MB |

GNOME Shell Mobile starts and remains running at 2 GB with software rendering. It did not OOM at idle. More app load will consume the remaining ~1.5 GB, so zram is still useful, but it is not required to start the shell.

## zram

`postmarketos-zram-swap` failed under QEMU because the Ubuntu host kernel has `CONFIG_ZRAM=m` and no `zram` module in the QEMU initramfs, so `/dev/zram0` did not exist.

The postmarketOS image kernel has `CONFIG_ZRAM=y` and zram backends built in. This is not an image defect; it remains a first-boot service to verify on the phone. It is not required for the idle GNOME Shell session.

## Scanout caveat

QEMU `screendump` captured the tty1 text console even while the GNOME Wayland session was active on tty7. The VNC scanout did not follow the GNOME VT. This is QEMU plumbing, not an image failure. The session evidence is the process list, `loginctl`, environment, and mutter session log. Attempts to switch the scanout with `chvt 7` did not change the captured framebuffer.

Files:

- `QEMU-GNOME-SERIAL.log` — OpenRC/GDM/serial log.
- `QEMU-GNOME-SESSION.log` — mutter/GNOME session log.
- `QEMU-SCANOUT-TTY1.png` — the misleading tty1 scanout, kept for audit.
- `QEMU-SCANOUT-INACTIVE.png` — earlier “Display output is not active” capture before the VNC client attached.
