#!/bin/bash

source .env

# Create dirs

if [[ ! -e ${VOLUMES_PATH} ]]; then
  echo "Creating ${VOLUMES_PATH}"
  mkdir -p ${VOLUMES_PATH}
fi

if [[ ! -e ${DISKS_PATH} ]]; then
  echo "Creating ${DISKS_PATH}"
  mkdir -p ${DISKS_PATH}
fi

# remove previous Ceph config
echo "Removing old Ceph config from ${VOLUMES_PATH}/ceph/"
sudo rm -rf ${VOLUMES_PATH}/ceph/

echo "removing existing loop devices"
osd_devices=(${OSD1_DEVICE} ${OSD2_DEVICE} ${OSD3_DEVICE})
# remove existing loop devices
for i in ${osd_devices[@]}; do
    sudo losetup -d $i
done

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
  sudo losetup ${osd_devices[${j}]}  ${DISKS_PATH}/$i
  ((j++));
done

echo "Done!"
