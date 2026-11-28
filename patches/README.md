# Optional kernel patches (Android 16 / GKI 6.12.38)

These patches are **not applied by default**. They are gated behind the
`use_bore`, `use_adios`, `use_lifo_accept` and `use_thp_advise` workflow
inputs and are only applied for `android16-6.12-38-2025-09`, the only
combination currently verified with `patch --dry-run`.

| Patch | Source | SHA256 |
| --- | --- | --- |
| `bore-7.0.0-gki-6.12.patch` | BORE 7.0.0 by Masahito S ([firelzrd/bore-scheduler](https://github.com/firelzrd/bore-scheduler)), GKI KMI-preserving port from [af-t/myc-gki](https://github.com/af-t/myc-gki) commit `7b530e7442b8b65f5d3b159f0b2a06fd5007c24c` | `1da3d4fac9e3990b4606147a26a70c7f938ad50d3693131c2562458e06708f54` |
| `adios-3.2.0-6.12.patch` | ADIOS 3.2.0 by Masahito S ([firelzrd/adios](https://github.com/firelzrd/adios)), stable patch at commit `08bf078aac99075a0bef73c2b2497574a82e4c41` | `acc8365226537617b33064acc623775a3fb3b07e45a6da7820d9563964b1f9f4` |
| `io-sched-defaults-6.12.patch` | Adapted from CachyOS commit `9797ab73854b6019085cd43706cf985ad7cd8b36` (`CACHY: Use BFQ for SQ devices and mq-deadline for MQ devices`) | `75180e6b62570cf9964b29be28d0efa9b36e7ac387fbb978cf11d70bf64bb3be` |
| `lifo-accept-6.12.patch` | Arjan van de Ven's `do accept() in LIFO order for cache efficiency` patch from [clearlinux-pkgs/linux-current](https://github.com/clearlinux-pkgs/linux-current) | `214e27301bd9e9ab24ae4da5bebe405fa25ca5f77c764e0d1dce92571c53cd5e` |
| `thp-shmem-advise-6.12.patch` | Local one-line default change plus tmpfs inheritance, based on the 6.12 `mm/shmem.c` policy | `8481b0b3c4e38e29dd0c25fe6e1a613021cbea6c176dbb58ebe1f912327a9306` |

## Notes

- BORE modifies EEVDF/fair scheduling. It does **not** replace the vendor
  EAS/energy-model or cpufreq governor. It is kept behind an opt-in switch
  because it changes task wakeup/preemption behaviour.
- ADIOS is compiled in but is **not** made the default scheduler. The
  companion I/O tweak selects BFQ for single-queue devices and mq-deadline
  for multi-queue devices, matching CachyOS. The ADIOS-specific default
  switch (`CONFIG_MQ_IOSCHED_DEFAULT_ADIOS`) stays off.
- LIFO accept() changes the wait queue order for TCP/TCP-like listeners.
- THP ADVISE only becomes effective for shmem/tmpfs mappings that explicitly
  call `madvise(MADV_HUGEPAGE)`; the global GKI THP mode is already MADVISE.
