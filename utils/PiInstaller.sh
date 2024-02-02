#!/bin/bash

set -eo pipefail
set -o errtrace


trap 'exit_error $LINENO' INT ERR

isMounted() {
  findmnt -rno SOURCE,TARGET "$1" >/dev/null;
}

exit_error() {
  /bin/echo "PiInstaller '${task}' failed at lineno: $1"

  if isMounted /tmp/boot; then
    /bin/umount /tmp/boot
  fi

  if isMounted /tmp/volumio; then
    /bin/umount /tmp/volumio
  fi

  [ -d "/tmp/boot" ] && /bin/rm -r /tmp/boot
  [ -d "/tmp/volumio" ] && /bin/rm -r /tmp/volumio

}

if [ "$#" -ne 8 ]; then
  /bin/echo "Incorrect number of parameters"
  exit 1
fi

# Wipe the partition table
/bin/dd if=/dev/zero of=$1 count=512 > /dev/null 2>&1
/bin/echo "5" > /tmp/install_progress

# Re-partition
/sbin/parted -s ${1} mklabel "${2}"
/bin/echo "10" > /tmp/install_progress
/sbin/parted -s ${1} mkpart primary fat32 ${3} ${4}
/bin/echo "13" > /tmp/install_progress
/sbin/parted -s ${1} mkpart primary ext3  ${4} ${5}
/bin/echo "16" > /tmp/install_progress
/sbin/parted -s ${1} mkpart primary ext3  ${5} 100%
/bin/echo "20" > /tmp/install_progress
/sbin/parted -s ${1} set 1 boot on
sync
/sbin/partprobe ${1}
sleep 3

# Create filesystems
/bin/echo "25" > /tmp/install_progress
/sbin/mkfs -t vfat -F 32 -n boot ${6} > /dev/null 2>&1
/bin/echo "30" > /tmp/install_progress
/sbin/mkfs -F -t ext4 -L volumio ${7} > /dev/null 2>&1
/bin/echo "35" > /tmp/install_progress
/sbin/mkfs -F -t ext4 -L volumio_data ${8} > /dev/null 2>&1
/bin/echo "40" > /tmp/install_progress

# Mount boot and image partition
/bin/mkdir /tmp/boot
/bin/mkdir /tmp/volumio
/bin/mount $6 /tmp/boot
/bin/mount $7 /tmp/volumio
/bin/echo "50" > /tmp/install_progress

# Install current boot partition
/bin/tar xf /imgpart/kernel_current.tar -C /tmp/boot > /dev/null 2>&1
/bin/echo "60" > /tmp/install_progress

# Copy current squash file
/bin/cp -r /imgpart/* /tmp/volumio
/bin/echo "65" > /tmp/install_progress

# Prepare UUIDs
uuid_boot=$(/sbin/blkid -s UUID -o value ${6})
uuid_img=$(/sbin/blkid -s UUID -o value ${7})
uuid_data=$(/sbin/blkid -s UUID -o value ${8})

# Init a loop pointing to the image file
/bin/mkdir -m 777 /tmp/work # working directory
/bin/mkdir -m 777 /tmp/work/from # for mounting original
/bin/mkdir -m 777 /tmp/work/to # for upper unionfs layers
/bin/mkdir -m 777 /tmp/work/temp # some overlayfs technical folder
/bin/mkdir -m 777 /tmp/work/final # resulting folders/files would be there
/bin/mount /tmp/volumio/volumio_current.sqsh /tmp/work/from -t squashfs -o loop
/bin/mount -t overlay -olowerdir=/tmp/work/from,upperdir=/tmp/work/to,workdir=/tmp/work/temp overlay /tmp/work/final
/bin/echo "70" > /tmp/install_progress

# Update UUIDs
/bin/sed -i "s/%%IMGPART%%/${uuid_img}/g" /tmp/boot/cmdline.txt
/bin/sed -i "s/%%BOOTPART%%/${uuid_boot}/g" /tmp/boot/cmdline.txt
/bin/sed -i "s/%%DATAPART%%/${uuid_data}/g" /tmp/boot/cmdline.txt
/bin/sed -i "s/%%BOOTPART%%/${uuid_boot}/g" /tmp/work/final/etc/fstab
/bin/echo "75" > /tmp/install_progress

# Package resulting volumio_current squash file
/usr/bin/mksquashfs /tmp/work/final/final /tmp/volumio/volumio_current.new
/bin/echo "80" > /tmp/install_progress

# Cleanup working directory 
sudo umount /tmp/work/from
sudo umount /tmp/work/final
/bin/rm -rf /tmp/work/from # for mounting original
/bin/rm -rf /tmp/work/to # for upper unionfs layers
/bin/rm -rf /tmp/work/temp # some overlayfs technical folder
/bin/rm -rf /tmp/work/final # resulting folders/files would be there
/bin/rm -rf /tmp/work # working directory
/bin/echo "85" > /tmp/install_progress

# Move new and replace volumio_current squash file
/bin/mv -f /tmp/volumio/volumio_current.new /tmp/volumio/volumio_current.sqsh
/bin/echo "99" > /tmp/install_progress

# Cleanup
/bin/rm -r /tmp/volumio/lost+found
/bin/umount /tmp/boot
/bin/umount /tmp/volumio
/bin/rm -r /tmp/boot
/bin/rm -r /tmp/volumio

sleep 1
