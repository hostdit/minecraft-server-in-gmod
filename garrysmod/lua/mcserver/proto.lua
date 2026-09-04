local floor, frexp, ldexp, char, byte, rep, concat = math.floor, math.frexp, math.ldexp, string.char, string.byte, string.rep, table.concat

local P = {}

local function u32(n)
	return char(floor(n / 16777216) % 256, floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
end

local function rd32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	return a * 16777216 + b * 65536 + c * 256 + d, i + 4
end

function P.u8(n) return char(n % 256) end
function P.i8(n) return char(n % 256) end
function P.bool(b) return b and "\1" or "\0" end
function P.u16(n) return char(floor(n / 256) % 256, n % 256) end
function P.i16(n) return P.u16(n % 65536) end
function P.i32(n) return u32(n % 4294967296) end

function P.varint(n)
	n = n % 4294967296
	local out = {}
	repeat
		local b = n % 128
		n = floor(n / 128)
		if n > 0 then b = b + 128 end
		out[#out + 1] = char(b)
	until n == 0
	return concat(out)
end

function P.str(s) return P.varint(#s) .. s end

function P.f64(v)
	local sign = 0
	if v < 0 or (v == 0 and 1 / v < 0) then sign = 1; v = -v end
	local mant, exp
	if v == 0 then
		mant, exp = 0, 0
	elseif v == math.huge then
		mant, exp = 0, 2047
	else
		local m, e = frexp(v)
		exp = e + 1022
		if exp <= 0 then
			mant, exp = 0, 0
		else
			mant = (m * 2 - 1) * 4503599627370496
		end
	end
	local hi = floor(mant / 4294967296)
	local lo = mant - hi * 4294967296
	return u32(hi + exp * 1048576 + sign * 2147483648) .. u32(lo)
end

function P.f32(v)
	local sign = 0
	if v < 0 or (v == 0 and 1 / v < 0) then sign = 1; v = -v end
	local mant, exp
	if v == 0 then
		mant, exp = 0, 0
	elseif v == math.huge then
		mant, exp = 0, 255
	else
		local m, e = frexp(v)
		exp = e + 126
		if exp <= 0 then
			mant, exp = 0, 0
		elseif exp >= 255 then
			mant, exp = 0, 255
		else
			mant = floor((m * 2 - 1) * 8388608 + 0.5)
			if mant >= 8388608 then mant = 0; exp = exp + 1 end
		end
	end
	return u32(sign * 2147483648 + exp * 8388608 + mant)
end

function P.pos(x, y, z)
	local X, Y, Z = x % 67108864, y % 4096, z % 67108864
	return u32(X * 64 + floor(Y / 64)) .. u32((Y % 64) * 67108864 + Z)
end

function P.readVarint(s, i)
	local n, mul = 0, 1
	for k = 0, 4 do
		local b = byte(s, i + k)
		if not b then return nil end
		n = n + (b % 128) * mul
		if b < 128 then
			if n >= 2147483648 then n = n - 4294967296 end
			return n, i + k + 1
		end
		mul = mul * 128
	end
	return nil
end

function P.readU8(s, i) return byte(s, i), i + 1 end
function P.readI8(s, i)
	local b = byte(s, i)
	if b >= 128 then b = b - 256 end
	return b, i + 1
end
function P.readBool(s, i) return byte(s, i) ~= 0, i + 1 end
function P.readU16(s, i)
	local a, b = byte(s, i, i + 1)
	return a * 256 + b, i + 2
end
function P.readI16(s, i)
	local n, j = P.readU16(s, i)
	if n >= 32768 then n = n - 65536 end
	return n, j
end
function P.readI32(s, i)
	local n, j = rd32(s, i)
	if n >= 2147483648 then n = n - 4294967296 end
	return n, j
end
function P.readStr(s, i)
	local len, j = P.readVarint(s, i)
	return s:sub(j, j + len - 1), j + len
end

function P.readF64(s, i)
	local hi, j = rd32(s, i)
	local lo, k = rd32(s, j)
	local sign = floor(hi / 2147483648)
	local exp = floor(hi / 1048576) % 2048
	local mant = (hi % 1048576) * 4294967296 + lo
	local v
	if exp == 0 then
		v = ldexp(mant, -1074)
	elseif exp == 2047 then
		v = mant == 0 and math.huge or 0 / 0
	else
		v = ldexp(1 + mant / 4503599627370496, exp - 1023)
	end
	if sign == 1 then v = -v end
	return v, k
end

function P.readF32(s, i)
	local n, j = rd32(s, i)
	local sign = floor(n / 2147483648)
	local exp = floor(n / 8388608) % 256
	local mant = n % 8388608
	local v
	if exp == 0 then
		v = ldexp(mant, -149)
	elseif exp == 255 then
		v = mant == 0 and math.huge or 0 / 0
	else
		v = ldexp(1 + mant / 8388608, exp - 127)
	end
	if sign == 1 then v = -v end
	return v, j
end

function P.readPos(s, i)
	local hi, j = rd32(s, i)
	local lo, k = rd32(s, j)
	local x = floor(hi / 64)
	local y = (hi % 64) * 64 + floor(lo / 67108864)
	local z = lo % 67108864
	if x >= 33554432 then x = x - 67108864 end
	if y >= 2048 then y = y - 4096 end
	if z >= 33554432 then z = z - 67108864 end
	return x, y, z, k
end

function P.frame(id, body)
	body = body or ""
	local inner = P.varint(id) .. body
	return P.varint(#inner) .. inner
end

function P.split(buf)
	local out, i = {}, 1
	while true do
		local len, j = P.readVarint(buf, i)
		if not len or #buf < j + len - 1 then break end
		local id, k = P.readVarint(buf, j)
		out[#out + 1] = { id = id, body = buf:sub(k, j + len - 1) }
		i = j + len
	end
	return out, buf:sub(i)
end

function P.chunk(cx, cz, layers)
	local parts = {}
	for y = 1, 16 do
		local b = layers[y]
		local v = b and (b[1] * 16 + (b[2] or 0)) or 0
		parts[y] = rep(char(v % 256, floor(v / 256)), 256)
	end
	local data = concat(parts) .. rep("\0", 2048) .. rep("\255", 2048) .. rep("\1", 256)
	return P.frame(0x21, P.i32(cx) .. P.i32(cz) .. "\1" .. P.u16(1) .. P.varint(#data) .. data)
end

function P.statusResponse(json) return P.frame(0x00, P.str(json)) end
function P.pong(payload) return P.frame(0x01, payload) end
function P.loginSuccess(uuid, name) return P.frame(0x02, P.str(uuid) .. P.str(name)) end
function P.joinGame(eid) return P.frame(0x01, P.i32(eid) .. "\1\0\1\1" .. P.str("flat") .. "\0") end
function P.spawnPos(x, y, z) return P.frame(0x05, P.pos(x, y, z)) end
function P.posLook(x, y, z, yaw, pitch) return P.frame(0x08, P.f64(x) .. P.f64(y) .. P.f64(z) .. P.f32(yaw) .. P.f32(pitch) .. "\0") end
function P.keepAlive(id) return P.frame(0x00, P.varint(id)) end
function P.blockChange(x, y, z, id, meta) return P.frame(0x23, P.pos(x, y, z) .. P.varint(id * 16 + (meta or 0))) end
function P.multiBlockChange(cx, cz, records)
	local parts = { P.i32(cx), P.i32(cz), P.varint(#records) }
	for i = 1, #records do
		local r = records[i]
		parts[#parts + 1] = char((r[1] % 16) * 16 + (r[3] % 16), r[2] % 256) .. P.varint(r[4] * 16 + r[5])
	end
	return P.frame(0x22, concat(parts))
end

function P.disconnect(text) return P.frame(0x40, P.str('{"text":"' .. text .. '"}')) end
function P.abilities() return P.frame(0x39, "\13" .. P.f32(0.05) .. P.f32(0.1)) end
function P.chat(text) return P.frame(0x02, P.str('{"text":"' .. text .. '"}') .. "\0") end

function P.explosion(x, y, z, radius, records)
	local parts = { P.f32(x), P.f32(y), P.f32(z), P.f32(radius), P.i32(#records) }
	for i, r in ipairs(records) do
		parts[#parts + 1] = char(r[1] % 256, r[2] % 256, r[3] % 256)
	end
	parts[#parts + 1] = P.f32(0) .. P.f32(0) .. P.f32(0)
	return P.frame(0x27, concat(parts))
end

function P.readHandshake(b)
	local proto, i = P.readVarint(b, 1)
	local addr; addr, i = P.readStr(b, i)
	local port; port, i = P.readU16(b, i)
	local next = P.readVarint(b, i)
	return proto, addr, port, next
end

function P.readLoginStart(b) return (P.readStr(b, 1)) end

function P.readPosition(b)
	local x, i = P.readF64(b, 1)
	local y; y, i = P.readF64(b, i)
	local z; z, i = P.readF64(b, i)
	return x, y, z
end

function P.readPositionLook(b)
	local x, i = P.readF64(b, 1)
	local y; y, i = P.readF64(b, i)
	local z; z, i = P.readF64(b, i)
	local yaw; yaw, i = P.readF32(b, i)
	local pitch = P.readF32(b, i)
	return x, y, z, yaw, pitch
end

function P.readLook(b)
	local yaw, i = P.readF32(b, 1)
	local pitch = P.readF32(b, i)
	return yaw, pitch
end

function P.readDigging(b)
	local status, i = P.readI8(b, 1)
	local x, y, z, j = P.readPos(b, i)
	local face = P.readI8(b, j)
	return status, x, y, z, face
end

function P.readPlacement(b)
	local x, y, z, i = P.readPos(b, 1)
	local face; face, i = P.readI8(b, i)
	local id; id, i = P.readI16(b, i)
	if id == -1 then return x, y, z, face, nil end
	local count; count, i = P.readU8(b, i)
	local damage = P.readI16(b, i)
	return x, y, z, face, id, damage
end

return P
