#!/bin/sh
# Install the built 7.2.9-gentoo-min kernel (EFI stub) for ONE test boot.
# Replaces the installed image and modules of the same release name.
# BootNext only: if it fails, the next boot uses the default entry again.
# Run from the kernel tree after building:  doas sh install.sh   then reboot.
set -eu
cd /usr/src/linux
[ "$(make -s kernelrelease)" = "7.2.9-gentoo-min" ] || { echo "unexpected kernel release"; exit 1; }
grep -q CONFIG_HZ_1000=y .config || { echo "not this config"; exit 1; }
grep -q "^# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set" .config || { echo "not this config"; exit 1; }

rm -rf /lib/modules/7.2.9-gentoo-min
make -s modules_install
cp arch/x86/boot/bzImage /efi/EFI/Gentoo/bzImage-min.efi

NEW=$(efibootmgr | awk '/Gentoo-min/{print substr($1,5,4); exit}')
[ -n "$NEW" ] || { echo "Gentoo-min boot entry missing"; exit 1; }
efibootmgr -q -n "$NEW"
efibootmgr | head -4
echo "OK: reboot now (BootNext=$NEW)."
