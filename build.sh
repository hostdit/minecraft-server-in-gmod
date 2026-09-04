#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
TARGET="${1:-mac}"
SRC="module/mcsock.cpp"
COMMON=(-std=c++17 -O2 -Imodule/include)

buildWindows() {
	OUT="gmsv_mcsock_win64.dll"
	if command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
		echo "using mingw"
		x86_64-w64-mingw32-g++ "${COMMON[@]}" -shared -static "$SRC" -o "$OUT" -lws2_32
	elif command -v zig >/dev/null 2>&1; then
		echo "using zig"
		zig c++ -target x86_64-windows-gnu "${COMMON[@]}" -shared "$SRC" -o "$OUT" -lws2_32
	else
		echo "need mingw or zig: brew install mingw-w64   (or) brew install zig" >&2
		exit 1
	fi
	file "$OUT"
	file "$OUT" | grep -q "PE32+" || { echo "not a 64-bit windows DLL" >&2; exit 1; }
	echo "built $OUT, copy it to garrysmod/lua/bin/ on the Windows machine"
}

buildMac() {
	OUT="gmsv_mcsock_osx64.dll"
	echo "== probing for an x86_64 toolchain =="
	printf 'int main(){return 0;}' > /tmp/mcprobe.c
	if clang -arch x86_64 /tmp/mcprobe.c -o /tmp/mcprobe 2>/dev/null && /tmp/mcprobe 2>/dev/null; then
		echo "clang can target x86_64, using it"
		clang++ -arch x86_64 -mmacosx-version-min=10.15 -pthread -shared -fPIC "${COMMON[@]}" "$SRC" -o "$OUT"
	elif command -v zig >/dev/null 2>&1; then
		echo "clang has no x86_64 slice, using zig"
		zig c++ -target x86_64-macos.11 -pthread -shared -fPIC "${COMMON[@]}" "$SRC" -o "$OUT"
	else
		echo "no x86_64 toolchain. install zig with: brew install zig" >&2
		exit 1
	fi
	echo
	echo "== verifying =="
	file "$OUT"
	file "$OUT" | grep -q x86_64 || { echo "WRONG ARCH, this will not load" >&2; exit 1; }
	nm -gU "$OUT" | grep -q "T _gmod13_open" || { echo "gmod13_open missing" >&2; exit 1; }
	nm -gU "$OUT" | grep -q "T _gmod13_close" || { echo "gmod13_close missing" >&2; exit 1; }
	echo "gmod13_open and gmod13_close exported"
	xattr -cr "$OUT"
	codesign -s - -f "$OUT"
	echo
	echo "built $OUT"
}

case "$TARGET" in
	mac|osx|macos) buildMac ;;
	win|windows) buildWindows ;;
	both) buildMac; echo; buildWindows ;;
	*) echo "usage: ./build.sh [mac|win|both]" >&2; exit 1 ;;
esac
