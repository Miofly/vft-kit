#!/usr/bin/env python3
"""Mach-O chained-fixup (LC_DYLD_CHAINED_FIXUPS) decoder.

Why this exists: on Apple-Silicon Mach-O files, on-disk pointers are NOT plain
addresses -- they are bit-packed chained-fixup entries. Any "scan the data
sections for a pointer to X" trick silently finds nothing on such a file. This
decodes the chains so you can ask "what points at X" for real.

Formats decoded: DYLD_CHAINED_PTR_64 (2) and DYLD_CHAINED_PTR_64_OFFSET (6).
For a dylib the image base is 0, so a rebase entry's `target` is the vmaddr of
what it points at.

Usage:
  python3 macho_chained_fixups.py <macho> [--arch arm64] [--find 0xLO-0xHI] [--json]

  --find prints every fixup whose target lands in [LO,HI), with the vmaddr of
  the entry itself (i.e. the field that holds the pointer).
"""
import argparse
import json
import struct
import sys

CHAINED_FIXUPS = 0x80000034
SEGMENT_64 = 0x19
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
CPU_ARM64 = 0x0100000C
CPU_X86_64 = 0x01000007
CPU_NAMES = {CPU_ARM64: "arm64", CPU_X86_64: "x86_64"}
PTR_FORMATS = {2: "DYLD_CHAINED_PTR_64", 6: "DYLD_CHAINED_PTR_64_OFFSET"}


def load_slice(buf, want_arch):
    """Return (slice_bytes, offset_in_file) for the requested thin slice."""
    magic = struct.unpack(">I", buf[:4])[0]
    if magic not in (FAT_MAGIC, FAT_MAGIC_64):
        return buf, 0
    entry = 20 if magic == FAT_MAGIC else 32
    n = struct.unpack(">I", buf[4:8])[0]
    for i in range(n):
        o = 8 + i * entry
        if magic == FAT_MAGIC:
            cputype, _sub, off, size, _align = struct.unpack(">iiIII", buf[o:o + 20])
        else:
            cputype, _sub, off, size, _align, _res = struct.unpack(">iiIIII", buf[o:o + 24])
        if CPU_NAMES.get(cputype) == want_arch:
            return buf[off:off + size], off
    raise SystemExit(f"no {want_arch} slice; have: "
                     + ", ".join(CPU_NAMES.get(struct.unpack('>i', buf[8 + i * entry:12 + i * entry])[0], "?")
                                 for i in range(n)))


def segments(m):
    ncmds = struct.unpack("<I", m[16:20])[0]
    off, segs, fixups = 32, [], None
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", m[off:off + 8])
        if cmd == SEGMENT_64:
            name = m[off + 8:off + 24].split(b"\0")[0].decode("latin1")
            vmaddr, vmsize, fileoff, filesize = struct.unpack("<QQQQ", m[off + 24:off + 56])
            segs.append({"name": name, "vmaddr": vmaddr, "vmsize": vmsize,
                         "fileoff": fileoff, "filesize": filesize})
        elif cmd == CHAINED_FIXUPS:
            dataoff, datasize = struct.unpack("<II", m[off + 8:off + 16])
            fixups = (dataoff, datasize)
        off += size
    if fixups is None:
        raise SystemExit("no LC_DYLD_CHAINED_FIXUPS in this slice")
    return segs, fixups


def vm2fo(segs, vm):
    for s in segs:
        if s["vmaddr"] <= vm < s["vmaddr"] + s["filesize"]:
            return s["fileoff"] + (vm - s["vmaddr"])
    return None


def decode(m, segs, fixups):
    """Yield (entry_vmaddr, target_vmaddr) for every non-bind fixup."""
    fo, _size = fixups
    (ver, starts_off, _imp_off, _sym_off, imports_count,
     imports_fmt, _sym_fmt) = struct.unpack("<IIIIIII", m[fo:fo + 28])
    base = fo + starts_off
    seg_count = struct.unpack("<I", m[base:base + 4])[0]
    seg_info = [struct.unpack("<I", m[base + 4 + 4 * i:base + 8 + 4 * i])[0]
                for i in range(seg_count)]
    out, stats = [], {"fixups_version": ver, "imports_count": imports_count,
                      "imports_format": imports_fmt, "segments": []}
    for si, so in enumerate(seg_info):
        if so == 0:                                     # segment has no chains
            continue
        sb = base + so
        _sz, page_size, ptr_fmt, seg_off, _mvp, page_count = struct.unpack(
            "<IHHQIH", m[sb:sb + 22])
        if ptr_fmt not in PTR_FORMATS:
            stats["segments"].append({"index": si, "skipped": f"unsupported fmt {ptr_fmt}"})
            continue
        pages = [struct.unpack("<H", m[sb + 22 + 2 * i:sb + 24 + 2 * i])[0]
                 for i in range(page_count)]
        n = 0
        for pi, pstart in enumerate(pages):
            if pstart == 0xFFFF:
                continue
            if pstart & 0x8000:                          # START_MULTI
                idx = sb + 22 + 2 * pi
                cnt = struct.unpack("<H", m[idx:idx + 2])[0]
                starts = [struct.unpack("<H", m[idx + 2 + 2 * k:idx + 4 + 2 * k])[0]
                          for k in range(cnt)]
            else:
                starts = [pstart & 0x7FFF]
            for st in starts:
                vm = seg_off + pi * page_size + st
                while True:
                    efo = vm2fo(segs, vm)
                    if efo is None:
                        break
                    val = struct.unpack("<Q", m[efo:efo + 8])[0]
                    bind = (val >> 63) & 1
                    nxt = (val >> 51) & 0xFFF
                    target = val & ((1 << 36) - 1)               # 64 / 64_OFFSET rebase
                    if not bind:
                        out.append((vm, target))
                    if nxt == 0:
                        break
                    vm += nxt * 4
        stats["segments"].append({"index": si, "segment_offset": seg_off,
                                  "pointer_format": PTR_FORMATS[ptr_fmt],
                                  "page_size": page_size, "pages": page_count,
                                  "rebases": n or None})
    return out, stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("macho")
    ap.add_argument("--arch", default="arm64")
    ap.add_argument("--find", help="0xLO-0xHI: print fixups pointing into this range")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    buf = open(a.macho, "rb").read()
    m, off = load_slice(buf, a.arch)
    segs, fixups = segments(m)
    fix, stats = decode(m, segs, fixups)
    # decode() yields slice-relative addresses, which is what a disassembler
    # (Ghidra etc.) reports for a thin/imported image. Fat-file offsets are
    # slice_offset + that address; we only print the offset, not add it.
    if a.find:
        lo_s, hi_s = a.find.split("-")
        lo, hi = int(lo_s, 16), int(hi_s, 16)
        hits = [(e, t) for e, t in fix if lo <= t < hi]
        if a.json:
            print(json.dumps({"count": len(hits), "arch": a.arch, "slice_offset": hex(off),
                              "hits": [{"entry": hex(e), "target": hex(t)} for e, t in hits]}, indent=2))
        else:
            print(f"fixups targeting [{hex(lo)},{hex(hi)}): {len(hits)}"
                  f"  (addresses slice-relative; fat file offset = +{hex(off)})")
            for e, t in hits:
                print(f"  entry {hex(e)} -> {hex(t)}")
        return

    total = len(fix)
    if a.json:
        print(json.dumps({"slice_offset": off, "segments": segs, "stats": stats,
                          "rebases": total,
                          "targets_by_segment": {
                              s["name"]: sum(1 for _e, t in fix
                                             if s["vmaddr"] <= t < s["vmaddr"] + s["vmsize"])
                              for s in segs}}, indent=2))
    else:
        print(f"arch={a.arch} slice_offset={hex(off)} rebases={total}")
        for s in segs:
            c = sum(1 for _e, t in fix if s["vmaddr"] <= t < s["vmaddr"] + s["vmsize"])
            print(f"  {s['name']:14s} vm={hex(s['vmaddr'])} targets={c}")


if __name__ == "__main__":
    sys.exit(main())
