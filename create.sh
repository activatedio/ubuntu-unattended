#!/usr/bin/env bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# file names & paths
tmp="/tmp"  # destination folder to store the final iso file
hostname="ubuntu"
# TODO - this is imperfect
currentuser="$SUDO_USER"
sshkey="$HOME/.ssh/id_rsa.pub"

if [[ ! -e "$sshkey" ]]; then
  echo "SSH key must first be generated via ssh-keygen"
  exit 1
fi

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

#get the latest versions of Ubuntu LTS

tmphtml=$tmp/tmphtml
rm $tmphtml || true
wget -O $tmphtml 'http://releases.ubuntu.com/'
xenn=$(fgrep Xenial $tmphtml | head -1 | awk '{print $3}')
download_file="ubuntu-$xenn-server-amd64.iso"
download_location="http://releases.ubuntu.com/$xenn/"
new_iso_name="ubuntu-$xenn-server-amd64-unattended.iso"
timezone=`cat /etc/timezone`
username=$currentuser
bootable=yes
seed_file="preseed.cfg"
seed_path="$DIR/$seed_file"

# download the ubunto iso. If it already exists, do not delete in the end.
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
	echo "Error: Failed to download ISO: $download_location$download_file"
	echo "This file may have moved or may no longer exist."
	echo
	echo "You can download it manually and move it to $tmp/$download_file"
	echo "Then run this script again."
	exit 1
fi

# create working folders
echo " remastering your iso file"
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    mount -o loop $tmp/$download_file $tmp/iso_org
fi

cp -rT $tmp/iso_org $tmp/iso_new

cd $tmp/iso_new
echo en > $tmp/iso_new/isolinux/lang

sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp/iso_new/isolinux/isolinux.cfg

# set late command

late_command="in-target /cdrom/preseed.late.sh;"

cp $seed_path $tmp/iso_new/preseed/preseed.cfg
cp $sshkey $tmp/iso_new/preseed/id_rsa.pub
cp $DIR/late.sh $tmp/iso_new/preseed/late.sh
chmod 755 $tmp/iso_new/preseed/late.sh

# include firstrun script
echo "
# setup firstrun script
d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Activated Autoinstall Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/$seed_file preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
mkisofs -D -r -V "ACTIVATED_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . 

isohybrid $tmp/$new_iso_name

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml

# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

