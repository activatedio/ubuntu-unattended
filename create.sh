#!/usr/bin/env bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# file names & paths
tmp="/tmp"  # destination folder to store the final iso file
hostname="ubuntu"
# TODO - this is imperfect
currentuser="$SUDO_USER"
sshkey="/home/$currentuser/.ssh/id_rsa.pub"

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

select_disk=$DEVICE

if [ -z "$select_disk" ]; then
  select_disk='/dev/sda'
fi

select_disk_equals=`echo $select_disk | sed -r 's/\//=/g'`

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
late_command="cp /target/media/cdrom/preseed/late.sh /target/tmp; in-target /tmp/late.sh;"

sshkey_contents=`cat $sshkey`

cat << EOF > $tmp/iso_new/preseed/late.sh
#!/usr/bin/env bash

set -e

mkdir /home/$username/.ssh
chmod 700 /home/$username/.ssh
echo "$sshkey_contents" > /home/$username/.ssh/authorized_keys
chmod 600 /home/$username/.ssh/authorized_keys
chown -R $username:$username /home/$username/.ssh
echo "$username ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/020_${username}-nopasswd
chmod 440 /etc/sudoers.d/020_${username}-nopasswd
sed -i 's/GRUB_HIDDEN_TIMEOUT=0/GRUB_HIDDEN_TIMEOUT=5/' /etc/default/grub
sed -i 's/GRUB_HIDDEN_TIMEOUT_QUIET=true/GRUB_HIDDEN_TIMEOUT_QUIET=false/' /etc/default/grub
sed -i 's/vt_handoff="1"/vt_handoff="0"/' /etc/grub.d/10_linux 
update-grub
EOF

chmod 755 $tmp/iso_new/preseed/late.sh
 
cat << EOF > $tmp/iso_new/preseed/preseed.cfg
# general options
d-i debconf/priority                                        string      critical

# regional setting
d-i debian-installer/language                               string      en_US:en
d-i debian-installer/country                                string      US
d-i debian-installer/locale                                 string      en_US
d-i debian-installer/splash                                 boolean     false
d-i localechooser/supported-locales                         multiselect en_US.UTF-8
d-i pkgsel/install-language-support                         boolean     true

# keyboard selection
d-i console-setup/ask_detect                                boolean     false
d-i keyboard-configuration/modelcode                        string      pc105
d-i keyboard-configuration/layoutcode                       string      us
d-i keyboard-configuration/variantcode                      string      intl
d-i keyboard-configuration/xkb-keymap                       select      us(intl)
d-i debconf/language                                        string      en_US:en

# network settings
d-i netcfg/choose_interface                                 select      auto
d-i netcfg/dhcp_timeout                                     string      5
d-i netcfg/get_hostname                                     string      ${hostname}
d-i netcfg/get_domain                                       string      ${hostname}

# mirror settings
d-i mirror/country                                          string      manual
d-i mirror/http/hostname                                    string      archive.ubuntu.com
d-i mirror/http/directory                                   string      /ubuntu
d-i mirror/http/proxy                                       string

# clock and timezone settings
d-i time/zone                                               string      ${timezone}
d-i clock-setup/utc                                         boolean     false
d-i clock-setup/ntp                                         boolean     true

# user account setup
d-i passwd/root-login                                       boolean     false
d-i passwd/make-user                                        boolean     true
d-i passwd/user-fullname                                    string      ${username}
d-i passwd/username                                         string      ${username}
d-i passwd/user-password-crypted                            password    !
d-i user-setup/encrypt-home                                 boolean     false

# configure apt
d-i apt-setup/restricted                                    boolean     true
d-i apt-setup/universe                                      boolean     true
d-i apt-setup/backports                                     boolean     true
d-i apt-setup/services-select                               multiselect security
d-i apt-setup/security_host                                 string      security.ubuntu.com
d-i apt-setup/security_path                                 string      /ubuntu
tasksel tasksel/first                                       multiselect Basic Ubuntu server
d-i pkgsel/include                                          string      openssh-server
d-i pkgsel/upgrade                                          select      safe-upgrade
d-i pkgsel/update-policy                                    select      none
d-i pkgsel/updatedb                                         boolean     true

# disk partitioning
d-i partman/confirm_write_new_label                         boolean     true
d-i partman/choose_partition                                select      finish
d-i partman/confirm_nooverwrite                             boolean     true
d-i partman/confirm                                         boolean     true
d-i partman-auto/purge_lvm_from_device                      boolean     true
d-i partman-lvm/device_remove_lvm                           boolean     true
d-i partman-lvm/confirm                                     boolean     true
d-i partman-lvm/confirm_nooverwrite                         boolean     true
d-i partman-auto-lvm/no_boot                                boolean     true
d-i partman-md/device_remove_md                             boolean     true
d-i partman-md/confirm                                      boolean     true
d-i partman-md/confirm_nooverwrite                          boolean     true
d-i partman-auto/method                                     string      lvm
d-i partman-auto-lvm/guided_size                            string      max
d-i partman-partitioning/confirm_write_new_label            boolean     true
partman-auto partman-auto/select_disk                       select      /var/lib/partman/devices/${select_disk_equals}
d-i partman/early_command                                   string      debconf-set partman-auto/disk "\$(list-devices disk | head -n1)"; pvremove -y -ff \`list-devices disk | head -n1\`* || true

# grub boot loader
d-i grub-installer/only_debian                              boolean     true
d-i grub-installer/with_other_os                            boolean     true
d-i grub-installer/bootdev                                  string      ${select_disk}

# finish installation
d-i finish-install/reboot_in_progress                       note
d-i cdrom-detect/eject                                      boolean     true
d-i debian-installer/exit/halt                              boolean     false
d-i debian-installer/exit/poweroff                          boolean     true
EOF

# include firstrun script
echo "
# setup firstrun script
d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file

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

if [ -z "$WRITE_TO" ]; then
  exit 0
fi

df -H | grep $WRITE_TO | awk '{ print $1 }' | xargs -r sudo umount

dd if=$tmp/$new_iso_name of=$WRITE_TO bs=4M
sync

echo "Wrote to device $WRITE_TO. Now safe to remove"


