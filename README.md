# moto-e4-perry-pmos

A postmarketOS device port for the Motorola Moto E4 (`perry`, MSM8917/PM8937) plus a
QEMU harness for validating a built pmOS image without hardware.

Everything here was produced by actually building a full GNOME Mobile image for this device and
verifying it, not by porting from a template.

## Status

| Item | State |
|---|---|
| Kernel package builds | yes — 7.1.3 fork tree, 315 modules, perry DTB |
| Device package builds | yes — `device-motorola-perry 0-r0` |
| GNOME Mobile image | yes — `postmarketos-ui-gnome-mobile` + `gnome-shell-mobile 48.0` |
| Rootfs userspace boots | yes — verified under QEMU; OpenRC reaches display-manager |
| GNOME Shell starts | yes — verified under QEMU with `virtio-gpu`; full Wayland session |
| Boots on a real phone | no — see below |

### Why it has not booted on hardware

The development unit was a Verizon XT1765PP, which is factory-locked
(`ro.boot.flash.locked=1`, `verifiedbootstate=green`) and is not eligible for Motorola's
bootloader unlock. `lk2nd` and the rootfs load into the `boot`/`userdata` partitions only on an
unlocked unit, and verified boot rejects an unsigned boot image regardless. This is a policy gate
on that specific carrier variant, not a defect in the port.

On any unlockable `perry`, the artifacts here are ready to flash.

## What is in here

```
port/
  pmaports/                 pmaports packages (device, kernel, firmware, lean tweaks)
  qemu-validate/            harness + real findings from booting the built image
```

- `port/pmaports/linux-motorola-perry` — kernel package with the perry DTS, the generated
  Ofilm panel driver, a verified aarch64 config, and the patch that enables MDSS.
- `port/pmaports/device-motorola-perry` — `deviceinfo`, initramfs module list, kernel cmdline.
- `port/pmaports/firmware-motorola-perry` — packaging recipe only. No vendor blobs are
  distributed here; the recipe builds the tarball from a stock ROM you supply.
- `port/qemu-validate` — scripts to boot a built pmOS rootfs under QEMU, including a
  `virtio-gpu` setup that gets a real GNOME Shell Wayland session running headless.

## Highlights worth reusing

- The `16 MiB` boot partition trap. Perry's `boot` partition is only 16 MiB, and `lk2nd`
  uses *fs-boot*: the kernel, initramfs and DTB live in `/boot` inside the rootfs, read from
  the `userdata`-flashed image. Flashing the split boot image or a combined image to `boot` does
  not work. Use `pmbootstrap install --single-partition` and flash that to `userdata`.
- A visible fallback console. The DTB carries a `simple-framebuffer` at `0x90001000` as
  `stdout-path`, with `console=tty0` plus `earlycon=msm_serial_dm,0x78b0000`. If the DSI panel
  driver fails to probe, you get text on screen instead of a silent black device.
- GNOME on 2 GB is viable. Measured: `gnome-shell` 210 MB RSS, total used 352 MB of 1960 MB
  with llvmpipe software rendering. It does not OOM at idle.

## Using it

```sh
# in a pmbootstrap environment
cp -r port/pmaports/* <pmaports>/device/testing/
pmbootstrap init      # vendor: motorola, codename: perry
pmbootstrap install --single-partition --ui gnome-mobile
pmbootstrap export
```

See `port/pmaports/README.md` for the details, including the firmware tarball step.

## Provenance

This port builds on other people's work:

- [msm89x7-mainline/linux](https://github.com/msm89x7-mainline/linux) — the kernel fork this
  package tracks.
- The upstream perry device-tree series (`arm64: dts: qcom: add initial Motorola Moto E4 (perry)
  support`, July 2026) — the upstream-first subset that defers display.
- [msm89x7-mainline/linux-panel-drivers](https://github.com/msm89x7-mainline/linux-panel-drivers)
  — the Ofilm panel driver lineage.
- [lk2nd](https://github.com/msm8916-mainline/lk2nd) — its perry entry is already upstream.

## Licensing

Repo contents are MIT (see `LICENSE`). The kernel patches under
`port/pmaports/linux-motorola-perry/*.patch` are GPL-2.0-only, as kernel code must be.
No proprietary firmware is redistributed.
