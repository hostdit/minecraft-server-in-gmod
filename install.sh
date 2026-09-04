#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
GM="${GMOD_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/GarrysMod/garrysmod}"

[ -d "$GM" ] || { echo "GMod not at: $GM"; echo "set GMOD_DIR=/path/to/garrysmod and rerun" >&2; exit 1; }
[ -f gmsv_mcsock_osx64.dll ] || [ -f gmsv_mcsock_win64.dll ] || { echo "run ./build.sh first" >&2; exit 1; }

mkdir -p "$GM/lua/bin" "$GM/lua/mcserver" "$GM/lua/autorun/server" "$GM/data"
for m in gmsv_mcsock_osx64.dll gmsv_mcsock_win64.dll; do
	[ -f "$m" ] && cp "$m" "$GM/lua/bin/"
done
cp garrysmod/lua/mcserver/proto.lua "$GM/lua/mcserver/"
cp garrysmod/lua/autorun/server/mcserver.lua "$GM/lua/autorun/server/"
[ -f mc_favicon.png ] && cp mc_favicon.png "$GM/data/"

echo "installed into $GM"
ls "$GM/lua/bin/" | grep mcsock
find "$GM/lua/mcserver" "$GM/lua/autorun/server/mcserver.lua"
