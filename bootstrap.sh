#!/bin/bash

source .env

# remove previous Ceph config
echo "Removing old Ceph config from ${VOLUMES_PATH}/ceph/"
sudo rm -rf ${VOLUMES_PATH}/ceph/

echo "removing existing loop devices"
# remove existing loop devices
sudo losetup -d ${OSD1_DEVICE}
sudo losetup -d ${OSD2_DEVICE}
sudo losetup -d ${OSD3_DEVICE}

echo "Clean up old disk files"
# Clean up old disks
for i in ceph{a..c}; do
  if [ -f ${DISKS_PATH}/$i ]; then
     rm ${DISKS_PATH}/$i
  fi
done

echo "Creating new disks"
# Create new disks
mkdir -p ${DISKS_PATH}
for i in ceph{a..c}; do
  fallocate -l ${OSD_SIZE} ${DISKS_PATH}/$i
done

echo "Creating new loop devices"
# Create new loop devives
j=0
for i in ceph{a..c}; do
  sudo losetup /dev/loop${j}  ${DISKS_PATH}/$i
  ((j++));
done

echo "Done!"
