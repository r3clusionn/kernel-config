#!/bin/sh
# Kernel 7.3.0-rc7-min-b28 = b26 config built with Clang 23.1.3 (~/.local/opt/llvm, official
# prebuilt, 0 Portage packages) instead of GCC 16:
#   ThinLTO (LTO_CLANG_THIN), -O3 (CachyOS's CC_OPTIMIZE_FOR_PERFORMANCE_O3 patch) plus the local
#   clang-lto-O3.patch so the ThinLTO backends run at -O3 too (ld.lld defaults to --lto-O2),
#   AUTOFDO_CLANG (profile-ready: line tables only, no runtime change until a profile is used),
#   TRIM_UNUSED_KSYMS, TCP BBR as default, CachyOS POC selector (A/B: kernel.sched_poc_selector).
# Second pass (b29): same with CLANG_AUTOFDO_PROFILE=<profile>, POC off (lost the A/B).
# Sources: linux-7.2 + patch-7.3-rc7 (Manifest-checked), CS35L41 + workqueue + CachyOS patches.
# Run as rec:   sh build-clang.sh [profile.afdo]     (b28 without a profile, b29 with one)
# As used on the laptop: K is the work directory (sources, tools, downloads, build trees),
# BASE the starting config, FW the firmware files for EXTRA_FIRMWARE, KP this repo's patches/.
set -eu
K=/home/rec/work/batch28
S=$K/src
PROF=${1:-}
if [ -n "$PROF" ]; then REL=b29; else REL=b28; fi
O=$K/kbuild-$REL
BASE=/home/rec/work/kernel/config-7.3.0-rc7-min-b26
FW=/home/rec/work/kernel/firmware
KP=/home/rec/work/kernel/patches
[ "$(id -u)" != 0 ] || { echo "run as rec"; exit 1; }
export PATH=/home/rec/.local/opt/llvm/bin:$PATH
clang --version | grep -q 'clang version 23' || { echo "clang 23 not found in ~/.local/opt/llvm"; exit 1; }
python3 -I - "$K/dl" <<'EOF'
import hashlib, sys
want = {'linux-7.2.tar.xz': 'cf5f3d87b96f223034c47c6e5fc972fe52c2556310eb2f064632537b8727231135a8540179fd5d51343738c8a51f51f09c7e8da374324b68551c84a4124bb71b',
        'patch-7.3-rc7.patch': '6cf3986eee66937796955811ff4539fa777dce98d7efb873488629a9b4ccdd308e665eb091b9c36b0cb35c2d3c900277aa0e9fe84408e914c65ce2c1c2e1f0ae'}
for f, h in want.items():
    if hashlib.blake2b(open(f'{sys.argv[1]}/{f}', 'rb').read()).hexdigest() != h:
        sys.exit(f'BLAKE2B mismatch: {f}')
print('downloads verified')
EOF
(cd "$FW" && sha256sum -c --quiet SHA256SUMS) || { echo "firmware copies in $FW don't match SHA256SUMS"; exit 1; }
[ -x "$K/tools/usr/bin/bison" ] || sh "$K/prep.sh"
. "$K/kenv.sh"
if [ ! -f "$S/Makefile" ]; then
    mkdir -p "$S"
    tar -xJf "$K/dl/linux-7.2.tar.xz" -C "$S" --strip-components=1
    patch -d "$S" -p1 -s < "$K/dl/patch-7.3-rc7.patch"
    patch -d "$S" -p1 -s < /etc/portage/patches/sys-kernel/gentoo-sources/cs35l41-103c8f2e.patch   # speakers: not in mainline 7.3-rc7
    patch -d "$S" -p1 -s < "$KP/workqueue-one-idle-worker.patch"
    patch -d "$S" -p1 -s < "$KP/cachy-O3-kconfig.patch"
    patch -d "$S" -p1 -s < "$KP/cachy-poc-selector-v2.6.3.patch"
    patch -d "$S" -p1 -s < "$KP/clang-lto-O3.patch"
    find "$S" -name '*.orig' -delete
fi
grep -qs 103C8F2E "$S/sound/hda/codecs/side-codecs/cs35l41_hda_property.c" || { echo "ERROR: CS35L41 speaker quirk 103C8F2E not found"; exit 1; }
grep -q 'return nr_idle > 1 && (nr_idle - 1)' "$S/kernel/workqueue.c" || { echo "ERROR: workqueue patch not applied"; exit 1; }
grep -q 'config CC_OPTIMIZE_FOR_PERFORMANCE_O3' "$S/init/Kconfig" || { echo "ERROR: O3 patch not applied"; exit 1; }
grep -q 'config SCHED_POC_SELECTOR' "$S/init/Kconfig" || { echo "ERROR: POC patch not applied"; exit 1; }
grep -q -- '--lto-O3' "$S/Makefile" || { echo "ERROR: lto-O3 patch not applied"; exit 1; }
# same firmware list as b26
FWLIST="amd-ucode/microcode_amd_fam1ah.bin amdgpu/dcn_3_5_dmcub.bin amdgpu/gc_11_5_0_imu.bin amdgpu/gc_11_5_0_me.bin amdgpu/gc_11_5_0_mec.bin amdgpu/gc_11_5_0_mes1.bin amdgpu/gc_11_5_0_mes_2.bin amdgpu/gc_11_5_0_pfp.bin amdgpu/gc_11_5_0_rlc.bin amdgpu/psp_14_0_0_ta.bin amdgpu/psp_14_0_0_toc.bin amdgpu/sdma_6_1_0.bin amdgpu/vcn_4_0_5.bin amdgpu/vpe_6_1_0.bin"
FWLIST="$FWLIST rtw89/rtw8922a_fw-4.bin rtl_bt/rtl8922au_fw.bin rtl_bt/rtl8922au_config.bin cirrus/cs35l41-dsp1-spk-prot-103c8f2e.wmfw cirrus/cs35l41-dsp1-spk-prot-103c8f2e-spkid0.bin cirrus/cs35l41-dsp1-spk-prot-103c8f2e-spkid1.bin"
FWLIST="$FWLIST regulatory.db regulatory.db.p7s"
for f in $FWLIST; do [ -s "$FW/$f" ] || { echo "missing firmware $FW/$f"; exit 1; }; done
grep -q "EXTRA_FIRMWARE=\"$FWLIST\"" "$BASE" || { echo "b26 firmware list changed; update FWLIST"; exit 1; }
mkdir -p "$O"; cp "$BASE" "$O/.config"
C="$S/scripts/config --file $O/.config"
$C --set-str LOCALVERSION "-min-$REL"
make -s -C "$S" O="$O" LLVM=1 olddefconfig
$C -d LTO_NONE -e LTO_CLANG_THIN -d CC_OPTIMIZE_FOR_PERFORMANCE -e CC_OPTIMIZE_FOR_PERFORMANCE_O3 \
   -e AUTOFDO_CLANG -e TRIM_UNUSED_KSYMS -e TCP_CONG_ADVANCED -e TCP_CONG_BBR -e DEFAULT_BBR -d DEFAULT_CUBIC \
   -e SCHED_POC_SELECTOR
# b29: POC lost the A/B on b28 (pipe ping-pong ~30% slower, ~1-2% gain elsewhere)
[ -z "$PROF" ] || $C -d SCHED_POC_SELECTOR
make -s -C "$S" O="$O" LLVM=1 olddefconfig
for o in CC_IS_CLANG LTO_CLANG_THIN CC_OPTIMIZE_FOR_PERFORMANCE_O3 AUTOFDO_CLANG TRIM_UNUSED_KSYMS DEFAULT_BBR X86_NATIVE_CPU INIT_STACK_NONE; do
    grep -q "^CONFIG_$o=y" "$O/.config" || { echo "ERROR: CONFIG_$o is not y after olddefconfig"; exit 1; }
done
for o in CFI RANDSTRUCT_FULL KSTACK_ERASE ZERO_CALL_USED_REGS DEBUG_INFO_DWARF5 DEBUG_INFO_DWARF4; do
    ! grep -q "^CONFIG_$o=y" "$O/.config" || { echo "ERROR: CONFIG_$o got enabled"; exit 1; }
done
"$S/scripts/diffconfig" "$BASE" "$O/.config" > "$K/diffconfig-$REL.txt" || true
echo "== config: $(grep -c . "$K/diffconfig-$REL.txt") lines differ from b26 (diffconfig-$REL.txt)"
echo "== building $REL $( [ -n "$PROF" ] && echo "with AutoFDO profile $PROF")"
s=$(date +%s)
if [ -n "$PROF" ]; then
    nice make -s -C "$S" O="$O" LLVM=1 -j24 -l24 CLANG_AUTOFDO_PROFILE="$PROF"
else
    nice make -s -C "$S" O="$O" LLVM=1 -j24 -l24
fi
echo "== built $(cat "$O/include/config/kernel.release") in $(( $(date +%s) - s )) s"
ls -la "$O/arch/x86/boot/bzImage"
llvm-size "$O/vmlinux" | tail -1
