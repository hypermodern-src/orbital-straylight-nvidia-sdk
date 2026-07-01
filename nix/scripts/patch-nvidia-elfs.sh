#!/usr/bin/env bash
# Patches ELF files in the NVIDIA SDK with proper library paths.
#
# Usage: patch-nvidia-elfs.sh <output-dir> <bundle-libs> <system-libs> <dynamic-linker>
#
# Ordering is load-bearing. NVIDIA's redistributables (nsight, etc.) ship their
# OWN complete Qt6 and various support libraries under their host dirs. We must
# let those bundled libs win: if a nixpkgs Qt (or other lib) lands on RPATH
# ahead of the bundle, the process mixes two ABI-incompatible builds of the same
# library and dies with e.g. "libQt6DBus.so.6: undefined symbol ...
# Qt_6_PRIVATE_API". So RPATH order is:
#
#   $out/lib : $out/lib64 : <bundle-libs> : <system-libs> : <existing>
#
# i.e. the artifact's own libs first, and nixpkgs only fills the genuine system
# floor (glibc-adjacent, glib, fontconfig, X11/xcb, GL, …) that the bundle does
# not and cannot carry. We deliberately do NOT inject nixpkgs Qt.

set -euo pipefail

output_dir="$1"
bundle_libs="$2"
system_libs="$3"
dynamic_linker="$4"

echo "Patching ELF files (bundle libs take precedence over the system floor)..."

find "$output_dir" -type f \( -executable -o -name "*.so*" \) 2>/dev/null | while read -r f; do
	# Skip symlinks
	[ -L "$f" ] && continue

	# Skip non-ELF files
	file "$f" | grep -q ELF || continue

	# Set interpreter for executables
	if file "$f" | grep -q "executable"; then
		patchelf --set-interpreter "$dynamic_linker" "$f" 2>/dev/null || true
	fi

	# Update rpath: bundle first, then the nixpkgs system floor, then whatever the
	# object already had. Bundle-before-system is what prevents the Qt (and other)
	# version-skew crashes.
	existing=$(patchelf --print-rpath "$f" 2>/dev/null || echo "")
	new_rpath="$output_dir/lib:$output_dir/lib64:$bundle_libs:$system_libs${existing:+:$existing}"
	patchelf --force-rpath --set-rpath "$new_rpath" "$f" 2>/dev/null || true
done

echo "ELF patching complete."
