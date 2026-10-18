#!/bin/sh
# AutoFDO workload (run as rec while perf samples the kernel): the owner's real kernel-heavy
# work, not the micro-benchmarks. Builds dominate the sample count, as they do in real use.
set -u
K=/home/rec/work/batch28
T=${TMPDIR:-/tmp}/afdo.$$
mkdir -p "$T"
export PATH=/home/rec/.local/opt/llvm/bin:$PATH
. "$K/kenv.sh"
echo "full clang kernel build (b28 config)"
mkdir -p "$K/afdo-build" && cp "$K/kbuild-b28/.config" "$K/afdo-build/.config"
nice make -s -C "$K/src" O="$K/afdo-build" LLVM=1 -j24 -l24 >/dev/null 2>&1
rm -rf "$K/afdo-build"
echo "gcc tinyconfig builds"
for i in 1 2; do make -s -C "$K/src" O="$T/tiny" tinyconfig >/dev/null 2>&1; make -s -C "$K/src" O="$T/tiny" -j24 vmlinux >/dev/null 2>&1; rm -rf "$T/tiny"; done
echo "file work"
for i in 1 2 3; do mkdir -p "$T/c"; tar -C "$K/src" -cf - . | tar -C "$T/c" -xf -; find "$T/c" -type f -name '*.c' | head -2000 | xargs cat >/dev/null; rm -rf "$T/c"; done
find "$K/src" -printf '%s\n' >/dev/null
echo "network download"
curl -fsS -o /dev/null https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.tar.xz
echo "emerge, git, grep, xz"
emerge -pe --usepkg=n @world >/dev/null 2>&1
git -C /home/rec/src/media-player log -p -n 1500 >/dev/null
grep -rc 'static' "$K/src/drivers/gpu" >/dev/null
xz -6 -T0 -c "$K/bench-data/blob" >/dev/null
echo "X text drawing"
DISPLAY=${DISPLAY:-:0} "$K/xftbench" 2000000 >/dev/null
rm -rf "$T"
echo "workload done"
