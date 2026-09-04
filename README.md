# Minecraft server in Garry's Mod

A working Minecraft 1.8.9 server running inside Garry's Mod. Real protocol and no server software. The process listening on port 25565 is Garry's Mod.

The world is the map. Build in Minecraft and the blocks appear as physics props, then physgun one and the block moves back in the world. Spawn anything in Garry's Mod and it gets voxelised into Minecraft, still moving. The Minecraft player is a ragdoll you can pick up and carry through the world too.

## Why

Excel, Outlook, OBS, Obsidian, Blender, PowerPoint, VLC, Word, The Sims 4, Terraria, FL Studio, VS Code, DaVinci Resolve, Unity, now Garry's Mod.

Every previous episode was software that had no business hosting anything. This one is a game with physics, which is the point. Minecraft blocks don't fall over. These ones do.

## What it does

- Server list ping with MOTD, player count and a favicon
- Offline mode login, no encryption
- Flat world, 5x5 chunks of bedrock, dirt and grass
- Creative mode
- Keep-alives
- Chat, with a command in it
- Every block placed spawns a real `prop_physics`
- Physgun a block and it moves in Minecraft as it moves, rounded to the nearest cell
- Drop it and gravity carries it, updating the whole way down, freezing wherever it lands
- Shoot a block or blow one up and it breaks in Minecraft
- Blocks are ordinary props, so the toolgun works: weld a contraption and the whole shape moves through the Minecraft world as one
- Anything you spawn in Garry's Mod is voxelised from its collision mesh and appears as wool, tracking as it moves
- The Minecraft player is a ragdoll. Physgun it and the direction reverses: the ragdoll drives the player's position
- A nuke that expands from the player, throwing every prop and wiping the floor cell by cell, ending on a disconnect

## What it doesn't do

Almost everything else. No mobs, no inventory persistence, no world saving, no survival, no other dimensions.

A few limits in this build:

**One player.** Several connections are accepted so the server list ping and the join don't fight each other, but only one of them gets to be the player. A second login kicks the first (it is possible I just didn't build it).

**Sixteen blocks tall.** The world is one chunk section, so the chunk payload stays at 12,544 bytes.

**Eighty blocks square.** Props that leave that region stop existing in Minecraft.

**Nothing is saved.** Close Garry's Mod and the world is gone. The blocks live in the map's entity list, not a Minecraft world file.

It's a server in the sense that a client connects to it and receives a world. Set your expectations accordingly.

## Requirements

Garry's Mod.

Minecraft Java 1.8.9, protocol 47.

macOS or Windows. Built and tested on macOS 27, Apple Silicon, with Garry's Mod running on x86_64.

## Install

1. Steam, right click Garry's Mod, Properties, Betas, select x86-64 - Chromium + 64-bit binaries. Let it download.

2. Build the module. It's about 250 lines of sockets and a thread, and it doesn't need a copy of the game to compile.

## macOS:

cd minecraft-server-in-gmod
./build.sh

The script probes whether your clang can build and run x86_64 and uses it if so. If it can't, install zig and rerun, and it cross compiles instead:

brew install zig
./build.sh

It refuses to produce an arm64 binary. The module header picks its lua_State layout from __x86_64__, so an architecture mismatch is corrupt memory.

## Windows, from an x64 Native Tools Command Prompt for VS:

cd minecraft-server-in-gmod
build.bat

Install Build Tools for Visual Studio with the C++ workload if you're not comfortable with cl.

3. Install.

./install.sh          macOS
install.bat           Windows

Which puts three files in the game:

garrysmod/lua/bin/gmsv_mcsock_osx64.dll     (gmsv_mcsock_win64.dll on Windows)
garrysmod/lua/mcserver/proto.lua
garrysmod/lua/autorun/server/mcserver.lua

Set GMOD_DIR first if your Steam library isn't in the default place.

4. Start a game. Set the dropdown to Multiplayer, 2 players, not Single Player. Singleplayer Source pauses the entire game when the window loses focus, and you'll be inside Minecraft the whole time.

5. Open the console. You want [mc] build ... listening on 25565 (fd N, ok, heartbeat thread up) and no red errors.

### Favicon

A 64x64 PNG at `garrysmod/data/mc_favicon.png`. Anything other than exactly 64x64 gets dropped by the client.

The path is checked on every server list ping, so a newly added icon shows up without restarting anything, just refresh it in Minecraft.

## Use

**1.** The server starts with the map. Nothing to run.

**2.** Check it's real if you really want to:

```
lsof -nP -iTCP:25565 -sTCP:LISTEN
```

The pid holding the port is gmod. Same pid appears on the established connection once a client joins.

**3.** Connect Minecraft 1.8.9 to `localhost` via Add Server or Direct Connect.

**4.** Build something, then pick it up.

### Console commands

| Command | Effect |
| --- | --- |
| `mc_start` | starts the listener |
| `mc_stop` | stops it and drops every connection |
| `mc_reload` | re-reads the Lua from disk and restarts the listener, keeping the world |
| `mc_status` | build, pid, socket state, queue depth, connections, prop and voxel counts |
| `mc_origin` | aim at the ground and run it to set where Minecraft spawn sits in the map |
| `mc_probe` | prints the world bounds in Source coordinates and whether you're inside them |
| `mc_rescan` | voxelises everything already in the map |
| `mc_nuke` | same as typing `nuke` in Minecraft chat |

### Convars

| Convars | Default | Effect |
| --- | --- | --- |
| `mc_port` | 25565 | |
| `mc_scale` | 24 | Source units per block |
| `mc_model` | `cube05x05x05` | the prop a placed block spawns as |
| `mc_ragdoll` | `models/Kleiner.mdl` | set this to a Minecraft player model from the workshop |
| `mc_hip` | 0.8 | blocks between the ragdoll root and its feet |
| `mc_voxel` | 1 | voxelise props spawned in Garry's Mod |
| `mc_voxel_max` | 1200 | per-prop block cap |
| `mc_nuke_speed` | 0.8 | blocks of blast radius per tick |
| `mc_motd` | | |

`mc_scale` is the dial worth playing with. At 24 a car is about eight blocks long. At 12, with `mc_model` set to `models/hunter/blocks/cube025x025x025.mdl`, a car is sixteen blocks and much more recognisable, at the cost of placed blocks being small cubes in Garry's Mod.

Convars are archived, so the value in `garrysmod/cfg/config.cfg` beats the default in the source once you've set one.

## Troubleshooting

**`Couldn't load module library`.** Wrong architecture or unsigned. Rerun `./build.sh`, which checks both.

**Client times out.** Shouldn't happen, the heartbeat is on its own thread. If it does, `mc_status` reports the outbound queue depth, and a growing number means the socket is blocked.

**Your edits don't take effect.** Lua needs `mc_reload`. The module needs a full restart. The build stamp is printed on start and by `mc_status`.

**Spawned props show nothing in Minecraft.** The console shows it. `outside the Minecraft world at block x,y,z` is the usual one. Run `mc_probe`, then `mc_origin` while aiming at the ground where you want spawn.

**Ragdoll sunk into the floor or floating.** `mc_hip`.

**Framerate drops with a lot of blocks.** Every block is a real physics prop. That's the whole idea, but there's a limit, and `mc_voxel_max` is where to start.

## How it works

**Where the code lives.** A listen server runs the game and the server in one process, so the socket sits inside the same binary that's drawing the map. `mcsock.cpp` is the only compiled part: non-blocking POSIX sockets, seven functions, no protocol knowledge at all. Everything about Minecraft is Lua.

**The heartbeat thread.** Source games throttle or pause when the window isn't focused, and you're in Minecraft the whole time. So the module owns the outbound buffer and runs a thread that drains it, injecting a keepalive whenever it's been quiet for two seconds. Lua hands it whole packets, so the thread can't cut a packet in half. Nothing on the send path depends on the game ticking.

**Chunks.** The reason this targets 1.8.9. In 1.8 a chunk section is a flat array of `(id << 4) | meta` shorts, then block light, then sky light. 12,544 bytes for one section plus biome data, sent uncompressed. Modern versions use palette encoded, bit packed longs and expect zlib. The join sequence is 25 chunks, so about 314KB in one burst.

**Floats without a float library.** Lua 5.1 has no way to reinterpret a number as bytes. Doubles and floats are built out of `math.frexp` and read back with `math.ldexp`, and the 64-bit block position is handled as two 32-bit halves because LuaJIT numbers can't hold it exactly.

**The reverse direction.** Every tick, any prop that isn't frozen has its position rounded to a cell and compared to the cell it was last filed under. A change sends air to the old cell and the block to the new one. Physgunning, dropping, exploding and falling all produce the same signal, so one loop covers all of them. When the physics object goes to sleep the prop is frozen again, wherever it happens to be.

**Voxelising.** `GetMeshConvexes` gives the collision mesh in local space as triangles. Triangle normals from a convex hull point outwards, so each convex becomes a set of planes and a point is inside if it's behind all of them. That runs once per prop and the result is cached in local space, so moving a prop is a transform per voxel and a Multi Block Change per chunk. Props with no readable mesh fall back to a filled bounding box.

**The ragdoll.** `Entity:GetPos` on a ragdoll doesn't follow the bones, so the position comes off physics object zero. While it's held, incoming position packets are ignored and the ragdoll drives the client instead, which is what makes picking the player up work instead of fighting them.

## Previous episodes

- Excel: [github.com/hostdit/minecraft-server-in-excel](https://github.com/hostdit/minecraft-server-in-excel)
- Outlook: [github.com/hostdit/minecraft-server-in-outlook](https://github.com/hostdit/minecraft-server-in-outlook)
- OBS: [github.com/hostdit/minecraft-server-in-obs](https://github.com/hostdit/minecraft-server-in-obs)
- Obsidian: [github.com/hostdit/minecraft-server-in-obsidian](https://github.com/hostdit/minecraft-server-in-obsidian)
- Blender: [github.com/hostdit/minecraft-server-in-blender](https://github.com/hostdit/minecraft-server-in-blender)
- PowerPoint: [github.com/hostdit/minecraft-server-in-powerpoint](https://github.com/hostdit/minecraft-server-in-powerpoint)
- VLC: [github.com/hostdit/minecraft-server-in-vlc](https://github.com/hostdit/minecraft-server-in-vlc)
- Word: [github.com/hostdit/minecraft-server-in-word](https://github.com/hostdit/minecraft-server-in-word)
- The Sims 4: [github.com/hostdit/minecraft-server-in-sims](https://github.com/hostdit/minecraft-server-in-sims)
- Terraria: [github.com/hostdit/minecraft-server-in-terraria](https://github.com/hostdit/minecraft-server-in-terraria)
- FL Studio: [github.com/hostdit/minecraft-server-in-fl-studio](https://github.com/hostdit/minecraft-server-in-fl)
- VS Code: [github.com/hostdit/minecraft-server-in-vscode](https://github.com/hostdit/minecraft-server-in-vscode)
- DaVinci Resolve: [github.com/hostdit/minecraft-server-in-davinci-resolve](https://github.com/hostdit/minecraft-server-in-dr)
- Unity: [github.com/hostdit/minecraft-server-in-unity](https://github.com/hostdit/minecraft-server-in-unity)

## Licence

MIT. Do what you like with it.
