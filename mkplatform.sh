#!/bin/bash
C=`pwd`
A=../armbian
B=current
USERPATCHES_KERNEL_DIR=${B}
P=$1
V=v21.08
D=${P}-armbian

cd ${A}
CUR_BRANCH=`git rev-parse --abbrev-ref HEAD`
cd ${C}

case $P in
'nanopineo' | 'nanopiair' | 'orangepipc')
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

if [ ! -d ${A} ]; then
  echo "Armbian folder not exists"
  echo "Clone Armbian repository to folder ${A}"
  git clone https://github.com/armbian/build ${A}
else
  echo "Armbian folder already exists - keeping it"
fi

  cd ${A}
CUR_BRANCH=`git branch --show-current`
echo "-----Current armbian branch is ${CUR_BRANCH}-----"
if [ "${CUR_BRANCH}" != "${V}" ];
then
  echo "Armbian branch will changed from ${CUR_BRANCH} to ${V}"
  git fetch
  git switch ${V} && touch .ignore_changes
fi

cd ${C}
echo "Clean old patches"
rm -rf ./${A}/userpatches
echo "Copy patches"
mkdir -p ./${A}/userpatches/kernel/sunxi-${USERPATCHES_KERNEL_DIR}
cp ${C}/patches/kernel/sunxi-${B}/*.patch ./${A}/userpatches/kernel/sunxi-${USERPATCHES_KERNEL_DIR}/

cd ${A}

rm -rf ./${A}/output/debs

echo "U-Boot & kernel compile for ${P}"
./compile.sh docker KERNEL_ONLY=yes BOARD=${P} BRANCH=${B} LIB_TAG=${V} RELEASE=buster KERNEL_CONFIGURE=no EXTERNAL=yes BUILD_KSRC=no BUILD_DESKTOP=no IGNORE_CHANGES=yes

cd ${C}
rm -rf ./${D}
mkdir ./${D}
mkdir ./${D}/u-boot
mkdir -p ./${D}/usr/sbin

echo "Install packages for ${P}"
dpkg-deb -x ./${A}/output/debs/linux-dtb-* ${D}
dpkg-deb -x ./${A}/output/debs/linux-image-* ${D}
dpkg-deb -x ./${A}/output/debs/linux-u-boot-* ${D}
dpkg-deb -x ./${A}/output/debs/armbian-firmware_* ${D}

echo "Copy U-Boot"
cp ./${D}/usr/lib/linux-u-boot-${B}-*/u-boot-sunxi-with-spl.bin ./${D}/u-boot

rm -rf ./${D}/usr ./${D}/etc
mv ./${D}/boot/dtb* ./${D}/boot/dtb

if [ "$PLATFORM" = "sun50i-h5" ]; then
  mv ./${D}/boot/vmlinuz* ./${D}/boot/Image
else
  mv ./${D}/boot/vmlinuz* ./${D}/boot/zImage
fi

echo "Copy overlays for ${PLATFORM}"
mkdir ./${D}/boot/overlay-user
cp ${C}/sources/overlays/${PLATFORM}-*.* ./${D}/boot/overlay-user
dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/${PLATFORM}-i2s0-master.dtbo ${C}/sources/overlays/${PLATFORM}-i2s0-master.dts
dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/${PLATFORM}-i2s0-slave.dtbo ${C}/sources/overlays/${PLATFORM}-i2s0-slave.dts
if [ "$P" = "cubietruck" ]; then
 echo "Copy overlays for disabling audio-codec and spdif for cubietruck"
 dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/sun7i-a20-analog-codec-disable.dtbo ${C}/sources/overlays/sun7i-a20-analog-codec-disable.dts
 dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/sun7i-a20-spdif-disable.dtbo ${C}/sources/overlays/sun7i-a20-spdif-disable.dts
else
 dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/${PLATFORM}-powen.dtbo ${C}/sources/overlays/${PLATFORM}-powen.dts
 dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/${PLATFORM}-powbut.dtbo ${C}/sources/overlays/${PLATFORM}-powbut.dts
 dtc -@ -q -I dts -O dtb -o ./${D}/boot/overlay-user/${PLATFORM}-powman.dtbo ${C}/sources/overlays/${PLATFORM}-powman.dts
fi


if [ "$PLATFORM" = "sun50i-h5" ]; then
  cp ./${A}/config/bootscripts/boot-sun50i-next.cmd ./${D}/boot/boot.cmd
else
  cp ./${A}/config/bootscripts/boot-sunxi.cmd ./${D}/boot/boot.cmd
fi

mkimage -c none -A arm -T script -d ./${D}/boot/boot.cmd ./${D}/boot/boot.scr
touch ./${D}/boot/.next

echo "Create armbianEnv.txt"
case $P in
'nanopineo' | 'nanopiair' | 'orangepipc')
  echo "verbosity=1
logo=disabled
console=serial
disp_mode=none
overlay_prefix=sun8i-h3
overlays=i2c0 analog-codec i2c0
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun8i-h3-i2s0-slave
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh net.ifnames=0" >> ./${D}/boot/armbianEnv.txt
  ;;
'cubietruck')
  echo "verbosity=1
logo=disabled
console=serial
disp_mode=1920x1080p60
overlay_prefix=sun7i-a20
overlays=i2c0
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun7i-a20-i2s0-slave
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh net.ifnames=0" >> ./${D}/boot/armbianEnv.txt
  ;;
'nanopineo2' | 'nanopineoplus2')
  echo "verbosity=1
logo=disabled
console=serial
overlay_prefix=sun50i-h5
overlays=usbhost1 usbhost2 analog-codec i2c0
rootdev=/dev/mmcblk0p2
rootfstype=ext4
user_overlays=sun50i-h5-i2s0-slave
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh net.ifnames=0" >> ./${D}/boot/armbianEnv.txt
  ;;
'nanopineo2black')
  echo "verbosity=1
logo=disabled
console=serial
overlay_prefix=sun50i-h5
overlays=usbhost1 usbhost2 i2c0
rootdev=/dev/mmcblk0p2
rootfstype=ext4
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh net.ifnames=0" >> ./${D}/boot/armbianEnv.txt
  ;;
esac

rm $D.tar.xz
tar cJf $D.tar.xz $D
