package.path = "garrysmod/lua/?.lua;" .. package.path
local P = require("mcserver.proto")

local fails = 0
local say = print
local function eq(name, got, want)
	if type(got) == "number" and type(want) == "number" and math.abs(got - want) < 1e-6 then return end
	if got ~= want then fails = fails + 1; say("FAIL " .. name .. ": got " .. tostring(got) .. " want " .. tostring(want)) end
end

local VM = {}
VM.__index = VM
local function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VM) end
VM.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VM.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VM.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
VM.__tostring = function(v) return v.x .. " " .. v.y .. " " .. v.z end
function VM:Distance(o) return math.sqrt((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2) end
function VM:GetNormalized() local l = self:Distance(Vector(0, 0, 0)); return l == 0 and Vector() or self * (1 / l) end
_G.Vector = Vector
_G.Angle = function() return {} end
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
_G.SERVER = true
_G.FCVAR_ARCHIVE = 0
_G.RENDERMODE_TRANSCOLOR = 1
local clock = 0
_G.SysTime = function() return clock end
_G.print = function() end
_G.file = { Exists = function() return false end }
_G.util = { Base64Encode = function(s) return s end, ScreenShake = function() end }
_G.timer = { Simple = function(_, fn) fn() end }
_G.ents = _G.ents
_G.hook = { fns = {}, Add = function(event, _, fn) hook.fns[event] = hook.fns[event] or {}; table.insert(hook.fns[event], fn) end }
_G.concommand = { fns = {}, Add = function(name, fn) concommand.fns[name] = fn end }
_G.CreateConVar = function(_, default)
	return { GetInt = function() return tonumber(default) end, GetFloat = function() return tonumber(default) end, GetString = function() return default end, GetBool = function() return default ~= "0" end }
end
_G.IsValid = function(e) return e ~= nil and e.valid ~= false end

local ents = {}
local function Phys(e)
	return { valid = true, motion = false, asleep = false, e = e,
		IsValid = function(s) return true end,
		EnableMotion = function(s, b) s.motion = b end,
		IsMotionEnabled = function(s) return s.motion end,
		IsAsleep = function(s) return s.asleep end,
		Wake = function(s) s.asleep = false end,
		SetPos = function(s, p) s.e.pos = p end,
		GetPos = function(s) return s.e.pos end,
		GetMass = function() return 1 end,
		ApplyForceCenter = function(s, f) s.force = f end,
	}
end
_G.ents = {
	Create = function(cls)
		local e = { cls = cls, pos = Vector(), valid = true }
		e.phys = Phys(e)
		e.SetModel = function() end; e.SetAngles = function() end; e.Spawn = function() end; e.Activate = function() end
		e.SetColor = function(s, c) s.colour = c end; e.SetRenderMode = function() end; e.SetKeyValue = function() end; e.Fire = function() end
		e.SetPos = function(s, p) s.pos = p end; e.GetPos = function(s) return s.pos end
		e.GetPhysicsObject = function(s) return s.phys end
		e.GetPhysicsObjectCount = function() return 1 end
		e.GetPhysicsObjectNum = function(s) return s.phys end
		e.Remove = function(s) s.valid = false end
		ents[#ents + 1] = e
		return e
	end,
	FindByClass = function() return { { GetPos = function() return Vector(100, 200, 300) end } } end,
}

local wire = { pending = {}, fds = {}, nextFd = 6 }
local function connect()
	wire.nextFd = wire.nextFd + 1
	local fd = wire.nextFd
	wire.fds[fd] = { inbox = "", outbox = "", open = true }
	wire.pending[#wire.pending + 1] = fd
	return fd
end
_G.mcsock = {
	listen = function(port) wire.listening = port; return true end,
	accept = function()
		local fd = table.remove(wire.pending, 1)
		if not fd then return nil end
		return fd, "127.0.0.1"
	end,
	recv = function(fd)
		local s = wire.fds[fd]
		if not s or not s.open then return nil end
		local d = s.inbox; s.inbox = ""; return d
	end,
	queue = function(fd, str)
		local s = wire.fds[fd]
		if not s or not s.open then return false end
		s.outbox = s.outbox .. str
		return true
	end,
	play = function(fd, beat, every)
		local s = wire.fds[fd]
		if s then s.beat = beat; s.every = every end
	end,
	pending = function(fd)
		local s = wire.fds[fd]
		if not s then return -1, true end
		return 0, not s.open
	end,
	close = function(fd) if wire.fds[fd] then wire.fds[fd].open = false end end,
	stop = function() for _, s in pairs(wire.fds) do s.open = false end end,
	info = function()
		if not wire.listening then return -1, -1, "no listen socket" end
		return 3, wire.listening, "ok"
	end,
	count = function() local n = 0 for _, s in pairs(wire.fds) do if s.open then n = n + 1 end end return n end,
	pid = function() return 4242 end,
}
_G.require = function() end
_G.include = function() return P end

dofile("garrysmod/lua/autorun/server/mcserver.lua")
hook.fns.InitPostEntity[1]()
eq("listening", wire.listening, 25565)

local function tick(n)
	for _ = 1, n or 1 do
		clock = clock + 0.05
		hook.fns.Think[1]()
	end
end
local function drain(fd)
	local s = wire.fds[fd]
	local packets, rest = P.split(s.outbox)
	s.outbox = rest
	return packets
end
local function feed(fd, pkt) wire.fds[fd].inbox = wire.fds[fd].inbox .. pkt end
local FD
local function client(pkt) feed(FD, pkt) end
local function findAll(packets, id) local out = {} for _, p in ipairs(packets) do if p.id == id then out[#out + 1] = p end end return out end

FD = connect()
client(P.frame(0, P.varint(47) .. P.str("localhost") .. P.u16(25565) .. P.varint(2)))
client(P.frame(0, P.str("Ry")))
tick(3)
local pk = drain(FD)
eq("login success", pk[1].id, 2)
eq("join game", pk[2].id, 1)
eq("spawn pos", pk[3].id, 5)
eq("abilities", pk[4].id, 0x39)
eq("chunks", #findAll(pk, 0x21), 25)
eq("chunk bytes", #pk[5].body, 12544 + 4 + 4 + 1 + 2 + 2)
eq("pos look", #findAll(pk, 0x08), 1)
eq("ragdoll spawned", ents[1].cls, "prop_ragdoll")
local rag = ents[1]
eq("ragdoll placed", tostring(rag.pos), tostring(Vector(100, 200, 300 + 0.8 * 24)))

eq("heartbeat armed", wire.fds[FD].beat, P.keepAlive(1))
eq("heartbeat interval", wire.fds[FD].every, 2)

client(P.frame(0x04, P.f64(10.5) .. P.f64(4) .. P.f64(12.5) .. "\1"))
tick(1)
eq("ragdoll follows x", rag.pos.x, 100 + 2 * 24)
eq("ragdoll follows z", rag.pos.y, 200 - 4 * 24)

client(P.frame(0x08, P.pos(10, 3, 10) .. "\1" .. P.i16(35) .. "\1" .. P.i16(14) .. "\0" .. "\8\16\8"))
tick(1)
pk = drain(FD)
eq("place block change", #findAll(pk, 0x23), 1)
local bx, by, bz = P.readPos(findAll(pk, 0x23)[1].body, 1)
eq("placed at y", by, 4)
eq("placed x", bx, 10)
local block = ents[2]
eq("prop spawned", block.cls, "prop_physics")
eq("prop frozen", block.phys.motion, false)
eq("prop colour red", block.colour.r, 165)
eq("prop centre x", block.pos.x, 100 + 2 * 24)
eq("prop centre z", block.pos.z, 300 + 0.5 * 24)

hook.fns.PhysgunPickup[1](nil, block)
block.phys.motion = true
block.pos = block.pos + Vector(3 * 24, 0, 2 * 24)
tick(1)
pk = findAll(drain(FD), 0x23)
eq("move sends two changes", #pk, 2)
local ax, ay, az = P.readPos(pk[1].body, 1)
eq("air at old x", ax, 10); eq("air at old y", ay, 4)
eq("air id", (P.readVarint(pk[1].body, 9)), 0)
local nx, ny, nz = P.readPos(pk[2].body, 1)
eq("block at new x", nx, 13); eq("block at new y", ny, 6); eq("block at new z", nz, 10)
eq("block id kept", (P.readVarint(pk[2].body, 9)), 35 * 16 + 14)

hook.fns.PhysgunDrop[1](nil, block)
block.pos = block.pos - Vector(0, 0, 1.6 * 24)
tick(1)
pk = findAll(drain(FD), 0x23)
eq("fall sends two", #pk, 2)
block.phys.asleep = true
tick(1)
eq("refrozen at rest", block.phys.motion, false)
eq("no spam when still", #drain(FD), 0)

client(P.frame(0x07, "\0" .. P.pos(13, 4, 10) .. "\1"))
tick(1)
eq("dug prop removed", block.valid, false)
eq("dig sends air", #findAll(drain(FD), 0x23), 1)

client(P.frame(0x07, "\0" .. P.pos(0, 3, 0) .. "\1"))
tick(1)
eq("floor dig air", #findAll(drain(FD), 0x23), 1)

client(P.frame(0x08, P.pos(5, 3, 5) .. "\1" .. P.i16(1) .. "\1" .. P.i16(0) .. "\0" .. "\8\16\8"))
tick(1)
drain(FD)
local second = ents[3]
hook.fns.PhysgunPickup[1](nil, rag)
eq("rag unfrozen", rag.phys.motion, true)
rag.pos = rag.pos + Vector(0, 0, 5 * 24)
tick(1)
pk = findAll(drain(FD), 0x08)
eq("rag drives player", #pk, 1)
local rx, ry, rz = P.readPositionLook(pk[1].body)
eq("rag player y", math.abs(ry - 9) < 1e-9, true)
client(P.frame(0x04, P.f64(1) .. P.f64(4) .. P.f64(1) .. "\1"))
tick(1)
eq("client pos ignored while held", rag.pos.x, 100 + 2 * 24)
hook.fns.PhysgunDrop[1](nil, rag)
rag.phys.asleep = true
tick(1)
eq("rag refrozen", rag.phys.motion, false)
drain(FD)

local jeep = _G.ents.Create("prop_physics")
jeep.model = "models/props_vehicles/car001a_phys.mdl"
jeep.GetModel = function(s) return s.model end
jeep.GetClass = function() return "prop_physics" end
jeep.GetColor = function() return { r = 200, g = 40, b = 30 } end
jeep.OBBMins = function() return Vector(-48, -24, 0) end
jeep.OBBMaxs = function() return Vector(48, 24, 48) end
jeep.GetAngles = function() return { p = 0, y = 0, r = 0 } end
jeep.LocalToWorld = function(s, p) return s.pos + p end
jeep:SetPos(Vector(100, 200, 300))
jeep.phys.GetMeshConvexes = nil
hook.fns.OnEntityCreated[1](jeep)
tick(1)
local vpk = findAll(drain(FD), 0x22)
eq("jeep voxelised", #vpk >= 1, true)
local vcx, vj = P.readI32(vpk[1].body, 1)
local vcz; vcz, vj = P.readI32(vpk[1].body, vj)
local vcount = P.readVarint(vpk[1].body, vj)
eq("jeep has cells", vcount > 10, true)

jeep:SetPos(jeep.pos + Vector(0, 0, 5 * 24))
tick(1)
eq("moving jeep resyncs", #findAll(drain(FD), 0x22) >= 2, true)

jeep:Remove()
tick(1)
eq("removed jeep clears", #findAll(drain(FD), 0x22) >= 1, true)

local ping = connect()
feed(ping, P.frame(0, P.varint(47) .. P.str("localhost") .. P.u16(25565) .. P.varint(1)))
feed(ping, P.frame(0, ""))
tick(2)
eq("ping answered", #drain(ping), 1)
eq("player kept while ping open", #findAll(drain(FD), 0x40), 0)

local rejoin = connect()
feed(rejoin, P.frame(0, P.varint(47) .. P.str("localhost") .. P.u16(25565) .. P.varint(2)))
feed(rejoin, P.frame(0, P.str("Ry")))
tick(3)
local rj = drain(rejoin)
eq("rejoin login success", rj[1].id, 2)
eq("rejoin gets chunks", #findAll(rj, 0x21), 25)
eq("old conn kicked", wire.fds[FD].open, false)
eq("blocks resent to rejoin", #findAll(rj, 0x23) >= 1, true)
FD = rejoin
drain(FD)

client(P.frame(0x01, P.str("nuke")))
tick(1)
pk = drain(FD)
eq("nuke chat", #findAll(pk, 0x02), 1)
tick(10)
eq("nuke reaches floor", #findAll(drain(FD), 0x27) >= 1, true)
tick(200)
pk = drain(FD)
local ex = findAll(pk, 0x27)
eq("nuke explosions", #ex > 50, true)
eq("second prop flung", second.phys.motion, true)
eq("disconnect", #findAll(pk, 0x40), 1)
eq("socket closed", wire.fds[FD].open, false)

if fails == 0 then say("all passed") else os.exit(1) end
