#!/usr/bin/env python3
"""Move the GKI-adapted BORE 7.0.0 bore_ctx out of task_struct.

The vendored BORE patch from af-t/myc-gki keeps task_struct's *binary*
layout by putting `struct bore_ctx bore` in a union over KABI reserves
3..7. That is not enough: genksyms still sees the new struct type inside
task_struct, so the CRC of task_struct (and of module_layout) changes and
stock vendor modules refuse to load -- the bootloop seen on MT6789.

This script restores the stock reserve fields and stores only a pointer
in KABI slot 8 with ANDROID_KABI_USE(). Under __GENKSYMS__ that macro
collapses to the original u64 reserve, so the KMI stays byte- and
CRC-identical to stock. The companion bore12_flat.py rewrites the C
accessors, adds NULL guards and alloc/free hooks.

Adapted from WildKernels/GKI_KernelSU_SUSFS bore branch
(.github/scripts/bore12_state.py, commit 06488106), changed for the
union-in-reserves shape used by our vendored patch.

Usage: bore12_state.py <include/linux/sched.h>
Idempotent: skips files carrying the marker; fails loudly on anchor misses.
"""
import sys

MARK = "/* bore-kabi: bore_ctx lives out-of-line; task_struct slot 8 = pointer */"

OLD = (
    "#ifdef CONFIG_SCHED_BORE\n"
    "\tunion {\n"
    "\t\tstruct bore_ctx bore;\n"
    "\t\tstruct {\n"
    "\t\t\tANDROID_KABI_RESERVE(3);\n"
    "\t\t\tANDROID_KABI_RESERVE(4);\n"
    "\t\t\tANDROID_KABI_RESERVE(5);\n"
    "\t\t\tANDROID_KABI_RESERVE(6);\n"
    "\t\t\tANDROID_KABI_RESERVE(7);\n"
    "\t\t};\n"
    "\t};\n"
    "#else\n"
    "\tANDROID_KABI_RESERVE(3);\n"
    "\tANDROID_KABI_RESERVE(4);\n"
    "\tANDROID_KABI_RESERVE(5);\n"
    "\tANDROID_KABI_RESERVE(6);\n"
    "\tANDROID_KABI_RESERVE(7);\n"
    "#endif\n"
    "\tANDROID_KABI_RESERVE(8);\n"
)

NEW = (
    "\tANDROID_KABI_RESERVE(3);\n"
    "\tANDROID_KABI_RESERVE(4);\n"
    "\tANDROID_KABI_RESERVE(5);\n"
    "\tANDROID_KABI_RESERVE(6);\n"
    "\tANDROID_KABI_RESERVE(7);\n"
    "#ifdef CONFIG_SCHED_BORE\n"
    "\t" + MARK + "\n"
    "\tANDROID_KABI_USE(8, struct bore_ctx *bore);\n"
    "#else\n"
    "\tANDROID_KABI_RESERVE(8);\n"
    "#endif\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: bore12_state.py <sched.h>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path) as f:
        src = f.read()

    if MARK in src:
        print("bore12-state: already relocated; nothing to do")
        return 0

    if "struct bore_ctx {" not in src:
        print("bore12-state: struct bore_ctx missing (BORE patch not applied?)",
              file=sys.stderr)
        return 1

    if src.count(OLD) != 1:
        print(f"bore12-state: found {src.count(OLD)} union-in-reserves blocks "
              "(expected 1); BORE patch shape changed", file=sys.stderr)
        return 1

    with open(path, "w") as f:
        f.write(src.replace(OLD, NEW, 1))
    print("bore12-state: bore_ctx moved out-of-line, task_struct slot 8 = pointer")
    return 0


if __name__ == "__main__":
    sys.exit(main())
