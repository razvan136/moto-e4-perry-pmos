# firmware-motorola-perry — recipe only, no blobs

This package installs **stock-derived proprietary firmware** into `/usr/lib/firmware`.

**No firmware is distributed in this repository.** The files are Motorola's proprietary blobs;
they cannot be redistributed. This package therefore ships the *packaging recipe* and the manifest
of what is needed, and expects you to produce the tarball from a stock ROM you obtained for your
own device.

## Why this package exists at all

postmarketOS ships `msm-firmware-loader`, which mounts the device's own stock partitions at boot
and symlinks the vendor firmware out of them. That is the preferred mechanism and
`device-motorola-perry` depends on it.

This package is for the cases that loader does not cover — specifically the modem/ADSP/Venus
images that are not present in the partitions the loader looks at on every device. It is optional:
the image builds and the userspace boots without it. Treat it as an enhancement, not a hard
requirement.

## Producing the tarball

1. Extract your own stock ROM, or pull the partitions from your own device.
2. Collect the 55 files listed in `firmware-manifest.json`, each verified by SHA-256. The
   `firmware_request_name` field is the name the kernel will request; the `source` field tells you
   where it lives in the stock image.
3. Run:

```sh
./make-firmware-tarball.sh /path/to/payload-dir
```

The script verifies every file against the manifest, refuses on a hash mismatch, and writes
`firmware-motorola-perry.tar.gz` plus the `sha512sums` line to paste into `APKBUILD`.

## What is in the manifest

55 files: `adsp.b10`, `venus.b03/b04`, and the `modem.b11`-`b21` family. Each entry records the
stock source path, the firmware request name, and the expected SHA-256, so extracting the wrong
ROM version fails loudly instead of silently shipping a mismatched modem image.

## Licensing

`license="proprietary"` is set in the APKBUILD because the contents are Motorola's. Distributing a
built package of this outside your own use is your problem, not the repository's — that is exactly
why the blob is not here.
