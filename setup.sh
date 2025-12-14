#!/bin/bash
SCRIPT_DATE=20251214-1236
set -e # Exit on error
LOG=/tmp/server.log
ERR=/tmp/server.err
SELECTIONS=/tmp/selections
echo ---------------------------------------------------------------------------
timedatectl set-timezone America/Argentina/Buenos_Aires
echo "now    $(date +'%Y%m%d-%H%M')"
echo "script $SCRIPT_DATE"
echo ---------------------------------------------------------------------------
echo "Installing dependencies for this script ---------------------"
        apt update                                                  >/dev/null 2>&1
        apt install dosfstools parted gnupg2 \
		    wget curl openssh-server multistrap \
		    netselect-apt btrfs-progs vim -y >/dev/null 2>&1
#####################################################################################################
#Selections
#####################################################################################################
if [ -f $SELECTIONS ] ; then
        echo Skiping questions, you may delete $SELECTIONS if you change your mind
        source $SELECTIONS
else
        reset
        #Finding Fastest repo in the background
        netselect-apt -n -s -a amd64 trixie 2>&1 | grep -A1 "fastest valid for http" | tail -n1 > /tmp/fastest_repo &
        REPOSITORY_DEB_PID=$!

        disk_list=$(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk"{print $1,$2}')
        menu_options=()
        while read -r name size; do
              menu_options+=("/dev/$name" "$size")
        done <<< "$disk_list"
        DEVICE=$(whiptail --title "Disk selection" --menu "Choose a disk from below and press enter to begin:" 20 60 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)

        #####################################################################################################
        username=$(whiptail --title "Local admin creation" --inputbox "Type a username:" 20 60  3>&1 1>&2 2>&3)
        REPEAT=yes
        while [ "$REPEAT" == "yes" ] ; do
                password=$( whiptail --title "Local admin creation" --passwordbox "Type a password:"                  20 60  3>&1 1>&2 2>&3)
                password2=$(whiptail --title "Local admin creation" --passwordbox "Just in case type it again:"       20 60  3>&1 1>&2 2>&3)
                if [ "$password" == "$password2" ] ; then
                        REPEAT=no
                else
                        #echo "ERROR: Passwords entered dont match"
                            whiptail --title "Local admin creation" \
                                     --msgbox "ERROR: Passwords dont match, try again" 20 60  3>&1 1>&2 2>&3
                fi
        done
        #####################################################################################################
        echo "Detecting fastest debian mirror, please wait ----------------"
        #Waiting to background process to finish
        wait $REPOSITORY_DEB_PID
        REPOSITORY_DEB_FAST=$(cat /tmp/fastest_repo)
        REPOSITORY_DEB_FAST=${REPOSITORY_DEB_FAST// /}
        REPOSITORY_DEB_STANDARD="http://deb.debian.org/debian/"
        REPOSITORY_DEB=$(whiptail --title "Debian respository" --menu "Choose one option:" 20 60 10 \
                           "${REPOSITORY_DEB_FAST}" "Fastest detected" \
                       "${REPOSITORY_DEB_STANDARD}" "Default Debian"   \
               3>&1 1>&2 2>&3)

        #####################################################################################################
        echo export DEVICE="$DEVICE"                            >  $SELECTIONS
        echo export username="$username"                        >> $SELECTIONS
        echo export password="$password"                        >> $SELECTIONS
        echo export REPOSITORY_DEB="${REPOSITORY_DEB}"          >> $SELECTIONS

fi

#####################################################################################################
#VARIABLES
#####################################################################################################

# Mount Points
CACHE_FOLDER=/tmp/resources-fs
ROOTFS=/tmp/os-rootfs
mkdir $CACHE_FOLDER $ROOTFS 2>/dev/null || true
cd /tmp

# Partition Fixed Sizes
	PART_EFI_SIZE=512 
	PART_OS_SIZE=95300
	PART_CZ_SIZE=10240
# Device Size
	DISK_SIZE=$(parted "${DEVICE}" --script unit MiB print | awk '/Disk/ {print $3}' | tr -d 'MiB')
# EFI Partition
	PART_EFI_START=1
	PART_EFI_END=$((PART_EFI_SIZE))
# OS Partition
	PART_OS_START=$((PART_EFI_END + 1))
	PART_OS_END=$((PART_OS_START + PART_OS_SIZE - 1))
# Clonezilla Parition
	PART_CZ_START=$((PART_OS_END + 1))
	PART_CZ_END=$((PART_CZ_START + PART_CZ_SIZE - 1))

# Overprovisioning Partition
	PART_REST_START=$((PART_CZ_END + 1))
	PART_REST_END=${DISK_SIZE}

# Cloning software for recovery partition
RECOVERYFS=/tmp/recovery-rootfs
CLONEZILLA_KEYBOARD=latam
DOWNLOAD_DIR_CLONEZILLA=${CACHE_FOLDER}/Clonezilla
BASEURL_CLONEZILLA_FAST="https://free.nchc.org.tw/clonezilla-live/stable/"
BASEURL_CLONEZILLA_SLOW="https://sourceforge.net/projects/clonezilla/files/latest/download"

# Apt certificate repository folder
APT_CONFIG="`command -v apt-config 2> /dev/null`"
eval $("$APT_CONFIG" shell APT_TRUSTEDDIR 'Dir::Etc::trustedparts/d')

# Apt packages list for installing with mmdebstrap
# NOTE: Fictional variables below are only for title purposes ########################################
INCLUDES_DEB="apt linux-image-amd64 initramfs-tools zstd gnupg systemd \
task-web-server task-ssh-server \
sudo vim wget curl \
network-manager iputils-ping util-linux iproute2 bind9-host isc-dhcp-client \
grub2-common grub-efi grub-efi-amd64 \
console-data console-setup locales \
nfs-kernel-server nfs-common \
atftpd \
isc-dhcp-server"

REPOSITORY_DEB="http://deb.debian.org/debian/"

DEBIAN_VERSION=bookworm

# For Cleaning Screen and progress bar
LOCALIP=$(ip -br a | grep -v ^lo | grep -i UP | awk '{print $3}' | cut -d\/ -f1)
export PROGRESS_BAR_MAX=17
export PROGRESS_BAR_WIDTH=17
export PROGRESS_BAR_CURRENT=0
########################################################################################################################################################
cleaning_screen (){
# for clear screen on tty (clear doesnt work)
printf "\033c"
echo "============================================================="
echo "Installing on Device ${DEVICE} with ${username} as local admin :
        - Debian ${DEBIAN_VERSION} from ${REPOSITORY_DEB} (FASTEST REPOSITORY at your location) with :
                - BTRFS, GRUB-BTRFS and Timeshift for snapshots of root file system.
                - Unattended upgrades, Virtual Machine Manager (KVM/QEMU).
To follow extra details, use: Alt plus left or right arrows"
grep iso /proc/cmdline >/dev/null && \
echo "For remote access during installation, you can connect remotely : ssh user@$LOCALIP (password is \"live\") "
######## PROGRESS BAR ###################################################
echo "============================================================="
set +e
if [ $PROGRESS_BAR_CURRENT -eq $PROGRESS_BAR_MAX ]; then
        let "PROGRESS_BAR_PERCENT = 100"
        let "PROGRESS_BAR_FILLED_LEN = PROGRESS_BAR_WIDTH"
else
        let "PROGRESS_BAR_PERCENT = PROGRESS_BAR_CURRENT * 100 / PROGRESS_BAR_MAX"
        let "PROGRESS_BAR_FILLED_LEN = PROGRESS_BAR_CURRENT * PROGRESS_BAR_WIDTH / PROGRESS_BAR_MAX"
fi
let "PROGRESS_BAR_EMPTY_LEN = PROGRESS_BAR_WIDTH - PROGRESS_BAR_FILLED_LEN"
PROGRESS_BAR_FILLED_BAR=$(printf "%${PROGRESS_BAR_FILLED_LEN}s" | tr ' ' '#')
PROGRESS_BAR_EMPTY_BAR=$(printf "%${PROGRESS_BAR_EMPTY_LEN}s" | tr ' ' '-')
printf "\rProgress: [%s%s] %3d%% \033[K" "$PROGRESS_BAR_FILLED_BAR" "$PROGRESS_BAR_EMPTY_BAR" "$PROGRESS_BAR_PERCENT"
let "PROGRESS_BAR_CURRENT += 1"
sleep 0.05
printf "\n=============================================================\n"
set -e
#########################################################################
}

cleaning_screen
echo "Inicializing logs tails -------------------------------------"
        touch $LOG
        touch $ERR
set +e
        # RUNNING TAILS ON SECOND AND THIRD TTYs
        if ! pgrep tail ; then
                setsid bash -c 'exec watch sudo fdisk -l                                                                                <> /dev/tty2 >&0 2>&1' &
                setsid bash -c 'exec watch sudo df -h                                                                                   <> /dev/tty3 >&0 2>&1' &
                setsid bash -c 'exec watch sudo lsblk -f                                                                                <> /dev/tty4 >&0 2>&1' &
                setsid bash -c 'exec tail -f '$LOG'                                                                                     <> /dev/tty5 >&0 2>&1' &
                setsid bash -c 'exec tail -f '$ERR'                                                                                     <> /dev/tty6 >&0 2>&1' &
        fi
set -e

cleaning_screen
echo "Unmounting ${DEVICE}  ----------------------------------------"
        umount ${DEVICE}*               2>/dev/null || true
        umount ${ROOTFS}/dev/pts        2>/dev/null || true
        umount ${ROOTFS}/dev            2>/dev/null || true
        umount ${ROOTFS}/proc           2>/dev/null || true
        umount ${ROOTFS}/run            2>/dev/null || true
        umount ${ROOTFS}/sys            2>/dev/null || true
        umount ${ROOTFS}/tmp            2>/dev/null || true
        umount ${ROOTFS}/boot/efi       2>/dev/null || true
        umount ${ROOTFS}${CACHE_FOLDER} 2>/dev/null || true
        umount ${ROOTFS}                2>/dev/null || true

cleaning_screen
echo "Setting partition table to GPT (UEFI) -----------------------"
        parted ${DEVICE} --script mktable gpt                   > /dev/null 2>&1

cleaning_screen
echo "Creating EFI partition --------------------------------------"
        parted ${DEVICE} --script mkpart EFI fat32 ${PART_EFI_START}MiB ${PART_EFI_END}MiB   > /dev/null 2>&1
        parted ${DEVICE} --script set 1 esp on                               > /dev/null 2>&1

cleaning_screen	
echo "Creating OS partition ---------------------------------------"
        parted "${DEVICE}" --script mkpart LINUX btrfs ${PART_OS_START}MiB ${PART_OS_END}MiB    # >/dev/null 2>&1
        sleep 2

cleaning_screen	
echo "Creating Clonezilla partition -------------------------------"
        parted "${DEVICE}" --script mkpart CLONEZILLA ext4 ${PART_CZ_END}MiB ${PART_CZ_END}MiB # > /dev/null 2>&1

cleaning_screen	
echo "Creating Overprovisioning partition -------------------------------"
        parted "${DEVICE}" --script mkpart RESOURCES ext4 ${PART_CZ_END}MiB ${PART_CZ_END}MiB # > /dev/null 2>&1


cleaning_screen
echo "Formating partitions ----------------------------------------"
        if echo ${DEVICE} | grep -i nvme > /dev/null ; then
                DEVICE=${DEVICE}p
        fi
	# EVEN IF THE PARTITION IS FORMATTED I TRY TO CHECK THE FILESYSTEM
	fsck -y "${DEVICE}"1                           >/dev/null 2>&1 || true
	fsck -y "${DEVICE}"2                           >/dev/null 2>&1 || true
	fsck -y "${DEVICE}"3                           >/dev/null 2>&1 || true
	fsck -y "${DEVICE}"4                           >/dev/null 2>&1 || true
	mkfs.vfat  -n EFI        "${DEVICE}"1 -F                       || true
	mkfs.btrfs -L LINUX      "${DEVICE}"2 -f                       || true
	mkfs.ext4  -L CLONEZILLA "${DEVICE}"3 -F                       || true
	mkfs.ext4  -L RESOURCES  "${DEVICE}"4 -F                       || true

cleaning_screen
echo "Mounting OS partition ---------------------------------------"
        mkdir -p ${ROOTFS}                                      > /dev/null 2>&1
        mount ${DEVICE}2 ${ROOTFS}                              > /dev/null 2>&1
        mkdir -p ${ROOTFS}${CACHE_FOLDER}                       > /dev/null 2>&1
        mount --bind ${CACHE_FOLDER} ${ROOTFS}${CACHE_FOLDER}

cleaning_screen
echo "Creating configuration file for multistrap ------------------"
echo "[General]
arch=amd64
directory=${ROOTFS}
cleanup=false
unpack=true
omitdebsrc=true
bootstrap=Debian
aptsources=Debian

[Debian]
packages=${INCLUDES_DEB}
source=${REPOSITORY_DEB}
keyring=debian-archive-keyring
suite=${DEBIAN_VERSION}
components=main contrib non-free non-free-firmware" > multistrap.conf

cleaning_screen
echo "Running multistrap ------------------------------------------"
        SILENCE="Warning: unrecognised value 'no' for Multi-Arch field in|multistrap-googlechrome.list"
        multistrap -f multistrap.conf >$LOG 2> >(grep -vE "$SILENCE" > $ERR)

cleaning_screen
echo "Configurating the network -----------------------------------"
        cp /etc/resolv.conf ${ROOTFS}/etc/resolv.conf
        mkdir -p ${ROOTFS}/etc/network/interfaces.d/            > /dev/null 2>&1
        echo "allow-hotplug enp1s0"                          > ${ROOTFS}/etc/network/interfaces.d/enp1s0
        echo "iface enp1s0 inet dhcp"                       >> ${ROOTFS}/etc/network/interfaces.d/enp1s0
        echo "debian-$(date +'%Y-%m-%d')"                    > ${ROOTFS}/etc/hostname
        echo "127.0.0.1       localhost"                     > ${ROOTFS}/etc/hosts
        echo "127.0.1.1       debian-$(date +'%Y-%m-%d')"   >> ${ROOTFS}/etc/hosts
        echo "::1     localhost ip6-localhost ip6-loopback" >> ${ROOTFS}/etc/hosts
        echo "ff02::1 ip6-allnodes"                         >> ${ROOTFS}/etc/hosts
        echo "ff02::2 ip6-allrouters"                       >> ${ROOTFS}/etc/hosts
        touch ${ROOTFS}/ImageDate.$(date +'%Y-%m-%d')

cleaning_screen
echo "Mounting EFI partition --------------------------------------"
        mkdir -p ${ROOTFS}/boot/efi
        mount ${DEVICE}1 ${ROOTFS}/boot/efi

cleaning_screen
echo "Generating fstab --------------------------------------------"
        root_uuid="$(blkid | grep ^$DEVICE | grep ' LABEL="LINUX" ' | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        efi_uuid="$(blkid  | grep ^$DEVICE | grep ' LABEL="EFI" '   | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        FILE=${ROOTFS}/etc/fstab
        echo "$root_uuid /        btrfs defaults 0 1"  > $FILE
        echo "$efi_uuid  /boot/efi vfat defaults 0 1" >> $FILE

cleaning_screen
echo "Getting ready for chroot ------------------------------------"
        mount --bind /dev ${ROOTFS}/dev
        mount -t devpts /dev/pts ${ROOTFS}/dev/pts
        mount --bind /proc ${ROOTFS}/proc
        mount --bind /run  ${ROOTFS}/run
        mount -t sysfs sysfs ${ROOTFS}/sys
        mount -t tmpfs tmpfs ${ROOTFS}/tmp

cleaning_screen
echo "Setting Keyboard maps for non graphical console -------------"
        # FIX DEBIAN BUG
        keyboard_maps=$(curl -s https://mirrors.edge.kernel.org/pub/linux/utils/kbd/ | grep tar.gz | cut -d'"' -f2 | tail -n1)
        where_am_i=$PWD
        wget -O $keyboard_maps https://mirrors.edge.kernel.org/pub/linux/utils/kbd/$keyboard_maps >>$LOG 2>>$ERR
        cd /tmp
        tar xzvf $where_am_i/$keyboard_maps   >>$LOG 2>>$ERR
        cd kbd-*/data/keymaps/
        mkdir -p ${ROOTFS}/usr/share/keymaps/
        cp -r * ${ROOTFS}/usr/share/keymaps/  >>$LOG 2>>$ERR

cleaning_screen
echo "Entering chroot ---------------------------------------------"
        echo "#!/bin/bash
        export DOWNLOAD_DIR=${DOWNLOAD_DIR}
        export VERSION=${VERSION}
        export LO_LANG=es  # Idioma para la instalación
        export LC_ALL=C LANGUAGE=C LANG=C
        export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true

        PROC_NEEDS_UMOUNT=0
        if [ ! -e /proc/uptime ]; then
                mount proc -t proc /proc
                PROC_NEEDS_UMOUNT=1
        fi

        echo Setting up additional packages ------------------------------
        tasksel install ssh-server web-server --new-install                              >>$LOG 2>/dev/null

        echo Installing grub ---------------------------------------------
        update-initramfs -c -k all                                                              >/dev/null 2>&1
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram --removable  >/dev/null 2>&1
        update-grub                                                                             >/dev/null 2>&1

        if [ \$PROC_NEEDS_UMOUNT -eq 1 ]; then
                umount /proc
        fi

        echo Setting languaje --------------------------------------------
        debconf-set-selections <<< \"tzdata                  tzdata/Areas                                              select America\"
        debconf-set-selections <<< \"tzdata                  tzdata/Zones/America                                      select Argentina/Buenos_Aires\"
        debconf-set-selections <<< \"console-data  console-data/keymap/policy      select  Select keymap from full list\"
        debconf-set-selections <<< \"console-data  console-data/keymap/full        select  la-latin1\"
        debconf-set-selections <<< \"console-data  console-data/bootmap-md5sum     string  102c60ee2ad4688765db01cfa2d2da21\"
        debconf-set-selections <<< \"console-setup console-setup/charmap47 select  UTF-8\"
        debconf-set-selections <<< \"console-setup   console-setup/codeset47 select  Guess optimal character set\"
        debconf-set-selections <<< \"console-setup   console-setup/fontface47        select  Fixed\"
        debconf-set-selections <<< \"console-setup   console-setup/fontsize-fb47     select  8x16\"
        debconf-set-selections <<< \"console-setup   console-setup/fontsize  string  8x16\"
        debconf-set-selections <<< \"console-setup   console-setup/fontsize-text47   select  8x16\"
        debconf-set-selections <<< \"keyboard-configuration  keyboard-configuration/model    select  PC genérico 105 teclas\"
        debconf-set-selections <<< \"keyboard-configuration        keyboard-configuration/layout   select  Spanish (Latin American)\"
        debconf-set-selections <<< \"keyboard-configuration        keyboard-configuration/layoutcode       string  latam\"
        debconf-set-selections <<< \"keyboard-configuration        keyboard-configuration/variant  select  Spanish (Latin American)\"
        debconf-set-selections <<< \"keyboard-configuration  keyboard-configuration/altgr    select  The default for the keyboard layout\"
        debconf-set-selections <<< \"keyboard-configuration  keyboard-configuration/compose  select  No compose key\"
        debconf-set-selections <<< \"locales       locales/locales_to_be_generated multiselect     es_AR.UTF-8 UTF-8\"

        rm -f /etc/localtime /etc/timezone
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive tzdata
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-data
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive console-setup
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive keyboard-configuration
        sed -i '/# es_AR.UTF-8 UTF-8/s/^# //g' /etc/locale.gen
        locale-gen >/dev/null
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive locales
        update-locale LANG=es_AR.UTF-8 >/dev/null
        locale

        exit" > ${ROOTFS}/root/chroot.sh
        chmod +x ${ROOTFS}/root/chroot.sh
        chroot ${ROOTFS} /bin/bash /root/chroot.sh

cleaning_screen
echo "Setting up local admin account ------------------------------"
        echo "export LC_ALL=C LANGUAGE=C LANG=C
        useradd -d /home/$username -G sudo -m -s /bin/bash $username
        echo ${username}:${password} | chpasswd
        rm /tmp/local_admin.sh" > ${ROOTFS}/tmp/local_admin.sh
        chmod +x ${ROOTFS}/tmp/local_admin.sh
        chroot ${ROOTFS} /bin/bash /tmp/local_admin.sh

cleaning_screen
echo "Unmounting ${DEVICE} -----------------------------------------"
        umount ${DEVICE}*                2>/dev/null || true
        umount ${ROOTFS}/dev/pts         2>/dev/null || true
        umount ${ROOTFS}/dev             2>/dev/null || true
        umount ${ROOTFS}/proc            2>/dev/null || true
        umount ${ROOTFS}/run             2>/dev/null || true
        umount ${ROOTFS}/sys             2>/dev/null || true
        umount ${ROOTFS}/tmp             2>/dev/null || true
        umount ${ROOTFS}/boot/efi        2>/dev/null || true
        umount ${ROOTFS}${CACHE_FOLDER}  2>/dev/null || true
        umount ${ROOTFS}                 2>/dev/null || true

PROGRESS_BAR_CURRENT=$PROGRESS_BAR_MAX
PROGRESS_BAR_FILLED_LEN=$PROGRESS_BAR_CURRENT
PROGRESS_BAR_EMPTY_LEN=0

cleaning_screen
echo "END of the road!! keep up the good work ---------------------"
