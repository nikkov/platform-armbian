#!/bin/bash
C=`pwd`
A=../armbian
BRANCH=current
BOARD=$1
V=v23.08
D=${BOARD}-armbian

case $BOARD in
'nanopineo' | 'nanopiair' | 'orangepipc')
  PLATFORM="sun8i-h3"
  ;;
'nanopineo2' | 'nanopineoplus2' | 'nanopineo2black')
  PLATFORM="sun50i-h5"
  ;;
'cubietruck')
  PLATFORM="sun7i-a20"
  ;;
'nanopineo3')
  PLATFORM="rockchip"
  ;;
*)
  PLATFORM="unknown"
  echo "Please set known board name as script parameter"
  exit 1
  ;;
esac

case $PLATFORM in
'sun8i-h3' | 'sun7i-a20')
  LINUX_CONGIG_NAME="linux-sunxi-${BRANCH}.config"
  PATCHES_SRC_DIR=${C}/patches/kernel/sunxi
  PATCHES_DST_DIR=${C}/${A}/userpatches/kernel/archive/sunxi-6.1
  ;;
'sun50i-h5')
  LINUX_CONGIG_NAME="linux-sunxi64-${BRANCH}.config"
  PATCHES_SRC_DIR=${C}/patches/kernel/sunxi
  PATCHES_DST_DIR=${C}/${A}/userpatches/kernel/archive/sunxi-6.1
  ;;
'rockchip')
  LINUX_CONGIG_NAME="linux-rockchip64-${BRANCH}.config"
  PATCHES_SRC_DIR=${C}/patches/kernel/rockchip
  PATCHES_DST_DIR=${C}/${A}/userpatches/kernel/rockchip64-${BRANCH}
  ;;
esac


echo "-----Build platform files for ${BOARD} - ${PLATFORM}-----"

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
echo "Clean old kernel config and patches..."
rm -rf ${C}/${A}/userpatches

echo "Copy kernel config and patches..."
mkdir -p ${PATCHES_DST_DIR}

cp ./${A}/config/kernel/${LINUX_CONGIG_NAME} ${C}/${A}/userpatches/

echo "Enable PCM5102A and custom codec drivers in kernel config..."
case $PLATFORM in
'sun8i-h3' | 'sun7i-a20')
  sed -i "s/# CONFIG_SND_SOC_PCM5102A is not set/CONFIG_SND_SOC_PCM5102A=m\nCONFIG_SND_SOC_I2S_CLOCK_BOARD=m/1" ./${A}/userpatches/${LINUX_CONGIG_NAME}
  ;;
'sun50i-h5' | 'rockchip')
  sed -i "s/CONFIG_SND_SOC_PCM5102A=m/CONFIG_SND_SOC_PCM5102A=m\nCONFIG_SND_SOC_I2S_CLOCK_BOARD=m/1" ./${A}/userpatches/${LINUX_CONGIG_NAME}
  ;;
esac

#copy kernel patches
cp ${PATCHES_SRC_DIR}/*.patch ${PATCHES_DST_DIR}/

cd ${A}

echo "Clean old debs"
rm -rf ./${A}/output/debs
echo "U-Boot & kernel compile for ${BOARD}"
./compile.sh BUILD_ONLY="u-boot'kernel,armbian-firmware" SHARE_LOG=yes ARTIFACT_IGNORE_CACHE='yes' BOARD=${BOARD} BRANCH=${BRANCH} BUILD_MINIMAL=yes RELEASE=bullseye KERNEL_CONFIGURE=no
retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Error compile!"
    exit $retVal
fi

cd ${C}
rm -rf ./${D}
mkdir ./${D}
mkdir ./${D}/u-boot
mkdir -p ./${D}/usr/sbin

echo "Install packages for ${BOARD}"
dpkg-deb -x ./${A}/output/debs/linux-dtb-* ${D}
dpkg-deb -x ./${A}/output/debs/linux-image-* ${D}
dpkg-deb -x ./${A}/output/debs/linux-u-boot-* ${D}
dpkg-deb -x ./${A}/output/debs/armbian-firmware_* ${D}

echo "Copy U-Boot"

if [ "$PLATFORM" = "rockchip" ]; then
  cp ./${D}/usr/lib/linux-u-boot-${BRANCH}-*/*.* ./${D}/u-boot
else
  cp ./${D}/usr/lib/linux-u-boot-${BRANCH}-*/u-boot-sunxi-with-spl.bin ./${D}/u-boot
fi

rm -rf ./${D}/usr ./${D}/etc
mv ./${D}/boot/dtb* ./${D}/boot/dtb

case $PLATFORM in
'sun50i-h5' | 'rockchip')
  mv ./${D}/boot/vmlinuz* ./${D}/boot/Image
  ;;
*)
  mv ./${D}/boot/vmlinuz* ./${D}/boot/zImage
  ;;
esac

echo "Copy overlays for ${PLATFORM}"
OVERLAYS_DIR=./${D}/boot/overlay-user
mkdir ${OVERLAYS_DIR}

case $BOARD in
'nanopineo' | 'nanopiair' | 'orangepipc' | 'nanopineo2' | 'nanopineoplus2' | 'nanopineo2black')
  cp ${C}/sources/overlays/allwinner/${PLATFORM}-*.* ${OVERLAYS_DIR}
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-i2s0-master.dtbo ${OVERLAYS_DIR}/${PLATFORM}-i2s0-master.dts
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-i2s0-slave.dtbo ${OVERLAYS_DIR}/${PLATFORM}-i2s0-slave.dts
  #Overlays for power management
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-powen.dtbo ${OVERLAYS_DIR}/${PLATFORM}-powen.dts
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-powbut.dtbo ${OVERLAYS_DIR}/${PLATFORM}-powbut.dts
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-powman.dtbo ${OVERLAYS_DIR}/${PLATFORM}-powman.dts
  ;;
'cubietruck')
  cp ${C}/sources/overlays/allwinner/${PLATFORM}-*.* ${OVERLAYS_DIR}
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-i2s0-master.dtbo ${OVERLAYS_DIR}/${PLATFORM}-i2s0-master.dts
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-i2s0-slave.dtbo ${OVERLAYS_DIR}/${PLATFORM}-i2s0-slave.dts
  #overlays for disabling audio-codec and spdif for cubietruck
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-analog-codec-disable.dtbo ${OVERLAYS_DIR}/${PLATFORM}-analog-codec-disable.dts
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-spdif-disable.dtbo ${OVERLAYS_DIR}/${PLATFORM}-spdif-disable.dts
  ;;
'nanopineo3')
  cp ${C}/sources/overlays/rockchip/${PLATFORM}-*.* ${OVERLAYS_DIR}
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-i2s-external-mclk.dtbo ${OVERLAYS_DIR}/${PLATFORM}-i2s-external-mclk.dts
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-spdif-out-enable.dtbo ${OVERLAYS_DIR}/${PLATFORM}-spdif-out-enable.dts
  #Overlays for power management
  dtc -@ -q -I dts -O dtb -o ${OVERLAYS_DIR}/${PLATFORM}-powman.dtbo ${OVERLAYS_DIR}/${PLATFORM}-powman.dts
  ;;
esac

case $PLATFORM in
'sun8i-h3' | 'sun7i-a20')
  cp ./${A}/config/bootscripts/boot-sunxi.cmd ./${D}/boot/boot.cmd
  ;;
'sun50i-h5')
  cp ./${A}/config/bootscripts/boot-sun50i-next.cmd ./${D}/boot/boot.cmd
  ;;
'rockchip')
  cp ./${A}/config/bootscripts/boot-rockchip64.cmd ./${D}/boot/boot.cmd
  ;;
esac

mkimage -c none -A arm -T script -d ./${D}/boot/boot.cmd ./${D}/boot/boot.scr
touch ./${D}/boot/.next

echo "Create armbianEnv.txt"
case $BOARD in
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
'nanopineo3')
  echo "verbosity=1
bootlogo=false
overlay_prefix=rockchip
fdtfile=rockchip/rk3328-nanopi-neo3-rev02.dtb
rootfstype=ext4
console=serial
user_overlays=rockchip-spdif-out-enable
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
extraargs=imgpart=/dev/mmcblk0p2 imgfile=/volumio_current.sqsh net.ifnames=0" >> ./${D}/boot/armbianEnv.txt
  ;;
esac

echo "Create $D.tar.xz"
rm $D.tar.xz
tar cJf $D.tar.xz $D
