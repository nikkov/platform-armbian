#!/bin/bash
C=`pwd`
A=../armbian
B=current
P=$1
V=v19.11

if [ -d ${A} ]; then
  echo "Armbian folder already exists - keeping it"
else
  echo "clone Armbian repository to folder ${A}"
  git clone https://github.com/armbian/build ${A}
  cd ${A}
  git checkout ${V} && touch .ignore_changes
fi

cd ${C}
mkdir -p ${A}/userpatches/kernel/sunxi-${B}
cp ${C}/patches/kernel/sunxi-${B}/*.patch ${A}/userpatches/kernel/sunxi-${B}/
if [ "$P" = "nanopineo2" ]; then
cp ${A}/config/kernel/linux-sunxi64-${B}.config ${A}/userpatches/linux-sunxi64-${B}.config
cd ${A}
patch -p0 < ${C}/patches/config/linux-sunxi64-${B}.patch
fi
cd ${A}

rm -rf ${A}/output/debs

 echo "U-Boot & kernel compile for ${P}"
./compile.sh KERNEL_ONLY=yes BOARD=${P} BRANCH=${B} LIB_TAG=${V} RELEASE=buster KERNEL_CONFIGURE=no EXTERNAL=yes BUILD_KSRC=no BUILD_DESKTOP=no

cd ${C}
rm -rf ${P}
mkdir ${P}
mkdir ${P}/u-boot
mkdir -p ${P}/usr/sbin

dpkg-deb -x ${A}/output/debs/linux-dtb-* ${P}
dpkg-deb -x ${A}/output/debs/linux-image-* ${P}
dpkg-deb -x ${A}/output/debs/linux-u-boot-* ${P}
dpkg-deb -x ${A}/output/debs/armbian-firmware_* ${P}

if [ "$P" = "nanopineo2" ]; then
  cp ${P}/usr/lib/linux-u-boot-${B}-*/sunxi-spl.bin ${P}/u-boot
  cp ${P}/usr/lib/linux-u-boot-${B}-*/u-boot.itb ${P}/u-boot
else
  cp ${P}/usr/lib/linux-u-boot-${B}-*/u-boot-sunxi-with-spl.bin ${P}/u-boot
fi

rm -rf ${P}/usr ${P}/etc

mv ${P}/boot/dtb* ${P}/boot/dtb

if [ "$P" = "nanopineo2" ]; then
  mv ${P}/boot/vmlinuz* ${P}/boot/Image
else
  mv ${P}/boot/vmlinuz* ${P}/boot/zImage
fi

mkdir ${P}/boot/overlay-user
#cp sun8i-h3-i2s0*.* ${P}/boot/overlay-user
if [ "$P" = "nanopineo2" ]; then
  cp sun50i-h5-*.* ${P}/boot/overlay-user
  dtc -@ -q -I dts -O dtb -o ${P}/boot/overlay-user/sun50i-h5-i2s0-master.dtbo ${C}/sources/overlays/sun50i-h5-i2s0-master.dts
  dtc -@ -q -I dts -O dtb -o ${P}/boot/overlay-user/sun50i-h5-i2s0-slave.dtbo ${C}/sources/overlays/sun50i-h5-i2s0-slave.dts
  dtc -@ -q -I dts -O dtb -o ${P}/boot/overlay-user/sun50i-h5-powen.dtbo ${C}/sources/overlays/sun50i-h5-powen.dts

  cp ${A}/config/bootscripts/boot-sun50i-next.cmd ${P}/boot/boot.cmd
else
  cp sun8i-h3-*.* ${P}/boot/overlay-user
  dtc -@ -q -I dts -O dtb -o ${P}/boot/overlay-user/sun8i-h3-i2s0-master.dtbo ${C}/sources/overlays/sun8i-h3-i2s0-master.dts
  dtc -@ -q -I dts -O dtb -o ${P}/boot/overlay-user/sun8i-h3-i2s0-slave.dtbo ${C}/sources/overlays/sun8i-h3-i2s0-slave.dts
  dtc -@ -q -I dts -O dtb -o ${P}/boot/overlay-user/sun8i-h3-powen.dtbo ${C}/sources/overlays/sun8i-h3-powen.dts

  cp ${A}/config/bootscripts/boot-sunxi.cmd ${P}/boot/boot.cmd
fi

mkimage -c none -A arm -T script -d ${P}/boot/boot.cmd ${P}/boot/boot.scr
touch ${P}/boot/.next

if [ "$P" = "nanopineo2" ]; then
  echo "verbosity=1
logo=disabled
console=serial
overlay_prefix=sun50i-h5
overlays=usbhost1 usbhost2
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun50i-h5-i2s0-slave
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh" >> ${P}/boot/armbianEnv.txt
else
  echo "verbosity=1
logo=disabled
console=serial
disp_mode=1920x1080p60
overlay_prefix=sun8i-h3
overlays=i2c0
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun8i-h3-i2s0-slave
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh" >> ${P}/boot/armbianEnv.txt
fi

case $1 in
'pc' | 'zero')
  sed -i "s/i2c0/i2c0 analog-codec/" ${P}/boot/armbianEnv.txt
  ;;
esac

tar cJf $P.tar.xz $P
