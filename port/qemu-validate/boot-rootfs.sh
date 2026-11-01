#!/bin/sh
# Boot a postmarketOS aarch64 rootfs image under QEMU virt, serial console only.
#
# Proves whether the userspace (OpenRC / systemd) comes up. Does NOT need a GPU.
# The source image is never modified: a disposable qcow2 overlay is used and removed on exit.
#
# Usage: ./boot-rootfs.sh <image.img> [-r rootdev] [-m memory_mb] [-k host_kernel] [-i initrd]

set -eu

IMAGE=""
ROOTDEV="/dev/vda"
MEM=2048
KERNEL=""
INITRD=""

usage() {
	echo "usage: $0 <image.img> [-r /dev/vdaN] [-m MB] [-k host-kernel] [-i host-initrd]" >&2
	exit 1
}

[ $# -ge 1 ] || usage
IMAGE="$1"; shift
while [ $# -gt 0 ]; do
	case "$1" in
		-r) ROOTDEV="$2"; shift 2 ;;
		-m) MEM="$2"; shift 2 ;;
		-k) KERNEL="$2"; shift 2 ;;
		-i) INITRD="$2"; shift 2 ;;
		*) usage ;;
	esac
done

[ -f "$IMAGE" ] || { echo "error: no such image: $IMAGE" >&2; exit 1; }

# Default to the running aarch64 host kernel, which already has virtio + ext4.
if [ -z "$KERNEL" ]; then
	KERNEL="/boot/vmlinuz-$(uname -r)"
fi
[ -f "$KERNEL" ] || { echo "error: kernel not found: $KERNEL (pass -k)" >&2; exit 1; }

if [ -z "$INITRD" ]; then
	for cand in "/boot/initrd.img-$(uname -r)" "/boot/initramfs-$(uname -r).img"; do
		[ -f "$cand" ] && { INITRD="$cand"; break; }
	done
fi

# QEMU cannot boot a compressed kernel image directly on some builds; decompress if needed.
KERNEL_USE="$KERNEL"
case "$KERNEL" in
	*vmlinuz*)
		if command -v od >/dev/null 2>&1 && [ "$(od -An -tx1 -N2 "$KERNEL" | tr -d ' \n')" = "1f8b" ]; then
			KERNEL_USE="$(mktemp /tmp/pmos-qemu-kernel.XXXXXX)"
			# Find the gzip stream inside the bzImage/vmlinuz wrapper.
			offs=$(LC_ALL=C grep -abo $'\x1f\x8b\x08' "$KERNEL" | head -1 | cut -d: -f1)
			if [ -n "$offs" ]; then
				tail -c +$((offs + 1)) "$KERNEL" > "$KERNEL_USE.gz"
				gunzip -c "$KERNEL_USE.gz" > "$KERNEL_USE"
				rm -f "$KERNEL_USE.gz"
				echo "==> decompressed host kernel to $KERNEL_USE"
			fi
		fi
		;;
esac

OVERLAY="$(mktemp /tmp/pmos-qemu-rootfs.XXXXXX.qcow2)"
rm -f "$OVERLAY"
qemu-img create -q -f qcow2 -F raw -b "$(cd "$(dirname "$IMAGE")" && pwd)/$(basename "$IMAGE")" "$OVERLAY"

SERIAL_LOG="./qemu-rootfs-serial.log"

cleanup() {
	rm -f "$OVERLAY"
	case "$KERNEL_USE" in /tmp/pmos-qemu-kernel.*) rm -f "$KERNEL_USE" ;; esac
}
trap cleanup EXIT INT TERM

echo "==> booting $IMAGE (root=$ROOTDEV, ${MEM}M)"
echo "==> serial log: $SERIAL_LOG"

set -- \
	-M virt -cpu cortex-a72 -smp 4 -m "$MEM" \
	-kernel "$KERNEL_USE" \
	-append "root=$ROOTDEV rootfstype=ext4 rw rootwait console=ttyAMA0,115200 loglevel=7" \
	-drive "file=$OVERLAY,format=qcow2,if=virtio" \
	-display none -monitor none -no-reboot \
	-serial "file:$SERIAL_LOG"

[ -n "$INITRD" ] && set -- "$@" -initrd "$INITRD"

qemu-system-aarch64 "$@"
rc=$?
echo "==> qemu exited ($rc); see $SERIAL_LOG"
echo "==> look for OpenRC/systemd reaching the display-manager stage, not for a clean exit"
exit 0
