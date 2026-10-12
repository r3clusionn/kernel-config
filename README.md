# kernel-config

A trimmed Linux 7.2.9 (gentoo-sources) kernel configuration for one laptop, the HP OmniBook 7 14-kh0xxx with a Ryzen AI 9 HX 475. Everything the laptop doesn't have or use is removed: Ethernet, other Wi-Fi vendors, SATA, TV tuners, Intel and SoundWire audio, debugging and tracing, hibernation, kexec, NUMA. Unused security modules are removed too, after the owner chose to. The kernel image is 10.8 MB instead of 19.1 MB, and 136 MB more RAM is available after boot. The scripts that made it are included, so each removal can be read and repeated on a newer kernel.

**Status:** the running kernel on the target laptop since 2026-10-10 (`7.2.9-gentoo-min`, EFI stub, no initramfs).

![Terminal output on a dark background, two kernel boot lines. Original kernel: "Memory: 56913620K/58248588K available (23888K kernel code, 5137K rwdata, 10404K rodata, 3344K init, 5540K bss, 1297436K reserved)". This config: "Memory: 57052832K/58248588K available (14789K kernel code, 1867K rwdata, 5800K rodata, 1572K init, 3128K bss, 1173760K reserved)". Then the image sizes: 10826240 bytes for bzImage-min.efi and 19149312 bytes for the original bzImage.efi](docs/images/memory.png)

## Features

- **`config-7.2.9-gentoo-min`:** the full `.config`, matching the running kernel's `/proc/config.gz`. 1790 options built in, 182 as modules.
- **Fast on this CPU:** built for the native CPU (Zen 5), optimized for performance, 1000 Hz timer, lazy preemption, idle-only tickless, CPU vulnerability mitigations off (see Limits).
- **Boots without an initramfs:** the command line and the AMD CPU microcode are built into the image, and NVMe and XFS are built in, so the EFI firmware starts the kernel directly.
- **`trim.sh`:** the non-security removals, grouped and commented (power and wakeups, unused subsystems, workqueue owners, GPU and NPU, audio, absent hardware, debug infrastructure).
- **`trim-security.sh`:** the security removals the owner confirmed separately: SELinux, AppArmor, TOMOYO, IPE, IMA/EVM, audit, TPM, KFENCE. Landlock and Yama stay.
- **`install.sh`:** installs the built image as an EFI stub and boots it once (`BootNext`), so a kernel that doesn't boot falls back to the default entry on the next start.

## How to install

Requires gentoo-sources 7.2.9 (or a close version) and the speaker patch from [omnibook7-speakers](https://github.com/r3clusionn/omnibook7-speakers) in `/etc/portage/patches/sys-kernel/gentoo-sources/`.

```sh
doas emerge -1 sys-kernel/gentoo-sources
cd /usr/src/linux
doas cp /path/to/config-7.2.9-gentoo-min .config
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

Then compare with `config-7.2.9-gentoo-min` for anything new.

## How it works

- **No initramfs:** NVMe and XFS are built in, the early microcode is embedded with `CONFIG_EXTRA_FIRMWARE`, and `CONFIG_CMDLINE` names the root partition. The firmware loads the EFI stub and the kernel mounts root directly. Initramfs support itself is still compiled in but unused. The command line also sizes the dentry, inode and TCP hash tables down (`dhash_entries`, `ihash_entries`, `thash_entries`).
- **Hardware only:**
  - amdgpu for RDNA 3.5 without the old SI and CIK support or the ROCm HSA driver;
  - HDA audio with the CS35L41 I2C amplifiers, and the AMD ACP drivers for the microphone (Intel, SOF and SoundWire audio are off);
  - Realtek Wi-Fi only (rtw89, RTL8922AE);
  - HP and AMD platform drivers (amd-pmf, hp-wmi).
- **Fewer background wakeups:** PSI, schedstats, task delay accounting, memory cgroups, EDAC, quotas and block throttling are off. Several of them own workqueue rescuer threads or periodic timers.
- **Security trade-offs** (`trim-security.sh`, and in the final config):
  - only Landlock and Yama remain as LSMs;
  - zero-on-allocation (`init_on_alloc`) is off by default;
  - `mitigations=off` on the built-in command line disables the CPU vulnerability mitigations (Spectre and similar) for speed;
  - stack offset randomization and the other defaults stay.

## Measurements

From the kernel's own boot messages and the image files (original kernel vs this config):

| | Original | This config |
|---|---|---|
| EFI image | 19.1 MB | 10.8 MB |
| Kernel code | 23888 kB | 14789 kB |
| Read-only data | 10404 kB | 5800 kB |
| Reserved at boot | 1297436 kB | 1173760 kB |
| Available after boot | 56913620 kB | 57052832 kB (+136 MB) |

## Verification

- The running kernel's `/proc/config.gz` is identical to `config-7.2.9-gentoo-min`.
- Each stage was test-booted once through `BootNext` before replacing the previous one. The final config has been in daily use since: display and GPU (OpenGL games such as Minecraft, hardware video decoding), speakers, Wi-Fi, Bluetooth, and the power plans. The webcam and suspend haven't been checked specifically.

## Limits

- Made for one laptop: on other hardware it will lack drivers, and with the built-in root and no initramfs it won't boot until `CONFIG_CMDLINE` is changed.
- The security removals and `mitigations=off` are deliberate trade-offs for a single-user laptop (no SELinux or AppArmor policies were in use), not general advice. Remove `mitigations=off` to get the mitigations back.
- Hibernation, kexec, BPF syscalls and tracing are off. Tools that need them (bpftrace, perf tracing) won't work.

## License

The configuration and scripts are GPL-2.0, as the kernel they configure (see `LICENSE`).
