-- Spider-Man 3 (SLUS-21552): DawnStation's fix, built into the app since v00.52 (data/fixes/SLUS-21552;
-- a folder of your own in /data/dawn/fixes/SLUS-21552 replaces it).
--
-- After the first level the game stays on a black screen for ever (psdevwiki: "Unplayable. Freezes on
-- loading screen after the first level"; PCSX2 issue #3012 is the same hang). The stalls in play are
-- fixed by SLUS-21552_cli.conf (VU1 jump policy).
--
-- 1. Kozarovv's patch from PCSX2's game database (commit a4d89913, 2019: "Fixes hang before loading
--    level 2", SLUS-21552 CRC 29873A0C): bit 30 (E) of the word at 0x44BAE4, near the end of the VU0
--    program VU0Rebake, cleared. Kept, but on its own it didn't stop the freeze in Sony's core.
--
-- 2. FMOD stream watchdog (v00.54), from the user's state saved in the freeze (slot 3, 2026-10-25):
--    - FMOD's stream thread (EE thread 8) takes FMOD's lock (semaphore 41, at 0x3ADBB4) and, inside
--      it, polls every 5 ms (0x3CEB20) for a free buffer slot of a sound stream. The main thread waits
--      for that lock, so nothing more is drawn.
--    - The stream's 4 slots were all handed to the IOP (FMOD command 7: copy the slot into SPU2 RAM,
--      sent by 0x3CEC90). FMOD.IRX answers every command 7 with a command 7 that frees the slot
--      (0x3CDA40), even after an error, but those 4 answers never came: the slots' data is in IOP RAM,
--      FMOD.IRX's threads are idle and both command queues are empty. Emulation itself goes on.
--    So when a stream has found no free slot for 100 polls (half a second; a slot normally comes back
--    within milliseconds), the slots are freed the way the lost answers would have done it: the free
--    flag set and the slot's lock released (its record in the EE kernel's semaphore table, written
--    only if it has the shape of a held lock nobody waits for). At worst that costs a moment of that
--    stream's sound. Each time it acts it prints a line to the emulator's log (emulog), with how many
--    commands 7 each slot sent and got answered.
--
-- 3. Diagnostics for the cause, IOP side (only if the core's Lua can hook the IOP; FMOD.IRX was
--    loaded at 0x176C30 in the user's state, and each hook checks its instruction first): FMOD.IRX's
--    ring of commands from the EE has 128 entries and no overflow check (0x176E18), an answer it
--    can't send is dropped (0x1773B0), and a failed SPU2 transfer is answered with an error (0x177ACC).
--    Each prints at most 20 lines.
--
-- Lua's print doesn't reach any log on the console, so the counts also go to PS2 RAM 0xFFFE0 (unused
-- memory just below the game: zero in the user's states), where DawnStation's profiler (System >
-- Profiler) logs them as "fix counters": "DFC1", then FMOD rescues, FMOD.IRX ring overflows, answers
-- it couldn't send, failed SPU2 transfers and the deepest its ring got.

apiRequest(0.7)

require("ee-gpr-alias")

local eeObj = getEEObject()
local emuObj = getEmuObject()

local u32 = function(a) return eeObj.ReadMem32(a) & 0xFFFFFFFF end

local COUNTERS = 0x000FFFE0
local counts = {0, 0, 0, 0, 0}  -- rescues, ring overflows, unsent answers, failed transfers, deepest ring
local written = -1

-- 1. [Hang before level 2 (Kozarovv)]
-- Every vsync, as PCSX2 applies it, but only once the game's table is there: during boot that memory
-- belongs to the BIOS (DawnStation's cheats once hung its PS2 logo by writing too early). The
-- counters are written here too, on the EE's side.
local patcher = function()
	if (eeObj.ReadMem32(0x0044BAE4) & 0xBFFFFFFF) == 0x000002FF then
		eeObj.WriteMem32(0x0044BAE4, 0x000002FF)
	end
	local sum = counts[1] + counts[2] + counts[3] + counts[4] + counts[5]
	if sum ~= written and u32(0x0044BAE4) == 0x000002FF then
		eeObj.WriteMem32(COUNTERS, 0x31434644) -- "DFC1"
		for k = 1, 5 do
			eeObj.WriteMem32(COUNTERS + 4 * k, counts[k])
		end
		written = sum
	end
end

emuObj.AddVsyncHook(patcher)

-- 2. FMOD stream watchdog
local POLL_LIMIT = 100        -- 5 ms polls without a free slot before a stream's slots count as lost
local KSEMA = 0x0001CC00      -- the EE kernel's semaphore records: 0x20 bytes per id
local polls = {}              -- empty polls in a row, per slot block
local sent, answered, lastSpu = {}, {}, {}   -- commands 7 per slot (slot block + slot number)
local rescues = 0

-- A record is {free link, count, max count, attr, option, waiting threads, wait list (2 words)}; an
-- empty wait list points at itself (kernel address).
local release = function(id)
	local s = KSEMA + id * 0x20
	local list = 0x80000000 + s + 0x18
	if id <= 0 or id >= 0x100 or u32(s + 0x04) ~= 0 or u32(s + 0x08) ~= 1 or u32(s + 0x14) ~= 0
		or u32(s + 0x18) ~= list or u32(s + 0x1C) ~= list then
		return false
	end
	eeObj.WriteMem32(s + 0x04, 1)
	return true
end

-- 0x3CEBD0 (addiu v0,zero,-1): back from the 5 ms sleep, no slot was free. s6 = the stream; its slot
-- block at +0x12C has the slots' locks at +0x234 and their free flags at +0x274.
eeObj.AddHook(0x003CEBD0, 0x2402FFFF, function()
	local sub = u32(eeObj.GetGpr(gpr.s6) + 0x12C)
	local n = (polls[sub] or 0) + 1
	if n < POLL_LIMIT then
		polls[sub] = n
		return
	end
	polls[sub] = 0
	rescues = rescues + 1
	counts[1] = rescues
	local report = {}
	for i = 0, 3 do
		if eeObj.ReadMem8(sub + 0x274 + i) == 0 then
			local id = u32(u32(sub + 0x234 + i * 4))
			local ok = release(id)
			eeObj.WriteMem8(sub + 0x274 + i, 1)
			local k = sub + i
			report[#report + 1] = string.format("slot %d (lock %d%s; sent %d, answered %d, last to SPU2 %06x)", i, id,
				ok and "" or " NOT released", sent[k] or 0, answered[k] or 0, lastSpu[k] or 0)
		end
	end
	print(string.format("SLUS-21552 fix: FMOD stream %08x found no free buffer for %d ms; freed %s (rescue %d)",
		sub, POLL_LIMIT * 5, table.concat(report, ", "), rescues))
end)

-- 0x3CEBDC (lw v1,0x12c(s6)): a slot was free.
eeObj.AddHook(0x003CEBDC, 0x8EC3012C, function()
	polls[u32(eeObj.GetGpr(gpr.s6) + 0x12C)] = 0
end)

-- 0x3CEF6C (lw t2,0x114(s2)): command 7 about to go to the IOP for slot [s2+0x128] of [s2+0x12C]; its
-- SPU2 address is at sp+0x40.
eeObj.AddHook(0x003CEF6C, 0x8E4A0114, function()
	local obj = eeObj.GetGpr(gpr.s2)
	local k = u32(obj + 0x12C) + u32(obj + 0x128)
	sent[k] = (sent[k] or 0) + 1
	lastSpu[k] = u32(eeObj.GetGpr(gpr.sp) + 0x40)
end)

-- 0x3CDA9C (sb v1,0x274(v0)): FMOD.IRX's answer 7 frees slot [s0+0x30] of slot block a1.
eeObj.AddHook(0x003CDA9C, 0xA0430274, function()
	local k = eeObj.GetGpr(gpr.a1) + u32(eeObj.GetGpr(gpr.s0) + 0x30)
	answered[k] = (answered[k] or 0) + 1
end)

print("SLUS-21552 fix: VU0Rebake patch and FMOD stream watchdog on")

-- 3. IOP diagnostics
local okIop, iopObj = pcall(getIOPObject)
if okIop and iopObj and iopObj.AddHook and iopObj.GetGpr and iopObj.ReadMem32 then
	local said = {}
	local say = function(key, text)
		said[key] = (said[key] or 0) + 1
		if said[key] <= 20 then
			print("SLUS-21552 fix: FMOD.IRX " .. text)
		end
	end
	local deepest = 31
	local hook = function(addr, word, fn)
		pcall(iopObj.AddHook, addr, word, fn)
	end
	-- 0x176E20 (lw v1,0x49f0(a1)): a command from the EE arrives in queue a1 (+0x49EC read, +0x49F0
	-- written, entries of 0x60 bytes with the type at +0x14).
	hook(0x00176E20, 0x8CA349F0, function()
		local q = iopObj.GetGpr(gpr.a1)
		local wr = iopObj.ReadMem32(q + 0x49F0) & 0xFFFFFFFF
		local waiting = wr - (iopObj.ReadMem32(q + 0x49EC) & 0xFFFFFFFF)
		if waiting >= 128 then
			counts[2] = counts[2] + 1
			say("full", string.format("command ring full: an unread command %d is overwritten",
				iopObj.ReadMem32(q + (wr & 0x7F) * 0x60 + 0x14)))
		elseif waiting > deepest then
			deepest = waiting
			counts[5] = waiting
			say("deep", string.format("%d commands waiting in its ring (of 128)", waiting))
		end
	end)
	-- 0x1773B0: sceSifSendCmd failed, so the answer is dropped.
	hook(0x001773B0, 0x2484C510, function()
		counts[3] = counts[3] + 1
		say("send", string.format("couldn't send an answer %d to the EE (sceSifSendCmd failed)",
			iopObj.ReadMem32(iopObj.GetGpr(gpr.sp) + 0x4C)))
	end)
	-- 0x177ACC: sceSdVoiceTrans failed for a command 7 (it's answered with an error).
	hook(0x00177ACC, 0x3C040018, function()
		counts[4] = counts[4] + 1
		say("trans", string.format("SPU2 transfer failed (sceSdVoiceTrans returned %d)", iopObj.GetGpr(gpr.v0)))
	end)
end
