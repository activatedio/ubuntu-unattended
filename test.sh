#!/usr/bin/env bash

set -e

iso=$1

if [ -z "$iso" ]; then
  echo "Syntax: test.sh [path to iso]"
  echo "e.g.    test.sh /tmp/ubuntu-16.04.2-server-amd64-unattended.iso"
  exit 1
fi

user=$(whoami)
now=`date +%s`
hda=/tmp/${now}-test.img
netdev=tap$now

sudo tunctl -u $user -t $netdev
sudo ip link set $netdev up
sudo brctl addif virbr0 $netdev

qemu-img create -f qcow2 $hda 10G

qemu-system-x86_64 --enable-kvm -cdrom $iso -boot d -m 512 -device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0 -drive file=$hda,format=qcow2,if=none,id=drive-virtio-disk0 -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:01:02:03,bus=pci.0,addr=0x3 -netdev type=tap,id=net0,ifname=$netdev,script=no,downscript=no

# Run the same without the cdrom
qemu-system-x86_64 --enable-kvm -m 512 -device virtio-blk-pci,scsi=off,bus=pci.0,addr=0x4,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 -drive file=$hda,format=qcow2,if=none,id=drive-virtio-disk0 -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:01:02:03,bus=pci.0,addr=0x3 -netdev type=tap,id=net0,ifname=$netdev,script=no,downscript=no

