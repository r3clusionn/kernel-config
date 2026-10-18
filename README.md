# kernel-config

A trimmed Linux 7.2.10 (gentoo-sources) kernel configuration for one laptop, the HP OmniBook 7 14-kh0xxx with a Ryzen AI 9 HX 475. Everything the laptop doesn't have or use is removed: Ethernet, other Wi-Fi vendors, SATA, TV tuners, Intel and SoundWire audio, debugging and tracing, hibernation, kexec, NUMA. Security modules and kernel hardening are removed too, after the owner chose to. The kernel image is 8.4 MB instead of 19.1 MB (measured on 7.2.9: 136 MB more RAM available after boot). The scripts that made it are included, so each removal can be read and repeated on a newer kernel.

**Status:** the running kernel on the target laptop since 2026-10-16 (`7.2.10-gentoo-min-b19`, EFI stub, no initramfs).

![Terminal output on a dark background, two kernel boot lines. Original kernel: "Memory: 56913620K/58248588K available (23888K kernel code, 5137K rwdata, 10404K rodata, 3344K init, 5540K bss, 1297436K reserved)". This config: "Memory: 57052832K/58248588K available (14789K kernel code, 1867K rwdata, 5800K rodata, 1572K init, 3128K bss, 1173760K reserved)". Then the image sizes: 10826240 bytes for bzImage-min.efi and 19149312 bytes for the original bzImage.efi](docs/images/memory.png)

## Features

- **`config-7.3.0-rc7-min-b29`:** the current full `.config` (Linux 7.3-rc7): 1564 options built in, 121 as modules, built with Clang 23 (ThinLTO, `-O3`, AutoFDO). The 7.2.10 b17/b19 configs and `changes-b19.sh` are the earlier GCC kernels; see History.
- **`build-clang.sh`:** the build as used: mainline sources plus `patches/`, the b26 GCC config switched to Clang (`LLVM=1`) with ThinLTO, `-O3`, `AUTOFDO_CLANG`, `TRIM_UNUSED_KSYMS` and TCP BBR, the firmware built in. With a profile argument it builds the AutoFDO-optimized kernel.
- **`patches/`:** `cs35l41-103c8f2e.patch` (the speakers' CS35L41 amplifier entries, not in mainline 7.3-rc7), `workqueue-one-idle-worker.patch` (each worker pool keeps 1 idle kworker instead of 2), `cachy-O3-kconfig.patch` (CachyOS's `CC_OPTIMIZE_FOR_PERFORMANCE_O3`), `clang-lto-O3.patch` (local: ThinLTO's backends otherwise run at ld.lld's default `--lto-O2`, so `-O3` only reached the pre-link step), and `cachy-poc-selector-v2.6.3.patch` (CachyOS's idle-CPU selector, tried in b28 and turned off in b29, see History).
- **`autofdo/`:** `kernel.afdo`, the AutoFDO profile b29 was built with, and `workload.sh`, the load it was sampled under.
- **Fast on this CPU:** built for the native CPU (Zen 5), optimized for performance, 1000 Hz timer, lazy preemption, idle-only tickless, CPU vulnerability mitigations compiled out (see Limits).
- **Boots without an initramfs:** the command line and the AMD CPU microcode are built into the image, and NVMe and XFS are built in, so the EFI firmware starts the kernel directly.
- **`trim.sh`:** the non-security removals, grouped and commented (power and wakeups, unused subsystems, workqueue owners, GPU and NPU, audio, absent hardware, debug infrastructure).
- **`trim-security.sh`:** the security removals the owner confirmed separately: SELinux, AppArmor, TOMOYO, IPE, IMA/EVM, audit, TPM, KFENCE. Landlock and Yama stayed then; b19 removes them too (`changes-b19.sh`).
- **`install.sh`:** installs the built image as an EFI stub and boots it once (`BootNext`), so a kernel that doesn't boot falls back to the default entry on the next start.

## How to install

Requires gentoo-sources 7.2.10 (or a close version) and the speaker patch from [omnibook7-speakers](https://github.com/r3clusionn/omnibook7-speakers) in `/etc/portage/patches/sys-kernel/gentoo-sources/`.

```sh
doas emerge -1 sys-kernel/gentoo-sources
cd /usr/src/linux
doas cp /path/to/config-7.2.10-gentoo-min-b19 .config
doas make olddefconfig
doas make -j"$(nproc)"
doas sh /path/to/install.sh        # modules + EFI image, boots it once
```

Before building, change the built-in command line (`CONFIG_CMDLINE`) to your root partition: it holds this laptop's `root=PARTUUID=…` and `rootfstype=xfs`. Also check `CONFIG_EXTRA_FIRMWARE`, which needs `amd-ucode/microcode_amd_fam1ah.bin` from linux-firmware.

`install.sh` expects an EFI boot entry named `Gentoo-min` pointing at `\EFI\Gentoo\bzImage-min.efi`. Create it once with `efibootmgr`. Make it the default only after the test boot works.

## How to use

On a newer kernel, start from the new default config and apply the scripts. They use the kernel's `scripts/config`:

```sh
sh trim.sh .config
sh trim-security.sh .config       # only if you want the same security trade-offs
make olddefconfig
```

Then compare with `config-7.2.10-gentoo-min-b19` for anything new. To go from a b17-style config to b19, run `sh changes-b19.sh <kernel source> .config`.

## How it works

- **No initramfs:** NVMe and XFS are built in, the early microcode is embedded with `CONFIG_EXTRA_FIRMWARE`, and `CONFIG_CMDLINE` names the root partition. The firmware loads the EFI stub and the kernel mounts root directly. Initramfs support itself is still compiled in but unused. The command line also sizes the dentry, inode and TCP hash tables down (`dhash_entries`, `ihash_entries`, `thash_entries`).
- **Hardware only:**
  - amdgpu for RDNA 3.5 without the old SI and CIK support or the ROCm HSA driver;
  - HDA audio with the CS35L41 I2C amplifiers, and the AMD ACP drivers for the microphone (Intel, SOF and SoundWire audio are off);
  - Realtek Wi-Fi only (rtw89, RTL8922AE);
  - HP and AMD platform drivers (amd-pmf, hp-wmi).
- **Fewer background wakeups:** PSI, schedstats, task delay accounting, memory cgroups, EDAC, quotas and block throttling are off. Several of them own workqueue rescuer threads or periodic timers.
- **Security trade-offs** (`trim-security.sh`, and in the final config):
  - no LSMs at all in b19 (Landlock and Yama were the last ones), no stack protector, fortify or list hardening; seccomp and namespaces stay for browser sandboxes;
  - zero-on-allocation (`init_on_alloc`) is off by default;
  - the CPU vulnerability mitigations (Spectre and similar) are compiled out (`CPU_MITIGATIONS` off) for speed;
  - stack offset randomization and the other defaults stay.

## History

- **b21** (7.2.10): IA32 emulation, user shadow stack, binfmt_misc, `/proc/config.gz` and `/proc/kcore` off; no stack initialization; no swiotlb bounce buffer.
- **b22:** mainline 7.3-rc7 (the speaker patch is needed on any non-Gentoo tree); a small text console (`video=eDP-1:640x480`) saves the console's framebuffer.
- **b23–b26:** amdgpu and the 33 drivers that stay loaded built in, every firmware file the laptop loads (GPU, microcode, Wi-Fi, Bluetooth, speakers, `regulatory.db`) in `CONFIG_EXTRA_FIRMWARE`, smaller hash tables, IOMMU and debugfs off, the workqueue patch. No firmware package is installed.
- **b28:** the b26 config built with Clang 23: ThinLTO, `-O3` (with `--lto-O3`), `-march=native` (znver5), `TRIM_UNUSED_KSYMS`, TCP BBR as default, and CachyOS's POC selector for an A/B test. The POC selector made pipe ping-pong 30% slower for 1–2% elsewhere, so b29 turns it off.
- **b29:** b28 built with an AutoFDO profile (`-fprofile-sample-use`, `-fsplit-machine-functions`, `--lto-sample-profile`), sampled with `perf record -b` on the branch event `cpu/event=0xc4/k` (Zen 5's 16-entry LBR, no libpfm needed) during a kernel build, file work, a download, emerge, git and X text drawing, plus 10 minutes of normal use, and converted with `llvm-profgen`.

## Measurements

b29 against b26 (GCC 16, `-O2`, no LTO), same power plan and on AC, median of 3–5 runs: scheduler messaging −10.6%, deleting a 1.8 GB tree −18%, execve −5.4%, fork −2.2%, a tinyconfig kernel build −0.5%, a bare `getppid` syscall +5% (1.6 ns), user-space work unchanged (±2%). The profile's own share (b29 against b28): messaging −5.3%, tree delete −14%. Suspend: S0i3 for 23.7 of 30 s on battery.

The older measurements (GCC kernels):



From the kernel's own boot messages and the image files (original kernel vs this config):

| | Original | This config |
|---|---|---|
| EFI image | 19.1 MB | 10.8 MB (7.2.9), 10.7 MB (7.2.10 b17), 8.4 MB (7.2.10 b19) |
| Kernel code | 23888 kB | 14789 kB |
| Read-only data | 10404 kB | 5800 kB |
| Reserved at boot | 1297436 kB | 1173760 kB |
| Available after boot | 56913620 kB | 57052832 kB (+136 MB) |

## Verification

- `config-7.2.10-gentoo-min-b19` is identical to the running kernel's `/proc/config.gz`. Before building, a check confirmed that every module and driver in use on b17 is still built (122 checked).
- Test boot of b19 (2026-10-16): Wi-Fi, Bluetooth radio and scan, camera picture, speakers and the PDM mic (a 1 kHz tone played on the speakers is picked up by the mic at −54 dB, against −110 dB in silence), s2idle suspend and RTC wake (24 s of a 30 s sleep in S0ix, Wi-Fi back about 1 s after resume), backlight, battery reporting. SSD reads are unchanged from b17 with the shorter NVMe queues (6558 vs 6562 MiB/s sequential, 3730 vs 3750 MiB/s 4 KiB random). 14.4 MB more memory is available at boot than on b17. Bluetooth audio, the headphone jack and the Fn keys weren't checked on this build.
- Each stage was test-booted once through `BootNext` before replacing the previous one. The final config has been in daily use since: display and GPU (OpenGL games such as Minecraft, hardware video decoding), speakers, Wi-Fi, Bluetooth, and the power plans. The webcam and suspend haven't been checked specifically.

## Limits

- Made for one laptop: on other hardware it will lack drivers, and with the built-in root and no initramfs it won't boot until `CONFIG_CMDLINE` is changed.
- The security removals and the compiled-out mitigations are deliberate trade-offs for a single-user laptop (no SELinux or AppArmor policies were in use), not general advice. Turn `CPU_MITIGATIONS` back on to get the mitigations back.
- Hibernation, kexec, BPF syscalls and tracing are off. Tools that need them (bpftrace, perf tracing) won't work.

## License

The configuration and scripts are GPL-2.0, as the kernel they configure (see `LICENSE`).
