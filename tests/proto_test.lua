package.path = "garrysmod/lua/?.lua;" .. package.path
local P = require("mcserver.proto")

local fails = 0
local function eq(name, got, want)
	if got ~= want then
		fails = fails + 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. " want " .. tostring(want))
	end
end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end

eq("varint 0", hex(P.varint(0)), "00")
eq("varint 127", hex(P.varint(127)), "7f")
eq("varint 128", hex(P.varint(128)), "8001")
eq("varint 300", hex(P.varint(300)), "ac02")
eq("varint max", hex(P.varint(2147483647)), "ffffffff07")
eq("varint -1", hex(P.varint(-1)), "ffffffff0f")
for _, n in ipairs({ 0, 1, 127, 128, 300, 25565, 2147483647, -1, -2147483648 }) do
	local v, i = P.readVarint(P.varint(n) .. "zz", 1)
	eq("varint rt " .. n, v, n)
	eq("varint rt idx " .. n, i, #P.varint(n) + 1)
end
eq("varint partial", P.readVarint("\128", 1), nil)

eq("i32 -1", hex(P.i32(-1)), "ffffffff")
eq("i32 -2", hex(P.i32(-2)), "fffffffe")
eq("i32 rt", (P.readI32(P.i32(-123456), 1)), -123456)
eq("i16 rt", (P.readI16(P.i16(-7), 1)), -7)
eq("u16", hex(P.u16(25565)), "63dd")
eq("i8 rt", (P.readI8(P.i8(-3), 1)), -3)

eq("f64 1.0", hex(P.f64(1.0)), "3ff0000000000000")
eq("f64 -2.0", hex(P.f64(-2.0)), "c000000000000000")
eq("f64 0.1", hex(P.f64(0.1)), "3fb999999999999a")
eq("f64 0", hex(P.f64(0)), "0000000000000000")
for _, v in ipairs({ 0, -0.5, 8.5, 1234.5678, -3.25e10, 1e-5, 12345678.9, -0.000123 }) do
	eq("f64 rt " .. v, (P.readF64(P.f64(v), 1)), v)
end
eq("f32 1.0", hex(P.f32(1.0)), "3f800000")
eq("f32 -2.5", hex(P.f32(-2.5)), "c0200000")
eq("f32 0.05", hex(P.f32(0.05)), "3d4ccccd")
eq("f32 90 rt", (P.readF32(P.f32(90), 1)), 90)
eq("f32 -180 rt", (P.readF32(P.f32(-180), 1)), -180)

eq("pos 1,2,3", hex(P.pos(1, 2, 3)), "0000004008000003")
for _, c in ipairs({ { 1, 2, 3 }, { -1, 0, -1 }, { -32, 255, 47 }, { 1000, 4095 - 4096, -1000 } }) do
	local x, y, z, i = P.readPos(P.pos(c[1], c[2], c[3]), 1)
	eq("pos rt x", x, c[1]); eq("pos rt y", y, c[2]); eq("pos rt z", z, c[3]); eq("pos rt i", i, 9)
end

local ch = P.chunk(0, 0, { { 7, 0 }, { 3, 0 }, { 3, 0 }, { 2, 0 } })
local len, i = P.readVarint(ch, 1)
eq("chunk frame len", len, #ch - i + 1)
local id, j = P.readVarint(ch, i)
eq("chunk id", id, 0x21)
local cx; cx, j = P.readI32(ch, j)
local cz; cz, j = P.readI32(ch, j)
eq("chunk cx", cx, 0)
eq("chunk ground", (P.readBool(ch, j)), true); j = j + 1
eq("chunk mask", (P.readU16(ch, j)), 1); j = j + 2
local size; size, j = P.readVarint(ch, j)
eq("chunk size", size, 12544)
eq("chunk body", #ch - j + 1, 12544)
eq("chunk bedrock", hex(ch:sub(j, j + 1)), "7000")
eq("chunk grass", hex(ch:sub(j + 3 * 512, j + 3 * 512 + 1)), "2000")
eq("chunk air", hex(ch:sub(j + 4 * 512, j + 4 * 512 + 1)), "0000")

local a = P.frame(0x00, P.varint(47) .. P.str("localhost") .. P.u16(25565) .. P.varint(2))
local b = P.frame(0x00, P.str("Ry"))
local pk, rest = P.split(a .. b .. "\5\0")
eq("split count", #pk, 2)
eq("split rest", hex(rest), "0500")
local proto, addr, port, nxt = P.readHandshake(pk[1].body)
eq("hs proto", proto, 47); eq("hs addr", addr, "localhost"); eq("hs port", port, 25565); eq("hs next", nxt, 2)
eq("login name", P.readLoginStart(pk[2].body), "Ry")

local pl = P.f64(8.5) .. P.f64(4) .. P.f64(-3.25) .. P.f32(90) .. P.f32(-10) .. "\1"
local x, y, z, yaw, pitch = P.readPositionLook(pl)
eq("pl x", x, 8.5); eq("pl y", y, 4); eq("pl z", z, -3.25); eq("pl yaw", yaw, 90); eq("pl pitch", pitch, -10)

local st, dx, dy, dz, face = P.readDigging("\0" .. P.pos(-5, 3, 9) .. "\1")
eq("dig status", st, 0); eq("dig x", dx, -5); eq("dig y", dy, 3); eq("dig z", dz, 9); eq("dig face", face, 1)

local px, py, pz, pf, pid, pdmg = P.readPlacement(P.pos(1, 3, 2) .. "\1" .. P.i16(35) .. "\1" .. P.i16(14) .. "\0" .. "\8\16\8")
eq("place x", px, 1); eq("place face", pf, 1); eq("place id", pid, 35); eq("place dmg", pdmg, 14)
local _, _, _, _, nid = P.readPlacement(P.pos(1, 3, 2) .. "\255" .. P.i16(-1) .. "\8\16\8")
eq("place empty", nid, nil)

eq("blockchange", hex(P.blockChange(1, 2, 3, 35, 14)), "0b23" .. "0000004008000003" .. "be04")
eq("keepalive", hex(P.keepAlive(1)), "020001")
eq("join", hex(P.joinGame(1)), "0f01" .. "00000001" .. "01000101" .. "04666c6174" .. "00")
eq("explosion", #P.explosion(0, 0, 0, 3, { { 1, -1, 0 }, { 2, 0, 0 } }), 1 + 1 + 16 + 4 + 6 + 12)

local mb = P.multiBlockChange(1, -2, { { 3, 68, 5, 35, 14 }, { 15, 4, 0, 1, 0 } })
local mlen, mi = P.readVarint(mb, 1)
eq("mbc frame len", mlen, #mb - mi + 1)
eq("mbc id", (P.readVarint(mb, mi)), 0x22)
local mcx, mj = P.readI32(mb, mi + 1)
local mcz; mcz, mj = P.readI32(mb, mj)
eq("mbc cx", mcx, 1); eq("mbc cz", mcz, -2)
local cnt; cnt, mj = P.readVarint(mb, mj)
eq("mbc count", cnt, 2)
eq("mbc rec1 horiz", (P.readU8(mb, mj)), 3 * 16 + 5)
eq("mbc rec1 y", (P.readU8(mb, mj + 1)), 68)
eq("mbc rec1 state", (P.readVarint(mb, mj + 2)), 35 * 16 + 14)

if fails == 0 then print("all passed") else os.exit(1) end
