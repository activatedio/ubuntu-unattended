#!/usr/bin/env bash

set -e

iso=$1

if [ -z "$iso" ]; then
  echo "Syntax: test.sh [path to iso]"
  echo "e.g.    test.sh /tmp/ubuntu-16.04.2-server-amd64-unattended.iso"
  exit 1
fi

now=`date +%s`
hda=/tmp/${now}-test.img

qemu-img create -f qcow2 $hda 10G

qemu-system-x86_64 --enable-kvm -hda $hda -cdrom $iso -boot d -m 512
