# kernel-config

A trimmed Linux 7.2.10 (gentoo-sources) kernel configuration for one laptop, the HP OmniBook 7 14-kh0xxx with a Ryzen AI 9 HX 475. Everything the laptop doesn't have or use is removed: Ethernet, other Wi-Fi vendors, SATA, TV tuners, Intel and SoundWire audio, debugging and tracing, hibernation, kexec, NUMA. Security modules and kernel hardening are removed too, after the owner chose to. The kernel image is 8.4 MB instead of 19.1 MB (measured on 7.2.9: 136 MB more RAM available after boot). The scripts that made it are included, so each removal can be read and repeated on a newer kernel.

**Status:** the running kernel on the target laptop since 2026-10-16 (`7.2.10-gentoo-min-b19`, EFI stub, no initramfs).

![Terminal output on a dark background, two kernel boot lines. Original kernel: "Memory: 56913620K/58248588K available (23888K kernel code, 5137K rwdata, 10404K rodata, 3344K init, 5540K bss, 1297436K reserved)". This config: "Memory: 57052832K/58248588K available (14789K kernel code, 1867K rwdata, 5800K rodata, 1572K init, 3128K bss, 1173760K reserved)". Then the image sizes: 10826240 bytes for bzImage-min.efi and 19149312 bytes for the original bzImage.efi](docs/images/memory.png)

## Features

- **`config-7.2.10-gentoo-min-b19`:** the current full `.config`: 1540 options built in, 156 as modules. `config-7.2.10-gentoo-min-b17` is the one before it; the 7.2.9 config is in the git history.
- **`changes-b19.sh`:** every change from b17 to b19, each with its reason: about −20 MiB of kernel memory (memory encryption pools, NVMe queue depth, memory hotplug, kmalloc hardening caches), the ACPI bus-master check skipped on deep idle, absent hardware, unused features (kexec, DAMON, hugetlbfs, XFS online repair, unused cgroup controllers, netfilter, IBT) and the remaining hardening (stack protector, fortify, Landlock/Yama).
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

## Measurements

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
