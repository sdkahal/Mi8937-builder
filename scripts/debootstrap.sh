#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
RELEASE=${RELEASE=jammy}
HOST_NAME=${HOST_NAME=land}

rm -rf ${CHROOT}

# Use mmdebstrap for faster builds (god, it's so much faster)
echo "Using mmdebstrap for fast bootstrap..."
mmdebstrap --arch=arm64 \
    --include=systemd,udev,dbus,apt,wget,ca-certificates \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    ${RELEASE} ${CHROOT} http://ports.ubuntu.com/ubuntu-ports

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
# # deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
EOF

# Speed up apt
cat << EOF > ${CHROOT}/etc/apt/apt.conf.d/99speedup
APT::Acquire::Retries "3";
APT::Acquire::http::Timeout "10";
APT::Acquire::ftp::Timeout "10";
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options::="--force-confdef";
DPkg::Options::="--force-confold";
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

# configs'n stuff
mkdir -p ${CHROOT}/etc/systemd/system
cp -a configs/system/* ${CHROOT}/etc/systemd/system
cp configs/nftables.conf ${CHROOT}/etc/nftables.conf
mkdir -p ${CHROOT}/etc/NetworkManager/system-connections
mkdir -p ${CHROOT}/etc/NetworkManager/conf.d
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
cp configs/99-custom.conf ${CHROOT}/etc/NetworkManager/conf.d/
cp configs/default-wifi-powersave-on.conf ${CHROOT}/etc/NetworkManager/conf.d/
mkdir -p ${CHROOT}/etc/systemd/network
cp configs/10-usb0.network ${CHROOT}/etc/systemd/network/

# chroot setup
cp scripts/setup.sh ${CHROOT}

# copy debs  setup.sh install
cp debs/* ${CHROOT}/root/

# Copy qemu static and run setup script in chroot
cp /usr/bin/qemu-aarch64-static ${CHROOT}/usr/bin/
chroot ${CHROOT} qemu-aarch64-static /bin/sh -c "/setup.sh"

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm -f ${CHROOT}/setup.sh
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# hosts entry for the LAN IP
cat <<EOF >> ${CHROOT}/etc/hosts

192.168.100.1	${HOST_NAME}
EOF

# add MSM8916 USB gadget
cp -a configs/msm8916-usb-gadget.sh ${CHROOT}/usr/sbin/
cp configs/msm8916-usb-gadget.conf ${CHROOT}/etc/

# Install firmware into rootfs
mkdir -p ${CHROOT}/lib/firmware/
cp -a firmware/* ${CHROOT}/lib/firmware/

# install targz kernel
wget https://github.com/sdkahal/Armbian-build/releases/download/v2/linux-7.0.2-msm8937-arm64.tar.gz
tar -xzf linux-7.0.2-msm8937-arm64.tar.gz -C ${CHROOT}/root/ 2>/dev/null
mkdir -p ${CHROOT}/boot/
cp -rfpa ${CHROOT}/root/boot/* ${CHROOT}/boot/
mkdir -p ${CHROOT}/usr/lib/modules/
cp -rfpa ${CHROOT}/root/lib/modules/* ${CHROOT}/usr/lib/modules/
rm -rf ${CHROOT}/boot/vmlinux*
rm -rf ${CHROOT}/boot/System.map*
rm -rf ${CHROOT}/root/boot
rm -rf ${CHROOT}/root/lib

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
mkdir -p ${CHROOT}/boot/dtbs/qcom/
cp dtbs/* ${CHROOT}/boot/dtbs/qcom/


# update fstab
printf "PARTUUID=2fc3ff08-58af-3268-8d94-28ce07d79c0c\t/\tf2fs\trw,noatime\t0 1\n" > ${CHROOT}/etc/fstab
#echo -e "PARTUUID=8CA60C57-5EB2-1D44-4488-9FBFFAD1E061\t/\text4\trw,noatime\t0 1" > ${CHROOT}/etc/fstab
#echo "PARTUUID=8B8169CE-CC60-B23A-5411-132D6AE86697\t/boot\text2\tdefaults\t0 2" >> ${CHROOT}/etc/fstab

# initramfs
mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/
chroot ${CHROOT} qemu-aarch64-static /bin/sh -c "update-initramfs -c -k all"
# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;
rm -f ${CHROOT}/usr/bin/qemu-aarch64-static

# backup rootfs
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .
