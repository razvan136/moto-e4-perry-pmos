#!/bin/sh
# Boot a postmarketOS aarch64 rootfs under QEMU with a virtual GPU and get a REAL
# GNOME Shell Wayland session running headless.
#
# Why this is nontrivial: GNOME will not start without a DRM device. QEMU virt gives you one only
# with -device virtio-gpu-pci. Software rendering then has to be forced, and GDM needs a session to
# attach to an active output before it will start a compositor.
#
# The source image is never modified. A disposable qcow2 overlay is patched and removed on exit.
#
# Usage: ./boot-gnome-headless.sh <image.img> [-r rootdev] [-m memory_mb] [-u user] [-p password]

set -eu

IMAGE=""
ROOTDEV="/dev/vda"
MEM=2048
GUSER="user"
GPASS="1234"
SSH_PORT=2222
VNC_DISPLAY=1

usage() {
	echo "usage: $0 <image.img> [-r /dev/vdaN] [-m MB] [-u user] [-p pass]" >&2
	exit 1
}

[ $# -ge 1 ] || usage
IMAGE="$1"; shift
while [ $# -gt 0 ]; do
	case "$1" in
		-r) ROOTDEV="$2"; shift 2 ;;
		-m) MEM="$2"; shift 2 ;;
		-u) GUSER="$2"; shift 2 ;;
		-p) GPASS="$2"; shift 2 ;;
		*) usage ;;
	esac
done

[ -f "$IMAGE" ] || { echo "error: no such image: $IMAGE" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "error: needs root to patch the overlay (mounts it)" >&2; exit 1; }

for t in qemu-system-aarch64 qemu-img; do
	command -v "$t" >/dev/null 2>&1 || { echo "error: missing $t" >&2; exit 1; }
done

KERNEL="/boot/vmlinuz-$(uname -r)"
[ -f "$KERNEL" ] || { echo "error: host kernel $KERNEL missing" >&2; exit 1; }
INITRD=""
for cand in "/boot/initrd.img-$(uname -r)" "/boot/initramfs-$(uname -r).img"; do
	[ -f "$cand" ] && { INITRD="$cand"; break; }
done

WORK=$(mktemp -d /tmp/pmos-gnome.XXXXXX)
OVERLAY="$WORK/overlay.qcow2"
MNT="$WORK/root"
mkdir -p "$MNT"

qemu-img create -q -f qcow2 -F raw -b "$(cd "$(dirname "$IMAGE")" && pwd)/$(basename "$IMAGE")" "$OVERLAY"

cleanup() {
	umount "$MNT" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

# ---- patch the overlay so a session starts without a physical display ----
echo "==> patching overlay for headless GNOME"
# Single-partition images: partition offset 0. Split images need the root partition offset;
# the caller is expected to have used -r to say which device is root.
OFFSET=0
if BLK=$(kpartx -asv "$OVERLAY" 2>/dev/null); then
	DEVS=$(printf '%s\n' "$BLK" | awk '{print $3}')
	LAST=$(printf '%s\n' "$DEVS" | tail -1)
	[ -n "$LAST" ] && { mount "/dev/mapper/$LAST" "$MNT"; MAPPED=1; }
fi
if [ "${MAPPED:-0}" != "1" ]; then
	# Fall back to a loop offset for images whose root starts at a known partition boundary.
	OFFSET_BYTES=$(python3 - "$IMAGE" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(512)
for i in range(4):
    e = d[446 + i*16: 446 + (i+1)*16]
    lba = struct.unpack('<I', e[8:12])[0]
    if lba:
        print(lba * 512)
        break
PY
)
	[ -n "$OFFSET_BYTES" ] || { echo "error: could not locate a partition" >&2; exit 1; }
	mount -o offset="$OFFSET_BYTES" "$OVERLAY" "$MNT"
fi

mkdir -p "$MNT/etc/environment"
cat > "$MNT/etc/environment" <<EOF
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
MESA_LOADER_DRIVER_OVERRIDE=swrast
EOF
# /etc/environment must be a file, fix if we just made a directory
rm -rf "$MNT/etc/environment.d" 2>/dev/null || true

# GDM autologin so a session exists before the VNC client ever connects.
mkdir -p "$MNT/etc/gdm"
cat > "$MNT/etc/gdm/custom.conf" <<EOF
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$GUSER
WaylandEnable=true
EOF

sync
umount "$MNT" 2>/dev/null || true
kpartx -d "$OVERLAY" 2>/dev/null || true

echo "==> booting with virtio-gpu; VNC on 127.0.0.1:$VNC_DISPLAY, ssh on 127.0.0.1:$SSH_PORT"
echo "==> NOTE: the VNC scanout does NOT follow the GNOME VT. Judge success by loginctl/ps/logs."

set -- \
	-M virt -cpu cortex-a72 -smp 4 -m "$MEM" \
	-kernel "$KERNEL" \
	-append "root=$ROOTDEV rootfstype=ext4 rw rootwait console=ttyAMA0,115200 loglevel=6" \
	-drive "file=$OVERLAY,format=qcow2,if=virtio" \
	-device "virtio-gpu-pci,xres=1024,yres=768" \
	-device virtio-net-pci,netdev=net0 \
	-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22" \
	-device virtio-serial-pci \
	-chardev "file,id=vc0,path=$WORK/virtio-serial.log" \
	-device "virtserialport,chardev=vc0,nr=1,name=pmos-console" \
	-serial "file:$WORK/serial.log" \
	-display "vnc=127.0.0.1:$VNC_DISPLAY" \
	-no-reboot

[ -n "$INITRD" ] && set -- "$@" -initrd "$INITRD"

qemu-system-aarch64 "$@"
echo "==> qemu exited; logs kept in $WORK (copy them out before this shell ends)"
echo "==> expected: gnome-shell running as $GUSER, XDG_SESSION_TYPE=wayland, /dev/dri/card0 present"
