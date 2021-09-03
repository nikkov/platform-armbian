#!/bin/bash
C=`pwd`
A=../armbian
B=current
USERPATCHES_KERNEL_DIR=${B}
P=$1
V=v21.08
RT=$2
PREEMPT_RT=n

if [ "$RT" = "rt" ]; then
PREEMPT_RT=y
fi

cd ${A}
CUR_BRANCH=`git rev-parse --abbrev-ref HEAD`
cd ${C}

case $P in
'nanopineo' | 'nanopiair')
  PLATFORM="sun8i-h3"
  ;;
'nanopineo2' | 'nanopineoplus2' | 'nanopineo2black')
  PLATFORM="sun50i-h5"
  ;;
'cubietruck')
  PLATFORM="sun7i-a20"
  ;;
*)
  PLATFORM="unknown"
  echo "Please set known board name as script parameter"
  exit 1
  ;;
esac

echo "-----Build for ${P}, platform ${PLATFORM}-----"
echo "-----Current armbian branch is ${CUR_BRANCH}-----"
if [ "$PREEMPT_RT" = "y" ]; then
echo "-----Used PREEMPT_RT patch-----"
fi

if [ -d ${A} ]; then
  echo "Armbian folder already exists - keeping it"
if [ "${CUR_BRANCH}" != "heads/${V}" ];
then
  echo "Armbian branch changed from ${CUR_BRANCH} to heads/${V}"
  cd ${A}
  git checkout master
  git pull
  git checkout --track origin/${V} && touch .ignore_changes
fi
else
  echo "Clone Armbian repository to folder ${A}"
  git clone https://github.com/armbian/build ${A}
  cd ${A}
  git checkout ${V} && touch .ignore_changes
fi

cd ${C}
echo "Clean old patches"
rm -rf ./${A}/userpatches
echo "Copy patches"
mkdir -p ./${A}/userpatches/kernel/sunxi-${USERPATCHES_KERNEL_DIR}
cp ${C}/patches/kernel/sunxi-${B}/*.patch ./${A}/userpatches/kernel/sunxi-${USERPATCHES_KERNEL_DIR}/

if [ "$PREEMPT_RT" = "y" ]; then
 echo "Copy PREEMPT_RT patches and config"
 cp ${C}/patches/kernel/sunxi-${B}/rt/*.patch ./${A}/userpatches/kernel/sunxi-${USERPATCHES_KERNEL_DIR}/
 echo "Copy RT config and patch"
 if [ "$PLATFORM" = "sun50i-h5" ]; then
  cp ./${A}/config/kernel/linux-sunxi64-${B}.config ./${A}/userpatches/linux-sunxi64-${B}.config
  cd ${A}
  patch -p0 < ${C}/patches/config/rt/linux-sunxi64-${B}.patch
  cd ${C}
 else 
  cp ./${A}/config/kernel/linux-sunxi-${B}.config ./${A}/userpatches/linux-sunxi-${B}.config
  cd ${A}
  patch -p0 < ${C}/patches/config/rt/linux-sunxi-${B}.patch
  cd ${C}
 fi
else
 if [ "$PLATFORM" = "sun50i-h5" ]; then
 echo "Copy config and patch"
  cp ./${A}/config/kernel/linux-sunxi64-${B}.config ./${A}/userpatches/linux-sunxi64-${B}.config
  cd ${A}
  patch -p0 < ${C}/patches/config/linux-sunxi64-${B}.patch
  cd ${C}
 else 
  cp ./${A}/config/kernel/linux-sunxi-${B}.config ./${A}/userpatches/linux-sunxi-${B}.config
  cd ${A}
  patch -p0 < ${C}/patches/config/linux-sunxi-${B}.patch
  cd ${C}
 fi
fi

cd ${A}

rm -rf ./${A}/output/debs

echo "U-Boot & kernel compile for ${P}"
./compile.sh KERNEL_ONLY=yes BOARD=${P} BRANCH=${B} LIB_TAG=${V} RELEASE=buster KERNEL_CONFIGURE=no EXTERNAL=yes BUILD_KSRC=no BUILD_DESKTOP=no

cd ${C}
rm -rf ./${P}
mkdir ./${P}
mkdir ./${P}/u-boot
mkdir -p ./${P}/usr/sbin

echo "Install packages for ${P}"
dpkg-deb -x ./${A}/output/debs/linux-dtb-* ${P}
dpkg-deb -x ./${A}/output/debs/linux-image-* ${P}
dpkg-deb -x ./${A}/output/debs/linux-u-boot-* ${P}
dpkg-deb -x ./${A}/output/debs/armbian-firmware_* ${P}

echo "Copy U-Boot"
cp ./${P}/usr/lib/linux-u-boot-${B}-*/u-boot-sunxi-with-spl.bin ./${P}/u-boot

rm -rf ./${P}/usr ./${P}/etc
mv ./${P}/boot/dtb* ./${P}/boot/dtb

if [ "$PLATFORM" = "sun50i-h5" ]; then
  mv ./${P}/boot/vmlinuz* ./${P}/boot/Image
else
  mv ./${P}/boot/vmlinuz* ./${P}/boot/zImage
fi

echo "Copy overlays for ${PLATFORM}"
mkdir ./${P}/boot/overlay-user
cp ${C}/sources/overlays/${PLATFORM}-*.* ./${P}/boot/overlay-user
dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/${PLATFORM}-i2s0-master.dtbo ${C}/sources/overlays/${PLATFORM}-i2s0-master.dts
dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/${PLATFORM}-i2s0-slave.dtbo ${C}/sources/overlays/${PLATFORM}-i2s0-slave.dts
if [ "$P" = "cubietruck" ]; then
 echo "Copy overlays for disabling audio-codec and spdif for cubietruck"
 dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/sun7i-a20-analog-codec-disable.dtbo ${C}/sources/overlays/sun7i-a20-analog-codec-disable.dts
 dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/sun7i-a20-spdif-disable.dtbo ${C}/sources/overlays/sun7i-a20-spdif-disable.dts
else
 dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/${PLATFORM}-powen.dtbo ${C}/sources/overlays/${PLATFORM}-powen.dts
 dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/${PLATFORM}-powbut.dtbo ${C}/sources/overlays/${PLATFORM}-powbut.dts
 dtc -@ -q -I dts -O dtb -o ./${P}/boot/overlay-user/${PLATFORM}-powman.dtbo ${C}/sources/overlays/${PLATFORM}-powman.dts
fi


if [ "$PLATFORM" = "sun50i-h5" ]; then
  cp ./${A}/config/bootscripts/boot-sun50i-next.cmd ./${P}/boot/boot.cmd
else
  cp ./${A}/config/bootscripts/boot-sunxi.cmd ./${P}/boot/boot.cmd
fi

mkimage -c none -A arm -T script -d ./${P}/boot/boot.cmd ./${P}/boot/boot.scr
touch ./${P}/boot/.next

echo "Create armbianEnv.txt"
case $P in
'nanopineo' | 'nanopiair')
  echo "verbosity=1
logo=disabled
console=serial
disp_mode=none
overlay_prefix=sun8i-h3
overlays=i2c0 analog-codec
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun8i-h3-i2s0-slave
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh" >> ./${P}/boot/armbianEnv.txt
  ;;
'cubietruck')
  echo "verbosity=1
logo=disabled
console=serial
disp_mode=1920x1080p60
overlay_prefix=sun7i-a20
overlays=
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun7i-a20-i2s0-slave
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh" >> ./${P}/boot/armbianEnv.txt
  ;;
'nanopineo2' | 'nanopineoplus2')
  echo "verbosity=1
logo=disabled
console=serial
overlay_prefix=sun50i-h5
overlays=usbhost1 usbhost2 analog-codec
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun50i-h5-i2s0-slave
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh" >> ./${P}/boot/armbianEnv.txt
  ;;
'nanopineo2black')
  echo "verbosity=1
logo=disabled
console=serial
overlay_prefix=sun50i-h5
overlays=usbhost1 usbhost2
rootdev=/dev/mmcblk0p2
rootfstype=ext4
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh" >> ./${P}/boot/armbianEnv.txt
  ;;
esac

rm $P.tar.xz
tar cJf $P.tar.xz $P
