# Archive integrity admission

BLA is not a general-purpose ZIP/APK repacker. Archive protection now rejects input
it cannot fully represent, rather than silently omitting members or treating failed
DEFLATE decoding as original file data.

## Supported ZIP subset

- Single-disk classic ZIP, terminal EOCD with no archive comment or trailing bytes.
- Contiguous local records followed immediately by the complete central directory;
  every entry's name, offset, flags, sizes, method and CRC must agree.
- Stored or raw-DEFLATE entries; decoded length and CRC must match. DEFLATE must
  consume exactly its declared compressed stream.
- Unique, printable ASCII filenames; zero flags, timestamps, extra fields,
  entry comments and file attributes. Required ZIP version must be at most 2.0.
- At most 64 MiB decoded per entry and 256 MiB total declared decoded content.
  Inflater output is separately capped by the declared length, so false size
  claims cannot cause unbounded decompression.

This intentionally excludes many perfectly valid ZIPs, including ordinary archives
with timestamps or Unix permission attributes. Metadata is rejected rather than
silently discarded. Encryption, data descriptors, ZIP64, multi-volume archives,
unsupported encodings/compression, prepended executables, gaps and signing blocks
are unsupported. `readZipEntries` also enforces this subset; therefore auditing
unsupported archives fails explicitly instead of returning a partial inventory.

Protection reserves nine output entries below the classic ZIP count sentinel, so
inputs may contain at most 65,525 entries regardless of intensity.

Protection additionally refuses AndroidManifest.xml, signature entries under
META-INF (`.SF`, `.RSA`, `.DSA`, `.EC`) and existing entries in the reserved
`assets/enclave/` or `enclave/` output namespaces, including regular files named
exactly `assets`, `assets/enclave`, or `enclave` that would collide with new descendants. These checks are conservative
admission rules, not a universal signature detector or signature verification.

## APKs and failure behavior

All explicitly identified APK protection requests, including unsigned fixtures,
throw `UnsupportedApkProtectionError`. BLA does not implement signing, re-signing,
alignment preservation or APK signature validation. Renaming an APK does not make
it a supported package. ZIP rejection throws `UnsupportedArchiveError`.

The file engine preflights before audit, payload generation, directory creation or
output writes. On admission failure, input and existing output remain unchanged,
including in-place requests. CLI and MCP propagate these failures through their
existing error handling. No installability or real Android runtime claim is made.

The existing admitted ZIP transformation remains unchanged. Embedded JS/WASM is
copied, not recursively protected. Tests establish small fixture content
preservation and rejection behavior, not anti-analysis effectiveness, complete ZIP
compatibility, or production application correctness.
