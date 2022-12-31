#!/bin/sh
set -e
set -o noglob

# --- global variables ---
GIT_URL="https://github.com/reidav/arch"
BT_ARCH_INSTALLER="/root/arch-install-tmp-$$"
BT_HOST=""
BT_USER_NAME=""
BT_PASSWORD=""
BT_LUKS_KEY=""
BT_SWAP_SIZE="10G"
BT_VM="HyperV"

# --- helper functions ---
info() {
    echo '[INFO] ' "$@"
}
warn() {
    echo '[WARN] ' "$@" >&2
}
fatal() {
    echo '[ERROR] ' "$@" >&2
    exit 1
}
dialog_to_me() {
    DIALOG_RESULT=$(dialog --clear --stdout --backtitle "Installing ArchLinux" --no-shadow "$@" 2>/dev/null)
}

# --- bootstrap functions ---
bootstrap_pacman_and_required_packages() {
    info "Rank mirrorlists according to France ..."
    reflector --country France --protocol https --sort rate --save /etc/pacman.d/mirrorlist

    pacman-key --init
    pacman-key --populate archlinux
    pacman-key --refresh-keys
    pacman -Syy --noconfirm
    pacman -S dialog git --noconfirm
}

bootstrap_ask_global_settings() {
    reset
    dialog_to_me --title "Hostname" --inputbox "Please enter a name for this host.\n" 8 60
    BT_HOST="$DIALOG_RESULT"

    dialog_to_me --title "Disk encryption" --passwordbox "Please enter a strong passphrase for the full disk encryption.\n" 8 60
    BT_LUKS_KEY="$DIALOG_RESULT"

    dialog_to_me --title "Username" --inputbox "Please enter a username.\n" 8 60
    BT_USER_NAME="$DIALOG_RESULT"

    dialog_to_me --title "Password" --passwordbox "Please enter a password.\n" 8 60
    BT_PASSWORD="$DIALOG_RESULT"

    dialog_to_me --title "Swap Size" --inputbox "Please enter a swap size.\n" 8 60 "10G"
    BT_SWAP_SIZE="$DIALOG_RESULT"

    dialog_to_me --title "WARNING" --msgbox "This script will destroy your disk.\nPress <Enter> to continue or <Esc> to cancel.\n" 6 60
    [[ $? -ne 0 ]] && (dialog_to_me --title "Cancelled" --msgbox "Script was cancelled at your request." 5 40; exit 0)
    reset
} 

bootstrap_create_and_mount_volumes() {
    if lsblk | grep -q nvme0n1; then
        DISK="/dev/nvme0n1"
        ESP_PARTITION="${DISK}p1"
        BOOT_PARTITION="${DISK}p2"
        ROOT_PARTITION="${DISK}p3"
    else
        DISK="/dev/sda"
        ESP_PARTITION="${DISK}1"
        BOOT_PARTITION="${DISK}2"
        ROOT_PARTITION="${DISK}3"
    fi

    info "Empty volumes ...."
    sgdisk --zap-all $DISK
    
    info "Using parted to set up volumes (${ESP_PARTITION}, ${ROOT_PARTITION}, ${LVM_PARTITION}) ..."

    yes | parted -s "$DISK" mklabel gpt
    yes | parted -s -a optimal "$DISK" mkpart ESP fat32 1MiB 512MiB
    yes | parted -s "$DISK" set 1 boot on
    yes | parted -s "$DISK" name 1 efi

    yes | parted -s -a optimal "$DISK" mkpart primary ext4 512MiB 800MiB
    yes | parted -s "$DISK" name 2 boot

    yes | parted -s -a optimal "$DISK" mkpart primary ext4 800MiB 100%
    yes | parted -s "$DISK" name 3 root

    parted -s "$DISK" print

    if [ -n "$BT_LUKS_KEY" ]
    then
        info "Setup encryption ..."
        yes | echo -n "$BT_LUKS_KEY" | cryptsetup -y -v luksFormat "${ROOT_PARTITION}" -
        yes | echo -n "$BT_LUKS_KEY" | cryptsetup luksOpen "${ROOT_PARTITION}" cryptroot -d -
        ROOT_PARTITION="/dev/mapper/cryptroot"
    fi
    
    info "Initializing volumes ..."
    yes | mkfs.fat -F32 "$ESP_PARTITION"
    yes | mkfs.ext2 "$BOOT_PARTITION"
    yes | mkfs.ext4 "$ROOT_PARTITION"

    mount "$ROOT_PARTITION" /mnt
    mkdir -p /mnt/boot && mount "$BOOT_PARTITION" /mnt/boot
    mkdir -p /mnt/boot/efi && mount "$ESP_PARTITION" /mnt/boot/efi
}

# --- chroot functions ---
chroot_system_pacstrap() {
    info "Pactrap in /mtn and base system configuration ..."
    yes "" | pacstrap -i /mnt pacman base linux linux-firmware base-devel fish git grub dhcpcd sudo dialog ntp wget efibootmgr intel-ucode neovim iwd
    genfstab -p /mnt >> /mnt/etc/fstab
}

chroot_system_configure() {
    info "Base system configuration ..."

    arch-chroot /mnt /bin/bash <<EOF
        pacman-key --init
        pacman-key --populate archlinux

        echo "Rank mirrorlists according to France ..."
        reflector --country France --protocol https --sort rate --save /etc/pacman.d/mirrorlist

        echo "Setting $BT_HOST as hostname ..."
        echo "$BT_HOST" > /etc/hostname
        sed -i "/localhost/s/$/ $BT_HOST/" /etc/hosts

        echo "Creating the swap file to $BT_SWAP_SIZE ..."
        fallocate -l "$BT_SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        echo /swapfile none swap defaults 0 0 >> /etc/fstab

        echo "Setting the US & FR locale ..."
        echo -e "en_US.UTF-8 UTF-8\nfr_FR.UTF-8 UTF-8" > /etc/locale.gen
        echo LANG=en_US.UTF-8 > /etc/locale.conf
        locale-gen
        echo "KEYMAP=fr" > /etc/vconsole.conf
        ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
        hwclock --systohc
 
        echo "Configuring sudo ..."
        echo 'root ALL=(ALL) ALL' > /etc/sudoers
        echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
        echo -e 'EDITOR=nvim' > /etc/environment

        echo "Configuring services ..."
        systemctl enable dhcpcd.service
        systemctl enable ntpd.service

        info "Installing fonts ..."
        pacman -Syu --noconfirm fontconfig $(pacman -Ssq ttf | grep -v ttf-nerd-fonts-symbols-mono)
        
        echo "Setting credentials for root ..."
        echo "root:$BT_PASSWORD" | chpasswd
EOF
}

chroot_system_grub() {
    if lsblk | grep -q nvme0n1; then
        DISK="/dev/nvme0n1"
        ROOT_PARTITION="${DISK}p3"
    else
        DISK="/dev/sda"
        ROOT_PARTITION="${DISK}3"
    fi

    if [ -n "$BT_LUKS_KEY" ]
    then
        arch-chroot /mnt /bin/bash <<EOF
	    sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/g' /etc/mkinitcpio.conf
        sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub
        sed -i 's/#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
        echo GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value $ROOT_PARTITION):cryptroot root=/dev/mapper/cryptroot\" >> /etc/default/grub
EOF
    fi

    arch-chroot /mnt /bin/bash <<EOF
    mkinitcpio -p linux
    grub-install --efi-directory=/boot/efi --target=x86_64-efi --bootloader-id=GRUB
    sudo sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
EOF
}

chroot_system_copy_installer_assets() {
    info "Copy installer assets in $BT_ARCH_INSTALLER ..."
    
    arch-chroot /mnt /bin/bash <<EOF
    mkdir -p $BT_ARCH_INSTALLER
    git clone $GIT_URL $BT_ARCH_INSTALLER
EOF
}

chroot_system_dwm_st_slstatus() {
    info "Installing dwm, st, slstatus & dependencies ..."
    
    SUCKLESS_TMP_BUILD_DIR="/tmp/suckless-install-tmp-$$"

    arch-chroot /mnt /bin/bash <<EOF
        pacman -S --needed --noconfirm xorg xorg-xinit xf86-video-intel picom feh rofi alsa-utils
        
        echo "Building dwm ..."
        mkdir -p $SUCKLESS_TMP_BUILD_DIR/dwm-tmp
        cp -r $BT_ARCH_INSTALLER/assets/suckless/dwm/* $SUCKLESS_TMP_BUILD_DIR/dwm-tmp
            
        echo "Patching dwm ..."
        cp -r $BT_ARCH_INSTALLER/assets/suckless/patches/dwm-*.diff $SUCKLESS_TMP_BUILD_DIR/dwm-tmp
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/dwm-tmp; git apply dwm-01-alpha-20201019-61bb8b2.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/dwm-tmp; git apply dwm-02-azerty-6.2.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/dwm-tmp; git apply dwm-03-hide_vacant_tags-6.3.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/dwm-tmp; git apply dwm-04-vanity_gaps_custom.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/dwm-tmp; git apply dwm-05-gruvbox_custom.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/dwm-tmp; git apply dwm-06-cmd_custom.diff -v; )"
        make install -C $SUCKLESS_TMP_BUILD_DIR/dwm-tmp

        echo "Building st ..."
        mkdir -p $SUCKLESS_TMP_BUILD_DIR/st-tmp
        cp -r $BT_ARCH_INSTALLER/assets/suckless/st/* $SUCKLESS_TMP_BUILD_DIR/st-tmp
            
        echo "Patching st ..."
        cp -r $BT_ARCH_INSTALLER/assets/suckless/patches/st-*.diff $SUCKLESS_TMP_BUILD_DIR/st-tmp
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/st-tmp; git apply st-01-alpha-20220206-0.8.5.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/st-tmp; git apply st-02-changing-st-fonts.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/st-tmp; git apply st-03-scrollback-0.8.5.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/st-tmp; git apply st-04-gruvbox-material-0.8.2_custom.diff -v; )"
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/st-tmp; git apply st-05-scrollback_custom.diff -v; )"
        make install -C $SUCKLESS_TMP_BUILD_DIR/st-tmp

        echo "Building slstatus ..."
        mkdir -p $SUCKLESS_TMP_BUILD_DIR/slstatus-tmp
        cp -r $BT_ARCH_INSTALLER/assets/suckless/slstatus/* $SUCKLESS_TMP_BUILD_DIR/slstatus-tmp
        
        echo "Patching slstatus ..."
        cp $BT_ARCH_INSTALLER/assets/suckless/patches/slstatus-*.diff $SUCKLESS_TMP_BUILD_DIR/slstatus-tmp
        sh -c "(cd $SUCKLESS_TMP_BUILD_DIR/slstatus-tmp; git apply slstatus-01-modules.diff; )"
            
        make install -C $SUCKLESS_TMP_BUILD_DIR/slstatus-tmp

        rm -rf $SUCKLESS_TMP_BUILD_DIR
EOF
}

chroot_profile_setup() {
    info "Profile creation ..."
    
    arch-chroot /mnt /bin/bash <<EOF
        echo "Adding $BT_USER_NAME as new user ..."
        useradd -m -G wheel -s /bin/fish $BT_USER_NAME

        echo "$BT_USER_NAME:$BT_PASSWORD" | chpasswd
EOF
}

chroot_profile_set_vm_enhanced_mode() {
    info "Preparing VM Enhanced Mode ..."
    TMP_DIR="/home/$BT_USER_NAME/vmem-install-tmp-$$"

    arch-chroot /mnt /bin/bash <<REALEND
        pacman -Syu --needed --noconfirm base base-devel git
        su $BT_USER_NAME -c "mkdir -p $TMP_DIR"  -s /bin/sh
        su $BT_USER_NAME -c "git clone https://aur.archlinux.org/xrdp.git $TMP_DIR/xrdp"  -s /bin/sh
	    su $BT_USER_NAME -c "(cd $TMP_DIR/xrdp || exit && makepkg -sri --noconfirm)"  -s /bin/sh
        su $BT_USER_NAME -c "git clone https://aur.archlinux.org/xorgxrdp-devel-git.git $TMP_DIR/xorgxrdp-devel-git"  -s /bin/sh
	    su $BT_USER_NAME -c "(cd $TMP_DIR/xorgxrdp-devel-git || exit && makepkg -sri --noconfirm)"  -s /bin/sh
        su $BT_USER_NAME -c "rm -rf $TMP_DIR"  -s /bin/sh

        systemctl enable xrdp
        systemctl enable xrdp-sesman

        sed -i_orig -e 's/port=3389/port=vsock:\/\/-1:3389/g' /etc/xrdp/xrdp.ini
        sed -i_orig -e 's/security_layer=negotiate/security_layer=rdp/g' /etc/xrdp/xrdp.ini
        sed -i_orig -e 's/crypt_level=high/crypt_level=none/g' /etc/xrdp/xrdp.ini
        sed -i_orig -e 's/bitmap_compression=true/bitmap_compression=false/g' /etc/xrdp/xrdp.ini
        sed -n -e 's/max_bpp=32/max_bpp=24/g' /etc/xrdp/xrdp.ini
        sed -i_orig -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' /etc/xrdp/sesman.ini
        echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

        if [ ! -e /etc/modules-load.d/hv_sock.conf ]; then
            echo "hv_sock" > /etc/modules-load.d/hv_sock.conf
        fi
        
        cat > /etc/polkit-1/rules.d/02-allow-colord.rules <<EOFA
        polkit.addRule(function(action, subject) {
            if ((action.id == "org.freedesktop.color-manager.create-device" ||
                action.id == "org.freedesktop.color-manager.modify-profile" ||
                action.id == "org.freedesktop.color-manager.delete-device" ||
                action.id == "org.freedesktop.color-manager.create-profile" ||
                action.id == "org.freedesktop.color-manager.modify-profile" ||
                action.id == "org.freedesktop.color-manager.delete-profile") &&
                subject.isInGroup("users"))
            {
                return polkit.Result.YES;
            }
        });
EOFA
        # TODO : yay -S pulseaudio-module-xrdp
        # PULSE_SCRIPT=/etc/xrdp/pulse/default.pa pulseaudio --daemonize=no
        # OR
        # /etc/xrdp/sesman.ini
        # [SessionVariables]
        # PULSE_SCRIPT=/etc/xrdp/pulse/default.pa

        cat > /etc/pam.d/xrdp-sesman <<EOFB
        #%PAM-1.0
        auth        include     system-remote-login
        account     include     system-remote-login
        password    include     system-remote-login
        session     include     system-remote-login
EOFB

REALEND

    # vbox only
    # if [ "$VBOX" = true ] 
    # then
    #     pacman -S --noconfirm virtualbox-guest-utils
    #     systemctl enable vboxservice.service
    #     sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet video=1360x768"/g' /etc/default/grub
    # fi
}

chroot_profile_set_yay() {
    info "Installing yay ..."
    TMP_DIR="/home/$BT_USER_NAME/yay-install-tmp-$$"
arch-chroot /mnt /bin/bash <<EOF
    su $BT_USER_NAME -c "mkdir -p $TMP_DIR" -s /bin/sh
    su $BT_USER_NAME -c "git clone https://aur.archlinux.org/yay.git $TMP_DIR" -s /bin/sh
    su $BT_USER_NAME -c "(cd $TMP_DIR && makepkg -si --noconfirm);" -s /bin/sh
    su $BT_USER_NAME -c "yay -Syu --noconfirm" -s /bin/sh
    su $BT_USER_NAME -c "rm -rf $TMP_DIR" -s /bin/sh
EOF
}

chroot_profile_set_font() {
    info "Installing profile fonts ..."
    arch-chroot /mnt /bin/bash <<EOF
        su $BT_USER_NAME -c "mkdir -p ~/.local/share/fonts/saucecodepro" -s /bin/sh
        tar -xzvf "$BT_ARCH_INSTALLER/assets/fonts/SauceCodePro.tgz" -C "/home/$BT_USER_NAME/.local/share/fonts/saucecodepro"
        chown -R $BT_USER_NAME /home/$BT_USER_NAME/.local/share/fonts/saucecodepro
        su $BT_USER_NAME -c "fc-cache -fv" -s /bin/sh
EOF
}

chroot_profile_set_omf() {
    info "Installing Oh My Fish ..."
    TMP_DIR="/home/$BT_USER_NAME/omf-install-tmp-$$"
arch-chroot /mnt /bin/bash <<EOF
    su $BT_USER_NAME -c "mkdir -p $TMP_DIR" -s /bin/sh
    su $BT_USER_NAME -c "curl -L https://get.oh-my.fish > $TMP_DIR/install" -s /bin/sh
    su $BT_USER_NAME -c "fish $TMP_DIR/install --noninteractive --path=~/.local/share/omf --config=~/.config/omf" -s /bin/sh
    su $BT_USER_NAME -c "fish -c 'set -U fish_greeting'" -s /bin/sh
    su $BT_USER_NAME -c "rm -rf $TMP_DIR" -s /bin/sh
    su $BT_USER_NAME -c "omf install agnoster" -s /bin/fish
EOF
}

chroot_profile_set_devtools() {
    info "Installing npm go dotnet-sdk ..."
arch-chroot /mnt /bin/bash <<EOF
    pacman -S --needed --noconfirm npm go dotnet-sdk
    su $BT_USER_NAME -c "yay -S --noconfirm powershell-bin"
    su $BT_USER_NAME -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

    echo "Installing neovim  ..."
    pacman -S --needed --noconfirm neovim
EOF
}

chroot_profile_set_apps() {
    info "Installing apps ..."
arch-chroot /mnt /bin/bash <<EOF
    su $BT_USER_NAME -c "yay -S --noconfirm brave-bin"
EOF
}

chroot_profile_set_dotfiles() {
    info "Setting dotfiles ..."
arch-chroot /mnt /bin/bash <<EOF
    cp -rpf $BT_ARCH_INSTALLER/assets/dotfiles/. /home/$BT_USER_NAME
    chown -R $BT_USER_NAME:$BT_USER_NAME /home/$BT_USER_NAME
EOF
}

chroot_system_clean() {
    info "Cleaning, in chroot..."
    arch-chroot /mnt /bin/bash <<EOF
    rm -rf $BT_ARCH_INSTALLER
EOF
}

umount_and_reboot() {
    info "Unmounting & rebooting ..."
    umount -R /mnt
    reboot
}

# --- run the install process
{
    # --- if user is root, starting new installation 
    if [ $(id -u) -ne 0 ]; then
        fatal "This script should be running with root account to perform arch installation"
    fi

    bootstrap_pacman_and_required_packages   
    bootstrap_ask_global_settings    
    bootstrap_create_and_mount_volumes
    
    chroot_system_pacstrap
    chroot_system_configure
    chroot_system_grub
    chroot_system_copy_installer_assets
    chroot_system_dwm_st_slstatus

    chroot_profile_setup
    if [ -n "$BT_VM" ]; then
        chroot_profile_set_vm_enhanced_mode
    fi
    
    chroot_profile_set_yay
    chroot_profile_set_font
    chroot_profile_set_omf
    chroot_profile_set_devtools
    chroot_profile_set_apps
    chroot_profile_set_dotfiles
    chroot_system_clean

    umount_and_reboot
}
