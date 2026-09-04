if not SERVER then return end
if not mcsock then require("mcsock") end
local P = include("mcserver/proto.lua")

MCS = MCS or { tracked = {}, owner = {}, holes = {} }

local floor, sqrt = math.floor, math.sqrt
local cvPort = CreateConVar("mc_port", "25565", FCVAR_ARCHIVE)
local cvScale = CreateConVar("mc_scale", "24", FCVAR_ARCHIVE)
local cvModel = CreateConVar("mc_model", "models/hunter/blocks/cube05x05x05.mdl", FCVAR_ARCHIVE)
local cvRagdoll = CreateConVar("mc_ragdoll", "models/Kleiner.mdl", FCVAR_ARCHIVE)
local cvHip = CreateConVar("mc_hip", "0.8", FCVAR_ARCHIVE)
local cvNukeSpeed = CreateConVar("mc_nuke_speed", "0.8", FCVAR_ARCHIVE)
local cvVoxel = CreateConVar("mc_voxel", "1", FCVAR_ARCHIVE)
local cvVoxelMax = CreateConVar("mc_voxel_max", "1200", FCVAR_ARCHIVE)
local cvMotd = CreateConVar("mc_motd", "Running in Garry's Mod.", FCVAR_ARCHIVE)

local WORLD_MIN, WORLD_MAX = -32, 47
local FLOOR = { { 7, 0 }, { 3, 0 }, { 3, 0 }, { 2, 0 } }
local SPAWN = { 8.5, 4, 8.5 }

local origin = Vector(0, 0, 0)
local conns, player, rag, nuke = {}, nil, MCS.rag, nil
local tracked, owner, holes = MCS.tracked, MCS.owner, MCS.holes
local nextTick, keepId, sentBytes = 0, 0, 0

local WOOL = {
	{ 234, 234, 234 }, { 235, 125, 53 }, { 190, 73, 200 }, { 105, 138, 211 }, { 195, 182, 40 }, { 60, 180, 50 },
	{ 216, 130, 158 }, { 63, 63, 63 }, { 155, 165, 165 }, { 40, 120, 140 }, { 125, 60, 180 }, { 45, 55, 145 },
	{ 80, 50, 30 }, { 55, 75, 25 }, { 165, 40, 35 }, { 25, 22, 22 },
}
local PALETTE = {
	[1] = { 125, 125, 125 }, [2] = { 95, 159, 53 }, [3] = { 134, 96, 67 }, [4] = { 100, 100, 100 }, [5] = { 157, 127, 78 },
	[7] = { 60, 60, 60 }, [12] = { 219, 211, 160 }, [17] = { 102, 81, 50 }, [20] = { 200, 230, 255 }, [24] = { 216, 205, 158 },
	[41] = { 250, 230, 60 }, [42] = { 220, 220, 220 }, [45] = { 150, 80, 70 }, [46] = { 200, 50, 40 }, [49] = { 20, 18, 30 },
	[57] = { 100, 230, 230 }, [79] = { 160, 200, 255 }, [80] = { 245, 245, 245 }, [87] = { 110, 50, 50 }, [89] = { 250, 200, 120 },
	[98] = { 120, 120, 120 }, [152] = { 170, 30, 20 }, [155] = { 235, 230, 225 }, [173] = { 30, 30, 30 },
}

local function colourOf(id, meta)
	local c = (id == 35 or id == 159 or id == 95) and WOOL[(meta or 0) + 1] or PALETTE[id] or { 160, 160, 160 }
	return Color(c[1], c[2], c[3], id == 20 and 120 or 255)
end

local function S() return cvScale:GetFloat() end
local function toSrc(x, y, z) return origin + Vector(x * S(), -z * S(), y * S()) end
local function toMc(v) local d = v - origin; local s = S(); return d.x / s, d.z / s, -d.y / s end
local function cellOf(v) local x, y, z = toMc(v); return floor(x), floor(y), floor(z) end
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function inBounds(x, y, z) return x >= WORLD_MIN and x <= WORLD_MAX and z >= WORLD_MIN and z <= WORLD_MAX and y >= 0 and y <= 255 end
local function isFloor(x, y, z) return inBounds(x, y, z) and y <= 3 and not holes[key(x, y, z)] end

local function send(pkt)
	if not player or player.state ~= 3 then return end
	player.out[#player.out + 1] = pkt
end

local function sendAir(x, y, z) send(P.blockChange(x, y, z, 0, 0)) end

local function drop(c, reason)
	if not c or c.dead then return end
	c.dead = true
	conns[c.fd] = nil
	mcsock.close(c.fd)
	if player == c then player = nil end
	print("[mc] fd " .. c.fd .. " gone: " .. tostring(reason))
end

local function statusJson()
	local json = '{"version":{"name":"Garry\'s Mod","protocol":47},"players":{"max":1,"online":' .. (player and 1 or 0) .. '},"description":{"text":"' .. cvMotd:GetString() .. '"}'
	if file.Exists("mc_favicon.png", "DATA") then
		json = json .. ',"favicon":"data:image/png;base64,' .. util.Base64Encode(file.Read("mc_favicon.png", "DATA"), true) .. '"'
	end
	return json .. "}"
end

local function removeBlockEnt(e)
	tracked[e] = nil
	if e.mcCell and owner[e.mcCell] == e then owner[e.mcCell] = nil end
	if IsValid(e) then e:Remove() end
end

local function spawnBlock(x, y, z, id, meta)
	local k = key(x, y, z)
	if owner[k] then removeBlockEnt(owner[k]) end
	local e = ents.Create("prop_physics")
	e:SetModel(cvModel:GetString())
	e:SetPos(toSrc(x + 0.5, y + 0.5, z + 0.5))
	e:SetAngles(Angle(0, 0, 0))
	e:Spawn()
	e:Activate()
	if id == 20 then e:SetRenderMode(RENDERMODE_TRANSCOLOR) end
	e:SetColor(colourOf(id, meta))
	local ph = e:GetPhysicsObject()
	if ph:IsValid() then ph:EnableMotion(false) end
	e.mcBlock = { id = id, meta = meta or 0 }
	e.mcCell = k
	owner[k] = e
	tracked[e] = k
	return e
end

local voxelled = MCS.voxelled or {}
MCS.voxelled = voxelled

local function nearestWool(col)
	local best, bestD = 0, math.huge
	for i = 1, 16 do
		local w = WOOL[i]
		local d = (w[1] - col.r) ^ 2 + (w[2] - col.g) ^ 2 + (w[3] - col.b) ^ 2
		if d < bestD then best, bestD = i - 1, d end
	end
	return best
end

local function convexPlanes(mesh)
	local planes, seen = {}, {}
	for i = 1, #mesh - 2, 3 do
		local a, b, c = mesh[i].pos, mesh[i + 1].pos, mesh[i + 2].pos
		local n = (b - a):Cross(c - a)
		if n:LengthSqr() > 1e-6 then
			n:Normalize()
			local d = n:Dot(a)
			local k = string.format("%.2f %.2f %.2f %.1f", n.x, n.y, n.z, d)
			if not seen[k] then
				seen[k] = true
				planes[#planes + 1] = { n = n, d = d }
			end
		end
	end
	return planes
end

local function insideConvex(planes, p)
	for i = 1, #planes do
		if planes[i].n:Dot(p) > planes[i].d + 0.1 then return false end
	end
	return #planes > 0
end

local function voxelise(e)
	local s = S()
	local mins, maxs = e:OBBMins(), e:OBBMaxs()
	local nx = math.ceil((maxs.x - mins.x) / s)
	local ny = math.ceil((maxs.y - mins.y) / s)
	local nz = math.ceil((maxs.z - mins.z) / s)
	if (nx + 1) * (ny + 1) * (nz + 1) > cvVoxelMax:GetInt() * 8 then return nil end
	local hulls = {}
	local ph = e:GetPhysicsObject()
	if ph:IsValid() and ph.GetMeshConvexes then
		for _, m in ipairs(ph:GetMeshConvexes() or {}) do
			local pl = convexPlanes(m)
			if #pl > 0 then hulls[#hulls + 1] = pl end
		end
	end
	local function fill(useHulls)
	local out = {}
	for ix = 0, nx do
		for iy = 0, ny do
			for iz = 0, nz do
				local p = Vector(mins.x + ix * s + s * 0.5, mins.y + iy * s + s * 0.5, mins.z + iz * s + s * 0.5)
				if p.x <= maxs.x and p.y <= maxs.y and p.z <= maxs.z then
					local hit = not useHulls
					if useHulls then
						for _, pl in ipairs(hulls) do
							if insideConvex(pl, p) then hit = true break end
						end
					end
					if hit then
						out[#out + 1] = p
						if #out > cvVoxelMax:GetInt() then return nil end
					end
				end
			end
		end
	end
	return out
	end
	local pts = #hulls > 0 and fill(true) or nil
	if pts and #pts > 0 then return pts, "mesh" end
	return fill(false), "bounding box"
end

local function sendCells(cells, id, meta)
	local byChunk = {}
	for k, c in pairs(cells) do
		local ck = floor(c[1] / 16) .. "," .. floor(c[3] / 16)
		local g = byChunk[ck]
		if not g then g = { cx = floor(c[1] / 16), cz = floor(c[3] / 16), recs = {} }; byChunk[ck] = g end
		g.recs[#g.recs + 1] = { c[1], c[2], c[3], id, meta }
	end
	for _, g in pairs(byChunk) do
		for i = 1, #g.recs, 400 do
			local batch = {}
			for j = i, math.min(i + 399, #g.recs) do batch[#batch + 1] = g.recs[j] end
			send(P.multiBlockChange(g.cx, g.cz, batch))
		end
	end
end

local function syncVoxels()
	if not cvVoxel:GetBool() or not player then return end
	for e, v in pairs(voxelled) do
		if not IsValid(e) then
			sendCells(v.cells, 0, 0)
			voxelled[e] = nil
		else
			local pos, ang = e:GetPos(), e:GetAngles()
			if v.pos ~= pos or v.ang ~= ang then
				v.pos, v.ang = pos, ang
				local now = {}
				for i = 1, #v.points do
					local x, y, z = cellOf(e:LocalToWorld(v.points[i]))
					if inBounds(x, y, z) and not owner[key(x, y, z)] then
						now[key(x, y, z)] = { x, y, z }
					end
				end
				local gone, fresh = {}, {}
				for k, c in pairs(v.cells) do if not now[k] then gone[k] = c end end
				for k, c in pairs(now) do if not v.cells[k] then fresh[k] = c end end
				sendCells(gone, 0, 0)
				sendCells(fresh, 35, v.wool)
				v.cells = now
				if not v.warned then
					local n = 0
					for _ in pairs(now) do n = n + 1 end
					v.warned = true
					if n == 0 then
						local bx, by, bz = cellOf(e:GetPos())
						print(string.format("[mc] %s is outside the Minecraft world at block %d,%d,%d (x and z must be %d..%d, y 0..255)", v.model, bx, by, bz, WORLD_MIN, WORLD_MAX))
					else
						print(string.format("[mc] %s showing %d blocks in Minecraft", v.model, n))
					end
				end
			end
		end
	end
end

local function trackVoxel(e)
	if not cvVoxel:GetBool() or voxelled[e] or e.mcBlock or e.mcRag then return end
	local cls = e:GetClass()
	if cls:sub(1, 5) ~= "prop_" and cls:sub(1, 5) ~= "gmod_" then return end
	local ph = e:GetPhysicsObject()
	if not ph or not ph:IsValid() then return end
	local pts, how = voxelise(e)
	if not pts or #pts == 0 then print("[mc] cannot voxelise " .. tostring(e:GetModel()) .. " (too big or no mesh)") return end
	voxelled[e] = { points = pts, cells = {}, wool = nearestWool(e:GetColor()), pos = false, ang = false, warned = false, model = e:GetModel() }
	print("[mc] voxelised " .. tostring(e:GetModel()) .. " into " .. #pts .. " blocks via " .. how)
end

local function ragPhys(fn)
	if not IsValid(rag) then return end
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local ph = rag:GetPhysicsObjectNum(i)
		if ph:IsValid() then fn(ph) end
	end
end

local function ragPos()
	local ph = IsValid(rag) and rag:GetPhysicsObjectNum(0)
	if ph and ph:IsValid() then return ph:GetPos() end
	return rag:GetPos()
end

local function spawnRag()
	if IsValid(rag) then rag:Remove() end
	rag = nil
	rag = ents.Create("prop_ragdoll")
	rag:SetModel(cvRagdoll:GetString())
	rag:SetPos(toSrc(SPAWN[1], SPAWN[2] + cvHip:GetFloat(), SPAWN[3]))
	rag:Spawn()
	rag:Activate()
	ragPhys(function(ph) ph:EnableMotion(false) end)
	rag.mcRag = true
	MCS.rag = rag
end

local function moveRag(x, y, z)
	if not IsValid(rag) then return end
	local delta = toSrc(x, y + cvHip:GetFloat(), z) - ragPos()
	ragPhys(function(ph) ph:SetPos(ph:GetPos() + delta) end)
end

local function ragMc()
	local x, y, z = toMc(ragPos())
	return x, y - cvHip:GetFloat(), z
end

local function ragAsleep()
	local asleep = true
	ragPhys(function(ph) if not ph:IsAsleep() then asleep = false end end)
	return asleep
end

local function handlePlace(body)
	local x, y, z, face, id, meta = P.readPlacement(body)
	if face < 0 or not id or id <= 0 or id >= 256 then return end
	if face == 0 then y = y - 1 elseif face == 1 then y = y + 1 elseif face == 2 then z = z - 1
	elseif face == 3 then z = z + 1 elseif face == 4 then x = x - 1 else x = x + 1 end
	if not inBounds(x, y, z) then return end
	local px, py, pz = floor(player.x), floor(player.y), floor(player.z)
	if x == px and z == pz and (y == py or y == py + 1) then return end
	if y <= 3 and not holes[key(x, y, z)] then return end
	spawnBlock(x, y, z, id, meta)
	send(P.blockChange(x, y, z, id, meta))
end

local function handleDig(body)
	local status, x, y, z = P.readDigging(body)
	if status ~= 0 or not inBounds(x, y, z) then return end
	local k = key(x, y, z)
	if owner[k] then
		removeBlockEnt(owner[k])
	elseif isFloor(x, y, z) then
		holes[k] = true
	end
	sendAir(x, y, z)
end

local function handleLogin(c, name)
	if player and player ~= c then
		player.out[#player.out + 1] = P.disconnect("Replaced by a new connection")
		player.dying = true
		drop(player, "replaced")
	end
	player = c
	c.name = name
	c.state = 3
	c.out[#c.out + 1] = P.loginSuccess("00000000-0000-3000-8000-000000000001", name)
	send(P.joinGame(1))
	send(P.spawnPos(8, 4, 8))
	send(P.abilities())
	for cx = -2, 2 do
		for cz = -2, 2 do send(P.chunk(cx, cz, FLOOR)) end
	end
	for k, e in pairs(owner) do
		if IsValid(e) and e.mcBlock then
			local x, y, z = e.mcCell:match("(-?%d+),(-?%d+),(-?%d+)")
			send(P.blockChange(tonumber(x), tonumber(y), tonumber(z), e.mcBlock.id, e.mcBlock.meta))
		end
	end
	for k in pairs(holes) do
		local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
		sendAir(tonumber(x), tonumber(y), tonumber(z))
	end
	c.x, c.y, c.z = SPAWN[1], SPAWN[2], SPAWN[3]
	send(P.posLook(c.x, c.y, c.z, 0, 0))
	send(P.chat("This server is a Garry's Mod process. Say nuke when you're done."))
	mcsock.play(c.fd, P.keepAlive(1), 2)
	if not IsValid(rag) then spawnRag() else moveRag(c.x, c.y, c.z) end
	print("[mc] " .. name .. " joined")
end

local startNuke

local function handlePacket(c, pk)
	if c.state == 0 then
		local proto, _, _, nxt = P.readHandshake(pk.body)
		c.state = nxt
		if nxt == 2 and proto ~= 47 then
			c.out[#c.out + 1] = P.frame(0x00, P.str('{"text":"Use Minecraft 1.8.9"}'))
			c.dying = true
		end
	elseif c.state == 1 then
		if pk.id == 0 then c.out[#c.out + 1] = P.statusResponse(statusJson())
		elseif pk.id == 1 then c.out[#c.out + 1] = P.pong(pk.body); c.dying = true end
	elseif c.state == 2 then
		if pk.id == 0 then handleLogin(c, P.readLoginStart(pk.body)) end
	elseif c == player then
		local free = not (IsValid(rag) and (rag.mcHeld or rag.mcFalling))
		if pk.id == 0x04 then
			if free then c.x, c.y, c.z = P.readPosition(pk.body); moveRag(c.x, c.y, c.z) end
		elseif pk.id == 0x06 then
			if free then c.x, c.y, c.z, c.yaw, c.pitch = P.readPositionLook(pk.body); moveRag(c.x, c.y, c.z) end
		elseif pk.id == 0x05 then
			c.yaw, c.pitch = P.readLook(pk.body)
		elseif pk.id == 0x07 then handleDig(pk.body)
		elseif pk.id == 0x08 then handlePlace(pk.body)
		elseif pk.id == 0x01 then
			local msg = P.readStr(pk.body, 1)
			print("[mc] <" .. c.name .. "> " .. msg)
			if msg:lower() == "nuke" then startNuke() end
		end
	end
end

local function pump()
	for _ = 1, 4 do
		local fd, ip = mcsock.accept()
		if not fd then break end
		conns[fd] = { fd = fd, buf = "", out = {}, off = 0, state = 0, born = SysTime(), x = SPAWN[1], y = SPAWN[2], z = SPAWN[3], yaw = 0, pitch = 0, lastKeep = SysTime() }
		print("[mc] fd " .. fd .. " from " .. ip)
	end
	local now = SysTime()
	for fd, c in pairs(conns) do
		local closed = false
		for _ = 1, 8 do
			local data = mcsock.recv(fd)
			if data == nil then drop(c, "closed"); closed = true; break end
			if data == "" then break end
			c.buf = c.buf .. data
		end
		if not closed then
			local packets, rest = P.split(c.buf)
			c.buf = rest
			for _, pk in ipairs(packets) do
				if c.dead then break end
				handlePacket(c, pk)
			end
			if not c.dead and c.state ~= 3 and now - c.born > 15 then drop(c, "idle") end
		end
	end
end

local function flush()
	for fd, c in pairs(conns) do
		if not c.dead then
			while c.out[1] do
				if not mcsock.queue(fd, table.remove(c.out, 1)) then drop(c, "queue failed") break end
			end
			local left, broken = mcsock.pending(fd)
			if broken then drop(c, "send failed")
			elseif c.dying and left == 0 then drop(c, "done") end
		end
	end
end

local function syncBlocks()
	for e in pairs(tracked) do
		if not IsValid(e) then
			local cell = tracked[e]
			if cell ~= "" and owner[cell] == e then
				owner[cell] = nil
				local x, y, z = cell:match("(-?%d+),(-?%d+),(-?%d+)")
				sendAir(tonumber(x), tonumber(y), tonumber(z))
			end
			tracked[e] = nil
		else
			local ph = e:GetPhysicsObject()
			local moving = e.mcHeld or (ph:IsValid() and ph:IsMotionEnabled())
			if moving then
				local x, y, z = cellOf(e:GetPos())
				local k = inBounds(x, y, z) and key(x, y, z) or nil
				if k ~= e.mcCell then
					if e.mcCell and owner[e.mcCell] == e then
						owner[e.mcCell] = nil
						local ox, oy, oz = e.mcCell:match("(-?%d+),(-?%d+),(-?%d+)")
						sendAir(tonumber(ox), tonumber(oy), tonumber(oz))
					end
					e.mcCell = k
					tracked[e] = k or ""
					if k then
						local prev = owner[k]
						if prev and prev ~= e then prev.mcCell = nil end
						owner[k] = e
						send(P.blockChange(x, y, z, e.mcBlock.id, e.mcBlock.meta))
					end
				end
				if not e.mcHeld and ph:IsValid() and ph:IsAsleep() then ph:EnableMotion(false) end
			end
		end
	end
end

local function syncRag()
	if not IsValid(rag) or not player then return end
	if rag.mcHeld or rag.mcFalling then
		local x, y, z = ragMc()
		player.x, player.y, player.z = x, y, z
		send(P.posLook(x, y, z, player.yaw or 0, player.pitch or 0))
		if rag.mcFalling and ragAsleep() then
			ragPhys(function(ph) ph:EnableMotion(false) end)
			rag.mcFalling = false
		end
	end
end

local function tickNuke()
	if not nuke then return end
	nuke.r = nuke.r + cvNukeSpeed:GetFloat()
	local records = {}
	while nuke.cells[nuke.i] and nuke.cells[nuke.i].d <= nuke.r do
		local c = nuke.cells[nuke.i]
		holes[key(c.x, c.y, c.z)] = true
		records[#records + 1] = { c.x - nuke.cx, c.y - nuke.cy, c.z - nuke.cz }
		nuke.i = nuke.i + 1
		if #records >= 250 then
			send(P.explosion(nuke.cx, nuke.cy, nuke.cz, nuke.r, records))
			records = {}
		end
	end
	if #records > 0 then send(P.explosion(nuke.cx, nuke.cy, nuke.cz, nuke.r, records)) end
	local centre = toSrc(nuke.cx, nuke.cy, nuke.cz)
	local reach = nuke.r * S()
	for e in pairs(tracked) do
		if IsValid(e) and not e.mcNuked and e:GetPos():Distance(centre) <= reach then
			e.mcNuked = true
			local ph = e:GetPhysicsObject()
			if ph:IsValid() then
				ph:EnableMotion(true)
				ph:Wake()
				local dir = (e:GetPos() - centre):GetNormalized()
				ph:ApplyForceCenter((dir * 900 + Vector(0, 0, 500)) * ph:GetMass())
			end
		end
	end
	if IsValid(rag) and not rag.mcNuked and ragPos():Distance(centre) <= reach then
		rag.mcNuked = true
		rag.mcFalling = true
		ragPhys(function(ph)
			ph:EnableMotion(true)
			ph:Wake()
			local dir = (ph:GetPos() - centre):GetNormalized()
			ph:ApplyForceCenter((dir * 600 + Vector(0, 0, 900)) * ph:GetMass())
		end)
	end
	if not nuke.cells[nuke.i] then
		nuke.done = nuke.done or SysTime()
		if SysTime() - nuke.done > 2.5 then
			send(P.disconnect("Something Went Wrong"))
			if player then player.dying = true end
			nuke = nil
		end
	end
end

startNuke = function()
	if nuke then return end
	local cx, cy, cz = SPAWN[1], SPAWN[2], SPAWN[3]
	if player then cx, cy, cz = player.x, player.y, player.z end
	cx, cy, cz = floor(cx), floor(cy), floor(cz)
	local cells = {}
	for x = WORLD_MIN, WORLD_MAX do
		for z = WORLD_MIN, WORLD_MAX do
			for y = 0, 3 do
				if not holes[key(x, y, z)] then
					cells[#cells + 1] = { x = x, y = y, z = z, d = sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2) }
				end
			end
		end
	end
	table.sort(cells, function(a, b) return a.d < b.d end)
	nuke = { cx = cx, cy = cy, cz = cz, r = 0, cells = cells, i = 1 }
	local centre = toSrc(cx + 0.5, cy, cz + 0.5)
	local ex = ents.Create("env_explosion")
	ex:SetPos(centre)
	ex:SetKeyValue("iMagnitude", "400")
	ex:SetKeyValue("iRadiusOverride", tostring(20 * S()))
	ex:Spawn()
	ex:Activate()
	ex:Fire("Explode")
	util.ScreenShake(centre, 40, 5, 4, 3000)
	send(P.chat("Nuke armed."))
	print("[mc] nuke from " .. cx .. "," .. cy .. "," .. cz .. " over " .. #cells .. " cells")
end

hook.Add("Think", "mcserver", function()
	local now = SysTime()
	if now < nextTick then return end
	nextTick = now + 0.05
	pump()
	syncBlocks()
	syncRag()
	tickNuke()
	syncVoxels()
	flush()
end)

hook.Add("OnEntityCreated", "mcserver", function(e)
	timer.Simple(0, function()
		if IsValid(e) and cvVoxel:GetBool() then trackVoxel(e) end
	end)
end)

hook.Add("EntityTakeDamage", "mcserver", function(e, dmg)
	if e.mcBlock and dmg:GetDamage() >= 15 then
		local cell = tracked[e]
		removeBlockEnt(e)
		if cell then
			local x, y, z = cell:match("(-?%d+),(-?%d+),(-?%d+)")
			sendAir(tonumber(x), tonumber(y), tonumber(z))
		end
	end
end)

hook.Add("PhysgunPickup", "mcserver", function(ply, e)
	if e.mcBlock then e.mcHeld = true end
	if e.mcRag then
		e.mcHeld = true
		e.mcFalling = false
		ragPhys(function(ph) ph:EnableMotion(true); ph:Wake() end)
	end
end)

hook.Add("PhysgunDrop", "mcserver", function(ply, e)
	if e.mcBlock then e.mcHeld = false end
	if e.mcRag then e.mcHeld = false; e.mcFalling = true end
end)

hook.Add("OnPhysgunFreeze", "mcserver", function(wep, ph, e, ply)
	if e.mcRag then
		e.mcHeld = false
		e.mcFalling = false
		ragPhys(function(p) p:EnableMotion(false) end)
	end
end)

local function setOrigin(ground)
	origin = ground - Vector(SPAWN[1] * S(), -SPAWN[3] * S(), 4 * S())
	print("[mc] origin " .. tostring(origin))
end

local BUILD = "2026-09-04f"

local function start()
	for _, c in pairs(conns) do drop(c, "restart") end
	conns = {}
	player = nil
	local ok, err = pcall(mcsock.listen, cvPort:GetInt())
	if not ok then
		MCS.running = false
		print("[mc] LISTEN FAILED: " .. tostring(err))
		return
	end
	MCS.running = true
	local fd, port, state = mcsock.info()
	print(string.format("[mc] build %s listening on %d (fd %d, %s) in pid %d", BUILD, port, fd, state, mcsock.pid()))
end

hook.Add("ShutDown", "mcserver", function()
	mcsock.stop()
end)

hook.Add("InitPostEntity", "mcserver", function()
	local spawn = ents.FindByClass("info_player_start")[1]
	setOrigin(spawn and spawn:GetPos() or Vector(0, 0, 0))
	start()
end)

concommand.Add("mc_start", start)
concommand.Add("mc_stop", function()
	for _, c in pairs(conns) do drop(c, "stopped") end
	conns = {}
	MCS.running = false
	mcsock.stop()
	print("[mc] stopped")
end)
concommand.Add("mc_reload", function()
	print("[mc] reloading from disk")
	include("autorun/server/mcserver.lua")
end)
concommand.Add("mc_nuke", startNuke)
concommand.Add("mc_probe", function(ply)
	local lo, hi = toSrc(WORLD_MIN, 0, WORLD_MIN), toSrc(WORLD_MAX + 1, 4, WORLD_MAX + 1)
	print("[mc] origin " .. tostring(origin) .. " scale " .. S())
	print("[mc] world corners in source coords: " .. tostring(lo) .. " to " .. tostring(hi))
	if IsValid(ply) then
		local x, y, z = cellOf(ply:GetPos())
		print(string.format("[mc] you are at block %d,%d,%d, in bounds: %s", x, y, z, tostring(inBounds(x, y, z))))
		local tr = ply:GetEyeTrace()
		if tr.Hit then
			local ax, ay, az = cellOf(tr.HitPos)
			print(string.format("[mc] aiming at block %d,%d,%d, in bounds: %s", ax, ay, az, tostring(inBounds(ax, ay, az))))
		end
	end
end)

concommand.Add("mc_rescan", function()
	for _, e in ipairs(ents.GetAll()) do trackVoxel(e) end
end)
if MCS.running then start() end

concommand.Add("mc_origin", function(ply)
	if not IsValid(ply) then return end
	local tr = ply:GetEyeTrace()
	setOrigin(tr.Hit and tr.HitPos or ply:GetPos())
	spawnRag()
end)
concommand.Add("mc_status", function()
	local n = 0
	for _ in pairs(tracked) do n = n + 1 end
	local open = 0
	for _ in pairs(conns) do open = open + 1 end
	local fd, port, state = mcsock.info()
	print(string.format("[mc] build %s pid %d socket fd %d port %d %s", BUILD, mcsock.pid(), fd, port, state))
	if player then
		local left = mcsock.pending(player.fd)
		print(string.format("[mc] outbound queue %d bytes", left))
	end
	local vx, vc = 0, 0
	for _, v in pairs(voxelled) do vx = vx + 1; for _ in pairs(v.cells) do vc = vc + 1 end end
	print(string.format("[mc] voxelised props %d cells %d", vx, vc))
	print(string.format("[mc] player %s conns %d fds %d props %d sent %.1fKB nuke %s", player and (player.name or "?") or "none", open, mcsock.count(), n, sentBytes / 1024, tostring(nuke ~= nil)))
end)
