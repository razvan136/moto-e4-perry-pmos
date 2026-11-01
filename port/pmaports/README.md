# pmaports packages for Motorola Moto E4 (`perry`)

Built and verified against pmaports `edge`. These are drop-in for `pmaports/device/testing/`.

| Package | Purpose |
|---|---|
| `linux-motorola-perry` | Kernel 7.1.3 fork tree, perry DTS, Ofilm panel driver, aarch64 config |
| `device-motorola-perry` | `deviceinfo`, initramfs modules, kernel cmdline, dependencies |
| `firmware-motorola-perry` | Stock-derived firmware. **Blobs are not distributed here** — see its README |
| `postmarketos-perry-lean` | Trims services that do not earn their RAM on a 2 GB phone |

## Install into a pmaports checkout

```sh
cp -r device-motorola-perry linux-motorola-perry firmware-motorola-perry postmarketos-perry-lean \
    <pmaports>/device/testing/
```

Then in `pmbootstrap`:

```sh
pmbootstrap init            # vendor: motorola, codename: perry
pmbootstrap build linux-motorola-perry --lax
pmbootstrap install --single-partition --ui gnome-mobile
pmbootstrap export
```

## `--single-partition` matters

Perry's `boot` partition is only **16 MiB**, and `lk2nd` uses *fs-boot*: it reads
`/boot/extlinux/extlinux.conf`, the kernel, initramfs and DTB **from inside the rootfs**. So the
flashable artifact is a single ext4 image flashed to **`userdata`**, not a kernel image flashed to
`boot`.

```sh
fastboot flash boot lk2nd.img                    # 16 MiB boot partition
fastboot flash userdata motorola-perry.img       # single-partition rootfs, /boot included
```

Do **not** flash a split/combined image to `boot`. It will not work and can wedge the boot flow.

## Kernel patches

`0001-perry-support.patch` adds the perry device trees and the generated Ofilm panel driver.
`0002-perry-enable-framebuffer.patch` flips MDSS from `disabled` to `okay` so the panel probes.

Both apply cleanly to the pinned fork tag. `config-motorola-perry.aarch64` is the exact config the
built image used, including `CONFIG_ZRAM=y` and the framebuffer/console options.

## Console fallback

`kernel-cmdline.conf` deliberately sets a visible fallback console:

```
console=tty0
console=ttyMSM0,115200
earlycon=msm_serial_dm,0x78b0000
panic=0
oops=panic
```

Combined with the `simple-framebuffer` node in the perry DTS, a failed panel probe gives you text
on screen rather than a silently black phone. This is the single most useful thing for first boot
on a device whose panel driver has never run on hardware.

## Upstream direction

A `perry` device-tree series landed upstream in July 2026, but it deliberately **defers** DSI/MDSS,
audio, charger and remoteprocs. The display delta here is the interesting candidate for upstream,
once the Ofilm panel driver is reviewed.
