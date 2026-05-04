#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}

#package rootfs
rm -f rootfs.raw boot.raw
mkdir -p files mnt

# create boot
truncate -s 66060288 boot.raw
mkfs.ext2 boot.raw
mount boot.raw mnt
tar xf rootfs.tgz -C mnt ./boot --exclude='./boot/linux.efi' --strip-components=2
umount mnt

# create root img
# Default 3GB (3221225472), override with ROOTFS_SIZE env var
# Sparse output compresses empty space, so output file size stays small
ROOTFS_SIZE=${ROOTFS_SIZE:-3221225472}
truncate -s ${ROOTFS_SIZE} rootfs.raw
mkfs.f2fs rootfs.raw
TEMP_DIR=$(mktemp -d)
tar xpf rootfs.tgz -C $TEMP_DIR --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'
sload.f2fs -f $TEMP_DIR rootfs.raw
rm -rf $TEMP_DIR

# create sparse android images 
img2simg rootfs.raw files/rootfs.bin
img2simg boot.raw files/boot.bin
