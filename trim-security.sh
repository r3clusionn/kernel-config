#!/bin/sh
# Batch 5b: security-related options the owner explicitly confirmed removing
# (2026-10-10). Inactive LSMs, IMA/EVM without policy, AUDIT, TPM, KFENCE.
# Landlock and Yama are kept.
set -e
K=/usr/src/linux; F=$1
sc() { "$K/scripts/config" --file "$F" "$@"; }
sc -d SECURITY_SELINUX -d SECURITY_APPARMOR -d SECURITY_TOMOYO -d SECURITY_IPE \
   -d IMA -d EVM -d AUDIT -d TCG_TPM -d KFENCE \
   --set-str LSM "landlock,yama"
