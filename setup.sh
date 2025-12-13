#!/bin/bash
#VARIABLES
if [ -z $1 ] ; then
        echo Usage: "time sudo $0 /dev/vdb"
        exit
fi

set -e # Exit on error
cd /tmp
DEVICE=$1
CACHE_FOLDER=/var/cache/apt/archives
LOG=${CACHE_FOLDER}/multistrap.log
ERR=${CACHE_FOLDER}/multistrap.err
ROOTFS=/tmp/installing-rootfs
APT_CONFIG="`command -v apt-config 2> /dev/null`"
eval $("$APT_CONFIG" shell APT_TRUSTEDDIR 'Dir::Etc::trustedparts/d')

INCLUDES_DEB="apt linux-image-amd64 initramfs-tools zstd gnupg systemd \
xfce4 xfce4-goodies task-xfce-desktop xorg dbus-x11 \
task-web-server task-ssh-server task-laptop \
sudo vim wget curl \
network-manager iputils-ping util-linux iproute2 bind9-host isc-dhcp-client \
grub2-common grub-efi grub-efi-amd64 \
fonts-liberation libasound2 libnspr4 libnss3 libvulkan1 \
console-data console-setup locales \
libxslt1.1"
#Kernel, initrd, basics
#xfce, x11
#tools
#network
#boot
#chrome deps
#idioma e idioma terminal tty
#libreoffice

INCLUDES_X2GO="x2goserver x2goserver-xsession x2go-keyring"
REPOSITORY_DEB="http://deb.debian.org/debian/"
REPOSITORY_X2GO="http://packages.x2go.org/debian/"
REPOSITORY_CHROME="https://dl.google.com/linux/chrome/deb/"

DEBIAN_VERSION=bookworm

echo "Making script backup ----------------------------------------"
        cp $0 $0.$(date +'%Y%m%d-%H%M')
        chown $SUDO_USER: $0.*
        if [ $(ls $0.$(date +'%Y%m%d')* | wc -l) == "1" ] ; then
                echo ----First run of today, cleaning ${CACHE_FOLDER}
                rm -rf ${CACHE_FOLDER}/*
        fi

echo "Installing dependencies for this script ---------------------"
        apt update                                                  >/dev/null 2>&1
        apt install dosfstools parted btrfs-progs vim multistrap wget curl gnupg2 -y >/dev/null 2>&1

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

echo "Setting partition table to GPT (UEFI) -----------------------"
        parted ${DEVICE} --script mktable gpt                   > /dev/null 2>&1

echo "Creating EFI partition --------------------------------------"
        parted ${DEVICE} --script mkpart EFI fat16 1MiB 10MiB   > /dev/null 2>&1
        parted ${DEVICE} --script set 1 msftdata on             > /dev/null 2>&1

echo "Creating OS partition ---------------------------------------"
        parted ${DEVICE} --script mkpart LINUX btrfs 10MiB 100% > /dev/null 2>&1
        sleep 2

echo "Formating partitions ----------------------------------------"
        mkfs.vfat -n EFI ${DEVICE}1                             > /dev/null 2>&1
        mkfs.btrfs -f -L LINUX ${DEVICE}2                       > /dev/null 2>&1

echo "Mounting OS partition ---------------------------------------"
        mkdir -p ${ROOTFS}                                      > /dev/null 2>&1
        mount ${DEVICE}2 ${ROOTFS}                              > /dev/null 2>&1
        mkdir -p ${ROOTFS}${CACHE_FOLDER}                       > /dev/null 2>&1
        mount --bind ${CACHE_FOLDER} ${ROOTFS}${CACHE_FOLDER}

echo "Downloading x2go and Google Chrome keyrings -----------------"
        echo ---------Creating Directories in ${ROOTFS}
        #mkdir -p ${ROOTFS}/usr/share/keyrings/    
        mkdir -p ${ROOTFS}/etc/apt/sources.list.d/
        mkdir -p ${ROOTFS}${APT_TRUSTEDDIR}  

        #X2GO
        echo ---------Installing x2go keyring here
        set +e
        gpg --keyserver keyserver.ubuntu.com --recv-keys E1F958385BFE2B6E            > /dev/null 2>&1
        set -e
        gpg --export E1F958385BFE2B6E | tee /usr/share/keyrings/x2go-keyring.gpg     >       /usr/share/keyrings/x2go-keyring.gpg
        echo deb [trusted=yes] https://packages.x2go.org/debian bookworm extras main >          /etc/apt/sources.list.d/x2go.list

        echo ---------Installing x2go keyring in ${ROOTFS}
        set +e
        gpg --keyserver keyserver.ubuntu.com --recv-keys E1F958385BFE2B6E            > /dev/null 2>&1
        set -e
        gpg --export E1F958385BFE2B6E |  tee /usr/share/keyrings/x2go-keyring.gpg    > ${ROOTFS}${APT_TRUSTEDDIR}x2go-keyring.gpg
        echo deb [trusted=yes] https://packages.x2go.org/debian bookworm extras main > ${ROOTFS}/etc/apt/sources.list.d/multistrap-x2go.list

        #CHROME
        echo ---------Installing chrome keyring here
        wget -qO - https://dl.google.com/linux/linux_signing_key.pub \
        | awk '/-----BEGIN PGP PUBLIC KEY BLOCK-----/ {inBlock++} inBlock == 2 {print} /-----END PGP PUBLIC KEY BLOCK-----/ && inBlock == 2 {exit}' \
        | gpg --dearmor >          ${APT_TRUSTEDDIR}google-chrome.gpg
        echo deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main    >          /etc/apt/sources.list.d/google-chrome.list

        echo ---------Installing chrome keyring in ${ROOTFS}
        wget -qO - https://dl.google.com/linux/linux_signing_key.pub \
        | awk '/-----BEGIN PGP PUBLIC KEY BLOCK-----/ {inBlock++} inBlock == 2 {print} /-----END PGP PUBLIC KEY BLOCK-----/ && inBlock == 2 {exit}' \
        | gpg --dearmor > ${ROOTFS}${APT_TRUSTEDDIR}google-chrome.gpg
        echo deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main    > ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list

echo "Creating configuration file for multistrap ------------------"
echo "[General]
arch=amd64
directory=${ROOTFS}
cleanup=false
unpack=true
omitdebsrc=true
bootstrap=Debian X2Go GoogleChrome
aptsources=Debian X2go

[Debian]
packages=${INCLUDES_DEB}
source=${REPOSITORY_DEB}
keyring=debian-archive-keyring
suite=${DEBIAN_VERSION}
components=main contrib non-free non-free-firmware

[GoogleChrome]
arch=amd64
packages=google-chrome-stable
source=${REPOSITORY_CHROME}
suite=stable
noauth=true

[X2Go]
packages=${INCLUDES_X2GO}
source=${REPOSITORY_X2GO}
suite=${DEBIAN_VERSION}
#noauth=true
components=main" > multistrap.conf

echo "Running multistrap ------------------------------------------"
        SILENCE="Warning: unrecognised value 'no' for Multi-Arch field in|multistrap-googlechrome.list"
        multistrap -f multistrap.conf >$LOG 2> >(grep -vE "$SILENCE" > $ERR)
        #FIXES
        if [ -f ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list ] ; then
                rm ${ROOTFS}/etc/apt/sources.list.d/multistrap-googlechrome.list
        fi

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

echo "Mounting EFI partition --------------------------------------"
        mkdir -p ${ROOTFS}/boot/efi
        mount ${DEVICE}1 ${ROOTFS}/boot/efi

echo "Generating fstab --------------------------------------------"
        root_uuid="$(blkid | grep ^$DEVICE | grep ' LABEL="LINUX" ' | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        efi_uuid="$(blkid  | grep ^$DEVICE | grep ' LABEL="EFI" '   | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
        FILE=${ROOTFS}/etc/fstab
        echo "$root_uuid /        btrfs defaults 0 1"  > $FILE
        echo "$efi_uuid  /boot/efi vfat defaults 0 1" >> $FILE


echo "Getting ready for chroot ------------------------------------"
        mount --bind /dev ${ROOTFS}/dev
        mount -t devpts /dev/pts ${ROOTFS}/dev/pts
        mount --bind /proc ${ROOTFS}/proc
        mount --bind /run  ${ROOTFS}/run
        mount -t sysfs sysfs ${ROOTFS}/sys
        mount -t tmpfs tmpfs ${ROOTFS}/tmp

echo "Downloading Libreoffice -------------------------------------"
        # Variables
        LO_LANG=es  # Idioma para la instalación
        DOWNLOAD_DIR=${CACHE_FOLDER}/Libreoffice
        LIBREOFFICE_URL="https://download.documentfoundation.org/libreoffice/stable/"
        VERSION=$(wget -qO- $LIBREOFFICE_URL | grep -oP '[0-9]+(\.[0-9]+)+' | sort -V | tail -1)

        mkdir -p $DOWNLOAD_DIR >/dev/null 2>&1
        wget -qN ${LIBREOFFICE_URL}${VERSION}/deb/x86_64/LibreOffice_${VERSION}_Linux_x86-64_deb.tar.gz -P $DOWNLOAD_DIR
        wget -qN ${LIBREOFFICE_URL}${VERSION}/deb/x86_64/LibreOffice_${VERSION}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz -P $DOWNLOAD_DIR
        tar -xzf $DOWNLOAD_DIR/LibreOffice_${VERSION}_Linux_x86-64_deb.tar.gz -C $DOWNLOAD_DIR
        tar -xzf $DOWNLOAD_DIR/LibreOffice_${VERSION}_Linux_x86-64_deb_langpack_$LO_LANG.tar.gz -C $DOWNLOAD_DIR

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

echo "Copying skel, defaults and crontab --------------------------"
        cp -pR /etc/crontab /etc/skel ${ROOTFS}/etc/
        cp -p /etc/default/keyboard /etc/default/locale /etc/default/console-setup ${ROOTFS}/etc/default/

echo "Fixing XFCE on X2Go by disabling compositing ----------------"
        FILE=${ROOTFS}/etc/xdg/autostart/xcompose_disable.desktop
        mkdir -p ${ROOTFS}/etc/xdg/autostart/
        echo "[Desktop Entry]"                                                           >$FILE
        echo "Type=Application"                                                         >>$FILE
        echo "Name=XCompose Disable"                                                    >>$FILE
        echo "Icon=preferences-desktop-screensaver"                                     >>$FILE
        echo "Exec=/usr/bin/xfconf-query -c xfwm4 -p /general/use_compositing -s false" >>$FILE
        echo "OnlyShowIn=XFCE;"                                                         >>$FILE

echo "Disabling annoying X2Go features ----------------------------"
        echo ---BYEBYE CONTROL ALT T
        sed -i '/close_session/d' ${ROOTFS}/etc/x2go/keystrokes.cfg
        echo ---BYEBYE upper right corner clic to minimize x2go AKA magicpixel
        sed -i '/X2GO_NXAGENT_DEFAULT_OPTIONS/ s/"$/ -nomagicpixel"/' ${ROOTFS}/etc/x2go/x2goagent.options

echo "Generating rc.local for simple start up scripts -------------"
        FILE=${ROOTFS}/etc/systemd/system/rc-local.service
        echo [Unit]                                      >$FILE
        echo  Description=/etc/rc.local Compatibility   >>$FILE
        echo  ConditionPathExists=/etc/rc.local         >>$FILE
        echo [Service]                                  >>$FILE
        echo  Type=forking                              >>$FILE
        echo  ExecStart=/etc/rc.local                   >>$FILE
        echo  TimeoutSec=0                              >>$FILE
        echo  StandardOutput=tty                        >>$FILE
        echo  RemainAfterExit=yes                       >>$FILE
        echo  SysVStartPriority=99                      >>$FILE
        echo [Install]                                  >>$FILE
        echo  WantedBy=multi-user.target                >>$FILE
        printf '%s\n' '#!/bin/bash' \
                      'mount -a' \
                      'exit 0' > ${ROOTFS}/etc/rc.local
        chmod +x ${ROOTFS}/etc/rc.local


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
        tasksel install ssh-server laptop web-server --new-install                              >>$LOG 2>/dev/null

        #Installing Libreoffice and Google Chrome in backgroupd
        dpkg -i \$(find \$DOWNLOAD_DIR/ -type f -name \*.deb)                                   >>$LOG 2>&1 &
        pid_LO=$!

        echo Installing grub ---------------------------------------------
        update-initramfs -c -k all                                                              >/dev/null 2>&1
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram --removable  >/dev/null 2>&1
        update-grub                                                                             >/dev/null 2>&1

        echo Adding local user -------------------------------------------
        read -p \"What username do you want?: \" username
        useradd -d /home/\$username -c local_admin_user -G sudo -m -s /bin/bash \$username
        
        passwd \$username
        if [ \"\$?\" != \"0\" ] ; then echo Please repeat the password....; passwd \$username ; fi

        echo Installing LibreOffice and its language pack ----------------
        wait $pid_LO
        apt install --fix-broken -y                                                             >>$LOG 2>&1
        echo LibreOffice \$VERSION installation done.


        echo Listing relevant packages -----------------------------------
        dpkg -l | grep -v ^ii                        | grep -vE '^Des|^\| |^\|/'
        dpkg -l | grep -iE 'x2go|google|libreoffice' | grep -vE '^Des|^\| |^\|/'


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
        locale-gen
        DEBCONF_NONINTERACTIVE_SEEN=true dpkg-reconfigure -f noninteractive locales
        update-locale LANG=es_AR.UTF-8
        locale

        echo Disabling ldm -----------------------------------------------
        if [ -f /etc/systemd/system/display-manager.service ] ; then
                rm /etc/systemd/system/display-manager.service
        fi

        exit" > ${ROOTFS}/root/chroot.sh
        chmod +x ${ROOTFS}/root/chroot.sh
        chroot ${ROOTFS} /bin/bash /root/chroot.sh

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

echo "END of the road!! keep up the good work ---------------------"
