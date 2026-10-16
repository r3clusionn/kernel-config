#!/bin/sh
# Batch 19 kernel config changes, applied on top of the running b17 config.
# Usage: sh changes-b19.sh <kernel source dir> <.config to edit>
# Every change is a removal or a boot option; nothing new is built in.
# Bluetooth (Realtek), camera (UVC), speakers (CS35L41 + HDA), mic (ACP PDM),
# USB4, s2idle, battery, hotkeys, Wi-Fi debugfs and RAPL power meters are untouched.
set -eu
S=$1
C="$S/scripts/config --file $2"

$C --set-str LOCALVERSION -min-b19

# Boot options (built-in command line).
#   - mitigations=off dropped: CPU_MITIGATIONS is already off, the kernel logs
#     that it ignores the option
#   + nvme.io_queue_depth=256: shorter SSD request queues, about -6 MiB (1024 before)
#   + processor.bm_check_disable=1: skip the ACPI bus-master check on every
#     deep-idle (C3) entry; same effect as CachyOS's Strix Point patch
$C --set-str CMDLINE "root=PARTUUID=d41b11bb-3a4e-4328-bcc0-a6c952435f9a rootfstype=xfs rw dhash_entries=262144 ihash_entries=131072 thash_entries=32768 nvme.io_queue_depth=256 processor.bm_check_disable=1"

# M. Memory (the pending batch from the 2026-10-15 measurement)
#   AMD_MEM_ENCRYPT: memory encryption is not active here; it forces three
#     4 MiB atomic DMA pools (-12 MiB)
#   MEMORY_HOTPLUG: takes ZONE_DEVICE and DEVICE_PRIVATE with it (only ROCm's
#     SVM needs those; HSA_AMD is off)
#   KMALLOC_PARTITION_CACHES: hardening that keeps 16 copies of the kmalloc caches
#   SLAB_BUCKETS: hardening that keeps separate kmalloc caches for user-sized data
$C --disable AMD_MEM_ENCRYPT
$C --disable MEMORY_HOTPLUG
$C --disable KMALLOC_PARTITION_CACHES
$C --disable SLAB_BUCKETS

# H. Hardware this laptop doesn't have
#   no serial port (32 /dev/ttyS* exist, none is real); EFI boot, no VGA text
#   mode; simpledrm already drives the EFI framebuffer
$C --disable SERIAL_8250
$C --disable VGA_CONSOLE
$C --disable FB_EFI
#   other CPU vendors and Intel-only features
$C --enable PROCESSOR_SELECT
$C --disable CPU_SUP_INTEL --disable CPU_SUP_HYGON --disable CPU_SUP_CENTAUR --disable CPU_SUP_ZHAOXIN
$C --disable X86_SGX --disable X86_MCE_INTEL --disable INTEL_HFI_THERMAL --disable I2C_DESIGNWARE_BAYTRAIL
#   Bluetooth: Broadcom, MediaTek and Intel-PCIe chips. The Realtek RTL8922AU
#   uses btusb + btrtl, which stay (btusb also always needs btintel)
$C --disable BT_HCIBTUSB_BCM --disable BT_HCIBTUSB_MTK --disable BT_INTEL_PCIE
#   server and ECC error handling (no HEST table, no ECC reporting)
$C --disable ACPI_APEI --disable PCIE_DPC --disable PCIE_PTM --disable RAS_CEC --disable AMD_ATL --disable X86_MCELOG_LEGACY
#   Zen 3 branch sampling, Renesas USB 3 firmware loader, Cypress USB-C on NVIDIA GPUs
$C --disable PERF_EVENTS_AMD_BRS --disable USB_XHCI_PCI_RENESAS --disable I2C_CCGX_UCSI
#   PS/2 mice (the touchpad is I2C), Apple and N-Trig touch devices, an industrial ADC
$C --disable MOUSE_PS2 --disable HID_MAGICMOUSE --disable HID_NTRIG --disable AD4130

# U. Features nothing here uses
#   one SSD, no multipath; the SSD runs with no I/O scheduler, keep mq-deadline only
$C --disable NVME_MULTIPATH --disable IOSCHED_BFQ --disable MQ_IOSCHED_KYBER
#   amd-pstate active mode only uses powersave/performance (schedutil stays for
#   passive mode); teo is the idle governor in use, menu goes
$C --disable CPU_FREQ_GOV_ONDEMAND --disable CPU_FREQ_GOV_CONSERVATIVE --disable CPU_FREQ_GOV_USERSPACE
$C --disable CPU_IDLE_GOV_MENU
#   scheduler extras nothing sets: utilization clamps, cgroup CPU limits,
#   SMT core scheduling; full-tickless CPU-time accounting while full tickless is off
$C --disable UCLAMP_TASK --disable CFS_BANDWIDTH --disable SCHED_CORE
$C --enable TICK_CPU_ACCOUNTING --disable VIRT_CPU_ACCOUNTING_GEN
#   Qualcomm IPC router, iSCSI, userspace I/O drivers, kernel TLS (OpenSSL is built without ktls)
$C --disable QRTR --disable SCSI_ISCSI_ATTRS --disable UIO --disable TLS
#   ALSA MIDI sequencer (WirePlumber's MIDI monitor is off); audio playback/capture is untouched
$C --disable SND_SEQUENCER --disable SND_HRTIMER
#   Wi-Fi mesh networking and the old CRDA regulatory helper (the kernel loads wireless-regdb itself)
$C --disable MAC80211_MESH --disable CFG80211_CRDA_SUPPORT
#   camera presence/light sensors: nothing reads them; the camera picture is uvcvideo
#   and doesn't change. (AMD_SFH_HID stays: amd-pmf, which the power plans use,
#   depends on it.)
$C --disable HID_SENSOR_HUB
#   debug leftovers: resume tracing through the RTC, boot logo, data symbols in
#   kallsyms, scheduler statistics, contiguous memory allocator (its size is 0)
$C --disable PM_TRACE_RTC --disable LOGO --disable KALLSYMS_ALL --disable SCHEDSTATS --disable CMA
#   legacy x86 interfaces for Wine/DOSEMU and pre-2011 binaries
$C --disable X86_16BIT --disable MODIFY_LDT_SYSCALL --disable X86_IOPL_IOPERM --disable X86_VSYSCALL_EMULATION

# ---- Sweep 2026-10-16 (owner picked A, B and C; ~/work/audit-20261016/REPORT.md) ----
# A. More hardware this laptop doesn't have
#   AGP graphics ports (pre-2008) and the Intel GTT they pull in
$C --disable AGP --disable AGP_INTEL --disable AGP_SIS --disable AGP_VIA --disable INTEL_GTT
#   Intel Atom / Cherry Trail platform drivers (PMICs, SCU, Smart Connect)
$C --disable INTEL_SOC_PMIC_CHTWC --disable INTEL_SOC_PMIC_CHTDC_TI
$C --disable INTEL_SCU_PCI --disable INTEL_SCU_IPC --disable INTEL_SMARTCONNECT
#   Cavium server and old PCI-X hotplug (PCIe/ACPI hotplug stays for USB4)
$C --disable HOTPLUG_PCI_OCTEONEP --disable HOTPLUG_PCI_SHPC
#   CD/DVD drives, zoned (SMR) drives, CMOS /dev/nvram
$C --disable BLK_DEV_SR --disable BLK_DEV_ZONED --disable NVRAM
#   raw MIPI camera sensors/lenses (Intel IPU); the webcam is UVC
$C --disable VIDEO_CAMERA_SENSOR --disable VIDEO_CAMERA_LENS
#   initramfs support: the EFI stub boots straight to root=PARTUUID
$C --disable BLK_DEV_INITRD

# B. Features nothing here uses
#   kexec (loading another kernel without rebooting) and kexec handover
$C --disable KEXEC --disable KEXEC_FILE --disable KEXEC_HANDOVER
#   DAMON memory-access monitoring (off by default, no kdamond runs)
$C --disable DAMON
#   explicit huge pages (THP stays), process accounting, latencytop
$C --disable HUGETLBFS --disable CGROUP_HUGETLB --disable BSD_PROCESS_ACCT --disable LATENCYTOP
#   XFS online scrub/repair (xfs_scrub isn't installed), realtime device,
#   quotas (off), ASCII case-insensitive names; offline xfs_repair still works
$C --disable XFS_ONLINE_SCRUB --disable XFS_RT --disable XFS_QUOTA --disable QUOTA --disable XFS_SUPPORT_ASCII_CI
#   cgroup controllers nothing sets (pure cgroup2; OpenRC/elogind keep cgroups,
#   cpu and pids; Thorium's sandbox keeps namespaces). BLK_CGROUP also takes
#   per-I/O cgroup accounting out of the block path.
$C --disable CGROUP_RDMA --disable CGROUP_DMEM --disable CPUSETS --disable CGROUP_DEVICE
$C --disable CGROUP_PERF --disable CGROUP_MISC --disable CGROUP_FREEZER
$C --disable NET_CLS_CGROUP --disable CGROUP_NET_PRIO --disable CGROUP_NET_CLASSID --disable BLK_CGROUP
#   netfilter: no iptables/nftables installed, no rules
$C --disable NETFILTER
#   IBT: this CPU has no IBT (no ibt flag); it only adds endbr64 to every function
$C --disable X86_KERNEL_IBT

# C. Hardening (owner accepted removing it): stack canaries, fortify and
#    list checks, Landlock/Yama LSMs, boot-time W+X check. SECCOMP and
#    namespaces stay (Thorium/CEF sandbox).
$C --disable STACKPROTECTOR --disable FORTIFY_SOURCE --disable LIST_HARDENED --disable BUG_ON_DATA_CORRUPTION
$C --disable SECURITY --disable SECURITY_DMESG_RESTRICT --disable DEBUG_WX
