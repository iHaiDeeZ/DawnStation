-- Shadow Hearts: Covenant (Europe, Disc 2) [SLES-82031]: DawnStation's fix, the USA Disc 1's (fixes/SLUS-21041, made
-- there in the Lab, 2026-11-08), for the newer core (core2); UNTESTED on this disc. The handler is found by its lines
-- and patched only where this disc has the same one (its addresses and gp offsets are read from it); the addresses
-- below are the USA disc's.
--
-- The USA disc:
-- Shadow Hearts: Covenant (USA, Disc 1) [SLUS-21041]: DawnStation's fix (2026-11-08, Lab), for the newer core (core2).
--
-- The game stayed on a black screen after the PS2 logo (the user: "check why this game has blackscreen"). Seen live
-- in the Lab: the PS2 at full speed (its vblank counter 60 a second), and the game's start-up thread printing "FILE
-- I/O SYSTEM INIT STATUS:%d" (through DECI2, which a retail console doesn't have) in a loop at 0x229400 for as long
-- as the flag at 0x43FA88 (gp-0x7F68) isn't 0. It stayed 0xF001: the answer to command 0x16, the init of the game's
-- own file I/O engine (an IOP module, Nautilus' "FIO Engine" of 2004-01-16, reached through raw SIF commands: EE
-- command 1 to the IOP, IOP command 1 back to the handler at 0x228F10), never came. The engine's handler answers 0x16
-- at once from its one send buffer, then sends its usual 0x36 "command taken" note from the same buffer, having
-- waited only while the first transfer was queued (0x82838: while sceSifDmaStat > 0). On a PS2 a transfer under way
-- is over in microseconds; Sony's core holds it until the EE takes it and reads the buffer only then, so both
-- transfers carry the 0x36 note and the answer is lost (the IOP's buffer and the EE's receive buffer, 0x441080, both
-- held the note, and none of the answer's values had reached the EE). Barnyard's FMOD lost its "done" messages the
-- same way.
--
-- The fix: the handler's 0x36 case goes through a routine at 0xFFC00 that does what the case did, and when the note
-- is for the init (its word 4 = 0x16) while the game still waits for that answer (flag 0xF001, command 0x16), it is
-- handled as the lost answer too, by the handler's own 0x16 case: the engine sends both from the same buffer, so the
-- note's words 5-7 are the answer's, and only the answer's word 4, its status, was 0 (the IOP's code at 0x8257C).
-- The handler is found by its lines (the addresses below are the USA disc's; its gp offsets are read from it), and one
-- patched already (a save state made with the fix) is taken as it is. A save state made at the black screen stays
-- stuck (the answer is long gone): start the game again. A second fault in the same engine, on the IOP, kept play
-- from starting after the menus and cutscenes: the IOP part below.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- A word read as 0..0xFFFFFFFF, whether the core gives it signed or not.
local function u32(v)
	if v < 0 then
		return v + 4294967296
	end
	return v
end

local function ee(at)
	return u32(eeObj.ReadMem32(at))
end

-- How a line is matched: the whole word, or its upper half (a gp-relative access, whose offset is the build's).
local F, H16 = "F", "H16"

-- The handler's 0x36 and 0x16 cases (and the 0x37 and 0x34 ones between them).
local HANDLER = {
	lines = {0x24030036, 0x1083000A, 0x24030037, 0x10830004, 0x00000000, 0x10000070, 0x00000000, 0x00000000, 0x8F83828C, 0x24630001, 0x1000006B, 0xAF83828C, 0x8E230010, 0x10000068, 0xAF838288, 0x00000000, 0x8E230010, 0xAF838098, 0x8E230010, 0xAE0300AC, 0x8E230018, 0xAE0300BC, 0x1000005F, 0xAF80809C, 0x8E230014, 0xAF83824C, 0x8E230010, 0xAF838098, 0x8E230018, 0xAF838258, 0x8E23001C, 0xAF83825C, 0x10000055, 0xAF80809C},
	mask = {F, F, F, F, F, F, F, F, H16, F, F, H16, F, F, H16, F, F, H16, F, F, F, F, F, H16, F, H16, F, H16, F, H16, F, H16, F, H16},
	known = 0x00228F90,
	anchor = 1,
}

local CAVE = 0x000FFC00
local JUMP, DELAY, ACK, CASE16, FLAG, END_B, CMD = 0x30, 0x34, 0x38, 0x60, 0x6C, 0x80, 0x84

local function j(target)
	return 0x08000000 + math.floor(target / 4) % 0x4000000
end

local function lo16(w)
	return w % 0x10000
end

-- Where the b at this place goes.
local function branch_target(at)
	local off = lo16(ee(at))
	if off >= 0x8000 then
		off = off - 0x10000
	end
	return at + 4 + off * 4
end

-- The handler's lines at this place, as they were (patched false) or with the jump to the routine (patched true).
local function handler_at(at, patched)
	for k = 1, #HANDLER.lines do
		local w, l, m = ee(at + (k - 1) * 4), HANDLER.lines[k], HANDLER.mask[k]
		if patched and (k - 1) * 4 == JUMP then
			l, m = j(CAVE), F
		elseif patched and (k - 1) * 4 == DELAY then
			l, m = 0, F
		end
		if m == F then
			if w ~= l then
				return false
			end
		elseif math.floor(w / 0x10000) ~= math.floor(l / 0x10000) then
			return false
		end
	end
	return true
end

local function here(at)
	return handler_at(at, false) or handler_at(at, true)
end

-- The routine for the handler at this place: the 0x36 case's own store, then the lost answer to the init.
local function routine(at)
	local ack, flag, cmd = lo16(ee(at + ACK)), lo16(ee(at + FLAG)), lo16(ee(at + CMD))
	return {
		0x8E230010, -- lw v1, 0x10(s1): word 4, the command the note is for
		0xAF830000 + ack, -- sw v1, ack(gp): what the 0x36 case did
		0x24040016, -- addiu a0, zero, 0x16
		0x1464000A, -- bne v1, a0, out: not the init's note
		0x8F840000 + flag, -- lw a0, flag(gp)
		0x3403F001, -- ori v1, zero, 0xf001
		0x14830007, -- bne a0, v1, out: the game isn't waiting for an answer
		0x8F840000 + cmd, -- lw a0, cmd(gp)
		0x24030016, -- addiu v1, zero, 0x16
		0x14830004, -- bne a0, v1, out: not for the init's
		0x00000000, -- nop
		0xAE23000C, -- sw v1, 0xc(s1): the lost answer, command 0x16,
		j(at + CASE16), -- j the handler's 0x16 case
		0xAE200010, -- sw zero, 0x10(s1): with status 0
		j(branch_target(at + END_B)), -- out: j the handler's end
		0x00000000, -- nop
	}
end

-- The routine first, then the jump to it (its delay slot first): the handler never sees half of it.
local function install(at)
	for k, w in ipairs(routine(at)) do
		if ee(CAVE + (k - 1) * 4) ~= w then
			eeObj.WriteMem32(CAVE + (k - 1) * 4, w)
		end
	end
	if ee(at + JUMP) ~= j(CAVE) or ee(at + DELAY) ~= 0 then
		eeObj.WriteMem32(at + DELAY, 0)
		eeObj.WriteMem32(at + JUMP, j(CAVE))
	end
end

-- The search while the handler is missing: 512 words a vsync (each read costs the EE about 1.4 us) over the game's
-- code within 0x20000 of this disc's place, about 2 s a pass, 60 passes at most (the game loads its code once, at
-- boot, and sends the init a few seconds later).
local WORDS = 512
local SCAN = {lo = 0x00210000, hi = 0x00250000, passes = 60}
local site

local function step()
	if site then
		if ee(site + JUMP) == j(CAVE) then
			return
		end
		if here(site) then -- undone by a save state made without the fix
			install(site)
			return
		end
		site, SCAN.left = nil, nil
	end
	if here(HANDLER.known) then
		site = HANDLER.known
		install(site)
		return
	end
	if not SCAN.left then
		SCAN.left, SCAN.at = SCAN.passes, SCAN.lo
	end
	if SCAN.left <= 0 then
		return
	end
	local want, stop = HANDLER.lines[HANDLER.anchor], SCAN.at + WORDS * 4
	for at = SCAN.at, stop - 4, 4 do
		local start = at - (HANDLER.anchor - 1) * 4
		if ee(at) == want and here(start) then
			site = start
			install(site)
			return
		end
	end
	SCAN.at = stop
	if SCAN.at >= SCAN.hi then
		SCAN.at, SCAN.left = SCAN.lo, SCAN.left - 1
	end
end

-- The second fault, in the same engine on the IOP (2026-11-08, Lab, live: menus and cutscenes ran, play didn't start).
-- For a command that seeks first (mode 1 at 0xB5038, command 2 here), the engine's thread calls sceCdSeek (0x81AA0)
-- and only then sets its state to 0x2F, "waiting for the seek"; the CD callback (0x81570) moves a finished seek on to
-- state 2, "read". A PS2 seek takes milliseconds, but Sony's core times one by its distance (core+0x63E57: 50 cycles
-- a sector below 64 sectors), so a seek to where the drive already is ends at once: the callback ran before the
-- thread set 0x2F, and the thread then waited for a callback that had come and gone (the callback's reason consumed,
-- the drive at the seek's sector, the state 0x2F). Setting the state to 2 by hand let the game go on. The fix sets
-- 0x2F before the seek, and back to 0x2E if the drive refuses it (as the engine left it then). The module is
-- relocatable: its code is found by its lines (absolute-address words matched on their upper half, calls on their
-- opcode), the words written are its own moved about, and they are written only while the engine has no command.
-- With both parts the game plays (the user, 2026-11-08: "game plays").
local okIop, iopObj = pcall(getIOPObject)

local function iop(at)
	return u32(iopObj.ReadMem32(at))
end

local OP = "OP"

-- The engine's seek step, from its start (0x81A34 here).
local SEEK = {
	lines = {0x27BDFFE8, 0xAFBF0014, 0xAFB00010, 0x3C01000B, 0x8C245038, 0x24030004, 0x10830028, 0x00000000, 0x24030003, 0x10830025, 0x00000000, 0x24030002, 0x10830022, 0x00000000, 0x24020001, 0x10820003, 0x00000000, 0x10000022, 0x00000000, 0x24040001, 0x0C020189, 0x00000000, 0x24030002, 0x14430020, 0x00000000, 0x3C01000B, 0x8C245034, 0x0C020185, 0x00000000, 0x00408021, 0x1600000B, 0x00000000, 0x3C040008, 0x24842E7C, 0x02002821, 0x0C020111, 0x00000000, 0x3403F003, 0x3C010008, 0xAC232F40, 0x1000000F, 0x00000000, 0x2403002F, 0x3C010008, 0xAC232F44, 0x1000000A, 0x00000000},
	mask = {F, F, F, H16, H16, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, OP, F, F, F, F, H16, H16, OP, F, F, F, F, H16, H16, F, OP, F, F, H16, H16, F, F, F, H16, H16, F, F},
	known = 0x00081A34,
	anchor = 7,
}

local REWRITE = 25 -- the lines rewritten (0-based): from the seek's LSN (0x81A98 here) to the step's end
-- The new lines, by place: an old one (its index from REWRITE) or a word of their own.
local NEW = {
	{17}, {18}, {19}, -- addiu v1, zero, 0x2f; lui at; sw v1, state(at): "waiting for the seek", before it
	{0}, {1}, {2}, 0x00000000, -- lui at; lw a0, lsn(at); jal sceCdSeek; nop
	0x1440000C, {4}, -- bnez v0, the step's end; move s0, v0
	0x2403002E, {18}, {19}, -- refused: addiu v1, zero, 0x2e; lui at; sw v1, state(at): the state as it was
	{7}, {8}, {10}, {9}, -- lui a0; addiu a0 (the message); jal printf; move a1, s0
	{12}, {13}, {14}, 0x00000000, -- ori v1, zero, 0xf003; lui at; sw v1, flag(at): the error, as before; nop
	{20}, {21}, -- b (the function's end); nop
}
local WAITING = 0x2403002F -- the first new line

local function same(w, l, m)
	if m == F then
		return w == l
	elseif m == H16 then
		return math.floor(w / 0x10000) == math.floor(l / 0x10000)
	end
	return math.floor(w / 0x4000000) == math.floor(l / 0x4000000)
end

-- The step's lines at this place, as they were (patched false) or as the fix leaves them (patched true).
local function seek_at(at, patched)
	for k = 1, #SEEK.lines do
		local l, m = SEEK.lines[k], SEEK.mask[k]
		if patched and k > REWRITE then
			local src = NEW[k - REWRITE]
			if type(src) == "table" then
				l, m = SEEK.lines[REWRITE + src[1] + 1], SEEK.mask[REWRITE + src[1] + 1]
			else
				l, m = src, F
			end
		end
		if not same(iop(at + (k - 1) * 4), l, m) then
			return false
		end
	end
	return true
end

-- A word an lui and a load or store make, as in the step's own code.
local function data_addr(hi, lo)
	lo = lo % 0x10000
	if lo >= 0x8000 then
		lo = lo - 0x10000
	end
	return (hi % 0x10000) * 0x10000 + lo
end

-- Written only while the engine has no command (its flag, 0x82F40 here, at 0): its thread is asleep then.
local function seek_install(at)
	local base = at + REWRITE * 4
	if iop(data_addr(iop(base + 13 * 4), iop(base + 14 * 4))) ~= 0 then
		return
	end
	local old = {}
	for i = 0, #NEW - 1 do
		old[i] = iop(base + i * 4)
	end
	for k, src in ipairs(NEW) do
		iopObj.WriteMem32(base + (k - 1) * 4, type(src) == "table" and old[src[1]] or src)
	end
end

-- The search while the step is missing: 512 words a vsync over the IOP's modules, 40 passes at most (about 2 min).
local ISCAN = {lo = 0x00040000, hi = 0x000C0000, passes = 40}
local seekAt

local function step_iop()
	if not (okIop and iopObj) then
		return
	end
	if seekAt then
		if iop(seekAt + REWRITE * 4) == WAITING then
			return
		end
		if not seek_at(seekAt, false) then -- other code there now
			seekAt, ISCAN.left = nil, nil
		end
	end
	if not seekAt then
		if seek_at(SEEK.known, false) or seek_at(SEEK.known, true) then
			seekAt = SEEK.known
		else
			if not ISCAN.left then
				ISCAN.left, ISCAN.at = ISCAN.passes, ISCAN.lo
			end
			if ISCAN.left <= 0 then
				return
			end
			local want, stop = SEEK.lines[SEEK.anchor], ISCAN.at + WORDS * 4
			for at = ISCAN.at, stop - 4, 4 do
				local start = at - (SEEK.anchor - 1) * 4
				if iop(at) == want and (seek_at(start, false) or seek_at(start, true)) then
					seekAt = start
					break
				end
			end
			ISCAN.at = stop
			if ISCAN.at >= ISCAN.hi then
				ISCAN.at, ISCAN.left = ISCAN.lo, ISCAN.left - 1
			end
			if not seekAt then
				return
			end
		end
	end
	if iop(seekAt + REWRITE * 4) ~= WAITING then
		seek_install(seekAt)
	end
end

emuObj.AddVsyncHook(function()
	step()
	step_iop()
end)
