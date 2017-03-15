#!/usr/bin/env bash

set -e

if [[ -z "$USERNAME" ]]; then
  echo "Must export the following:"
  echo "USERNAME - username of the created user"
  exit 1
fi

mkdir /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
cp /cdrom/preseed/id_rsa.pub /home/$USERNAME/.ssh/authorized_keys
chmod 600 /home/$USERNAME/.ssh/authorized_keys

