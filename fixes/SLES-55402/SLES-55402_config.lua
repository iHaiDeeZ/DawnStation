-- SpongeBob SquarePants featuring Nicktoons: Globs of Doom (Australia) [SLES-55402]: DawnStation's fix, the USA disc's (fixes/SLUS-21818, made there in the Lab;
-- untested here). Its patches are found by their lines, so they go in only where this disc has the same
-- code. The addresses below are the USA disc's.
--
-- The game stopped on a black screen at the start (the user: "it seems stuck at the beginning"). Seen live in the Lab
-- on the newer core: the main thread loops at 0x116A78 (a 10 ms sleep, then "is the Common package still loading?")
-- and the package waits on FMOD Ex, whose sample loader (thread 11, 0x31572C) waits for one of its 4 upload slots
-- (0xA2EEB0 + 0x274: four flags, all 0) to come free. A slot comes free when the IOP's FMODEX.IRX answers the slot's
-- upload (command 7: IOP buffer -> sound RAM with sceSdVoiceTrans) with its own command 7. The IOP had nothing left
-- to do (its three FMOD threads idle in ReceiveMbx, its port 0 ring drained), its last upload slot 1's (IOP 0xB1B10
-- -> SPU2 0x4D000, 0x22C0 bytes), while the EE still held all 4 slots: the IOP's answers had been lost on the way.
-- The same fault as Nickelodeon Barnyard's (FMOD 3 there; DESIGN.md 1.08, fixed): FMOD sends every message from
-- one buffer (EE: 0x419F90 + port x 0x4A40 + 0x3000; IOP: 0x90400 + 0x3000 for port 0) and lets the next sender
-- write into it as soon as sceSifSendCmd has queued the DMA. A PS2 moves the 0x60 bytes at once; in Sony's core the
-- transfer can wait until the other side takes it, and then it carries the next message (here the 100-a-second
-- voice update, command 8) and the first one is gone. Each lost answer kept a slot for good; the fourth stopped the
-- game.
--
-- The fix, as Barnyard's: FMOD's sends wait until their DMA is done (sceSifDmaStat < 0) before the buffer is
-- written again, and a send that couldn't be queued (the SIF DMA queue full: FMOD printed "failed to send command!"
-- and dropped it) is sent again. EE: FMOD_Command_Send's sceSifSendCmd call goes to a stub at 0xFF300 (free memory
-- below the game) that calls it and then sceSifDmaStat; IOP: FMODEX.IRX's FMOD_Command_Send waits on sceSifDmaStat
-- where it printed the failure, and its data DMA (FMOD_Command_SendToIOP's sceSifSetDma) tries again instead of
-- giving up. Each place is found by its lines, so the same script serves every disc of the game; the IOP's once
-- FMODEX.IRX is loaded and linked. A place already patched (a save state made with the fix) is taken as it is.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local okIop, iopObj = pcall(getIOPObject)

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

local function iop(at)
	return u32(iopObj.ReadMem32(at))
end

local function ee_write(at, words)
	for k = 1, #words do
		eeObj.WriteMem32(at + (k - 1) * 4, words[k])
	end
end

local function iop_write(at, words)
	for k = 1, #words do
		iopObj.WriteMem32(at + (k - 1) * 4, words[k])
	end
end

local function jal(target)
	return 0x0C000000 + math.floor(target / 4) % 0x4000000
end

local function target(w) -- a jal's or j's target (code below 0x10000000)
	return (w % 0x4000000) * 4
end

-- How a line is matched: the whole word; its upper half (a lui/addiu pair's half, an address); its opcode only (a
-- jal or j, whose target is wherever the code was loaded).
local F, H16, OP = 0, 1, 2

local function site_at(read, site, at)
	for k = 1, #site.lines do
		local w, l, m = read(at + (k - 1) * 4), site.lines[k], site.mask[k]
		if m == F then
			if w ~= l then
				return false
			end
		elseif m == H16 then
			if math.floor(w / 0x10000) ~= math.floor(l / 0x10000) then
				return false
			end
		elseif math.floor(w / 0x4000000) ~= math.floor(l / 0x4000000) then
			return false
		end
	end
	return true
end

-- FMOD's SIF sends wait (no "-- [Name]" section: the fix is the whole script, not a game option to turn off).
-- EE, FMOD_Command_Send (0x312070 here): from lw a0, cid(s5) to the send semaphore's SignalSema (0x31218C here).
local EE_SEND = {
	lines = {0x8EA448F4, 0x26A53000, 0x24060060, 0x0240382D, 0x0220402D, 0x0C000000, 0x0200482D, 0x50400023,
		0x8EA548F4, 0x93A200AF, 0x10400004, 0x00000000, 0x0C000000, 0x8EA44A28, 0x8EB64A2C, 0x0C000000,
		0x8EA44A24},
	mask = {F, F, F, F, F, OP, F, F, F, F, F, F, OP, F, F, OP, F},
	known = 0x0031218C, -- SLUS-21818
	anchor = 2,         -- addiu a1, s5, 0x3000: the message buffer
}
local STUB_AT = 0x000FF300
EE_SEND.done = {{0x1C, 0x1040FFF8}, {0x14, jal(STUB_AT)}}

function EE_SEND.adopt()
	return ee(STUB_AT) == 0x27BDFFE0 and math.floor(ee(STUB_AT + 8) / 0x4000000) == 3 -- the stub, with its jal
end

-- sceSifDmaStat: the kernel's syscall 0x76 (0x347A80 here), among the game's other syscall wrappers, next to the
-- WaitSema that FMOD_Command_Send calls (0x347720 here).
local DMASTAT = {0x24030076, 0x0000000C, 0x03E00008, 0x00000000}

local function find_dmastat(near)
	for at = near - 0x800, near + 0x800, 4 do
		if ee(at) == DMASTAT[1] and ee(at + 4) == DMASTAT[2] and ee(at + 8) == DMASTAT[3] and ee(at + 12) == DMASTAT[4] then
			return at
		end
	end
	return nil
end

function EE_SEND.install(at)
	local dmastat = find_dmastat(target(ee(at + 0x30)))
	if not dmastat then
		return false
	end
	ee_write(STUB_AT, {
		0x27BDFFE0,                      -- addiu sp, sp, -0x20
		0xFFBF0010,                      -- sd    ra, 0x10(sp)
		ee(at + 0x14),                   -- jal   sceSifSendCmd, the game's own call
		0x00000000,                      -- nop
		0x10400008,                      -- beqz  v0, out: not queued (sent again by the caller)
		0xFFA20000,                      -- sd    v0, 0(sp): the DMA's id
		0xDFA40000,                      -- wait: ld a0, 0(sp)
		jal(dmastat),                    -- jal   sceSifDmaStat
		0x00000000,                      -- nop
		0x0441FFFC,                      -- bgez  v0, wait: not done yet
		0x00000000,                      -- nop
		0xDFA20000,                      -- ld    v0, 0(sp)
		0x00000000,                      -- nop
		0xDFBF0010,                      -- out: ld ra, 0x10(sp)
		0x03E00008,                      -- jr    ra
		0x27BD0020,                      -- addiu sp, sp, 0x20
	})
	eeObj.WriteMem32(at + 0x1C, 0x1040FFF8)      -- beqz v0, the first line: a failed send is set up and sent again
	eeObj.WriteMem32(at + 0x14, jal(STUB_AT))    -- jal 0xFF300
	return true
end

-- IOP, FMODEX.IRX's data DMA (0x8A080 here): from li a1, 1 (sceSifSetDma's count) to its sceSifDmaStat wait.
local IOP_DMA = {
	lines = {0x24050001, 0xAFB30010, 0xAFB10014, 0xAFB20018, 0x0C000000, 0xAFA0001C, 0x00408021, 0x16000008,
		0x3C040000, 0x24840000, 0x02602821, 0x02203021, 0x0C000000, 0x02403821, 0x08000000, 0x2402000D,
		0x12800005, 0x00001021, 0x0C000000, 0x02002021, 0x0441FFFD, 0x00001021},
	mask = {F, F, F, F, OP, F, F, F, H16, H16, F, F, OP, F, OP, F, F, F, OP, F, F, F},
	known = 0x0008A080, -- SLUS-21818
	anchor = 16,        -- li v0, 0xd: the error it returned
	done = {{0x24, 0x1000FFF6}, {0x28, 0x27A40010}},
}

-- IOP, FMODEX.IRX's FMOD_Command_Send (0x8A0F8 here): from addiu s1, s0, 0x3000 (the message) to the send
-- semaphore's SignalSema.
local IOP_SEND = {
	lines = {0x26113000, 0x02202821, 0x24060060, 0x8E0448C4, 0x02C03821, 0xAFB20010, 0x0C000000, 0xAFB30014,
		0x10400009, 0x3C040000, 0x12E00012, 0x00000000, 0x8E0449F8, 0x0C000000, 0x00000000, 0x8E1E49FC,
		0x08000000, 0x00000000, 0x24840000, 0x02203821, 0x241E000D, 0x8FA6004C, 0x8E0548C4, 0x24020060,
		0xAFA20010, 0xAFB60014, 0xAFB20018, 0x0C000000, 0xAFB3001C, 0x8E0449F4, 0x0C000000},
	mask = {F, F, F, F, F, F, OP, F, F, H16, F, F, F, OP, F, F, OP, F, H16, F, F, F, F, F, F, F, F, OP, F, F, OP},
	known = 0x0008A268, -- SLUS-21818
	anchor = 1,         -- addiu s1, s0, 0x3000
	done = {{0x20, 0x1040FFF7}, {0x24, 0x00408821}, {0x28, 0x12E00007}, {0x4C, 0x02202021}, {0x50, 0x0441FFFD}},
}

-- An import stub the module loader has linked: j to the library, li zero, its index.
local function linked(stub, index)
	return math.floor(iop(stub) / 0x4000000) == 2 and iop(stub + 4) == 0x24000000 + index
end

function IOP_DMA.install(at)
	-- relocated and linked: sceSifSetDma (sifman 7) and sceSifDmaStat (sifman 8) stubs past this code
	local setdma, stat = target(iop(at + 0x10)), target(iop(at + 0x48))
	if setdma <= at or stat <= at or not linked(setdma, 7) or not linked(stat, 8) then
		return false
	end
	IOP_DMA.stat = iop(at + 0x48)
	iopObj.WriteMem32(at + 0x28, 0x27A40010)     -- addiu a0, sp, 0x10: the transfer's record again
	iopObj.WriteMem32(at + 0x24, 0x1000FFF6)     -- b the first line: not queued, so queue it again
	return true
end

function IOP_DMA.adopt(at)
	IOP_DMA.stat = iop(at + 0x48) -- its jal sceSifDmaStat, for IOP_SEND
	return math.floor(IOP_DMA.stat / 0x4000000) == 3
end

function IOP_SEND.install(at)
	local send = target(iop(at + 0x18))
	if not IOP_DMA.stat or send <= at or not linked(send, 12) then -- sceSifSendCmd (sifcmd 12)
		return false
	end
	iop_write(at + 0x48, {
		IOP_DMA.stat,                    -- wait: jal sceSifDmaStat (where the failure was printed)
		0x02202021,                      -- move  a0, s1: the DMA's id
		0x0441FFFD,                      -- bgez  v0, wait: not done yet
		0x00000000,                      -- nop
		0x10000006,                      -- b     the send semaphore's SignalSema
		0x00000000,                      -- nop
	})
	iopObj.WriteMem32(at + 0x24, 0x00408821)     -- move s1, v0: keep the DMA's id
	iopObj.WriteMem32(at + 0x20, 0x1040FFF7)     -- beqz v0, the first line: not queued, so set up and send again
	iopObj.WriteMem32(at + 0x28, 0x12E00007)     -- beqz s7, wait: no answer wanted, so wait for the DMA instead
	return true
end

-- A site already patched (a save state made with this fix, or the script started again over patched code): the
-- words its install writes at fixed values, and its anchor line.
local function patched_at(read, site, at)
	for _, d in ipairs(site.done) do
		if read(at + d[1]) ~= d[2] then
			return false
		end
	end
	return read(at + (site.anchor - 1) * 4) == site.lines[site.anchor]
end

-- The site at this place: patched now, or taken as it is if it is patched already.
local function take(read, site, at)
	if site_at(read, site, at) then
		return site.install(at)
	end
	return patched_at(read, site, at) and (not site.adopt or site.adopt(at))
end

-- A site found before that is gone (the IRX loaded again, a save state without the fix) is looked for again.
local function still(read, site)
	return read(site.at + site.done[1][1]) == site.done[1][2]
end

-- The search while a site is missing: 512 words a vsync (each read costs the EE about 1.4 us; the first version of
-- this fix read 4096, a third of the EE's time, and for good after a save state made with the fix, whose patched
-- code it never recognised: the game at 85% speed, its sound breaking up), a few passes at most: the EE's code is
-- there from the start, the IOP's FMODEX.IRX comes later.
local WORDS = 512
local EE_SCAN = {read = ee, sites = {EE_SEND}, lo = 0x00100000, hi = 0x00600000, passes = 3}
local IOP_SCAN = {read = iop, sites = {IOP_DMA, IOP_SEND}, lo = 0x00010000, hi = 0x001F0000, passes = 40}

-- Each site at its known place first, then searched (its anchor line first).
local function step(s)
	local pending = false
	for _, site in ipairs(s.sites) do
		if site.at and not still(s.read, site) then
			site.at = nil
			s.left = nil
		end
		if not site.at then
			if take(s.read, site, site.known) then
				site.at = site.known
			else
				pending = true
			end
		end
	end
	if not pending then
		return
	end
	if not s.left then
		s.left, s.at = s.passes, s.lo
	end
	if s.left <= 0 then
		return
	end
	local stop = s.at + WORDS * 4
	for at = s.at, stop - 4, 4 do
		local w = s.read(at)
		for _, site in ipairs(s.sites) do
			local start = at - (site.anchor - 1) * 4
			if not site.at and w == site.lines[site.anchor] and start >= s.lo and take(s.read, site, start) then
				site.at = start
			end
		end
	end
	s.at = stop
	if s.at >= s.hi then
		s.at, s.left = s.lo, s.left - 1
	end
end

emuObj.AddVsyncHook(function()
	step(EE_SCAN)
	if okIop and iopObj then
		step(IOP_SCAN)
	end
end)
