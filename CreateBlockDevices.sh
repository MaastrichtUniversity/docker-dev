#!/bin/bash

fallocate -l 100M ./volumes_data/ceph/cepha
fallocate -l 100M ./volumes_data/ceph/cephb
fallocate -l 100M ./volumes_data/ceph/cephc

sudo mknod /dev/cepha b 7 200
sudo mknod /dev/cephb b 7 201
sudo mknod /dev/cephc b 7 202

sudo losetup /dev/cepha  ./volumes_data/ceph/cepha
sudo losetup /dev/cephb  ./volumes_data/ceph/cephb
sudo losetup /dev/cephc  ./volumes_data/ceph/cephc
