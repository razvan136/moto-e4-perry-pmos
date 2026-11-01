# Port

postmarketOS device port for the Motorola Moto E4 (`perry`, MSM8917 / PM8937, 2 GB RAM).

- `pmaports/` — the packages, drop-in ready for `pmaports/device/testing/`.
- `qemu-validate/` — prove a built image's userspace and desktop actually start, on any machine,
  before touching hardware.

## Target device

| | |
|---|---|
| Codename | `motorola-perry` |
| SoC | Qualcomm MSM8917 / PM8937 |
| Arch | aarch64 |
| RAM | 2 GB |
| Panel | Ofilm 499v0 (DSI) |
| Touch | Synaptics RMI4 |
| Bootloader | lk2nd-msm8952 (fs-boot from the rootfs `/boot`) |

Requires an **unlocked** bootloader. See the top-level README for why a locked unit cannot boot this.
