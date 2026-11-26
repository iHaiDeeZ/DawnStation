-- NASCAR 06: Total Team Control (SLUS-21266): DawnStation's fix (2026-11-06, Lab 00.08) for the shaking menus (the
-- user: "the menus are shaky"). The last six frames, read paused from the Lab, alternate between two pictures one PS2
-- line apart (frames 1, 3 and 5 identical, and 2, 4 and 6); PCSX2 needs AdaptiveTFF de-interlacing for the game
-- ("shaking otherwise"), and Sony's own deinterlacer (SetDeinterlace, SetDeinterlaceShift) changed nothing.
--
-- The cause is the game's flicker filter. In its 60 Hz display mode (the flag at gp-0x55CE, set at init from the
-- display config 0x5C07B8 / 0x5C07B9) the per-frame display update (0x2EFF58, mode 0: 0x2EF998) turns both read
-- circuits on, PMODE ALP 0x28: circuit 2 shows the frame, circuit 1 the same frame one line up or one line down,
-- alternating every frame (DISPFB1.DBY 2047 / 1, by the toggle at gp-0x55C0), for about 16 % of the line next to it on
-- an interlaced TV. Sony's core blends circuit 1 in far more strongly, so every frame leans a line up, then down.
-- The fix makes mode 0 always take its own filter-off path (circuit 2 only, DBY 0): `beqz v0` at 0x2EF9AC becomes `b`.
-- The flag itself stays, since it also sets the 60 Hz pacing (one vsync a frame instead of two).
--
-- 60 FPS (the user: "the fps seems low?"): races run at the game's own 30 fps, the emulator keeping up (the game's
-- 60 Hz tick and the vsyncs both 59.8 a second, its frame counter 30.0). The cap is a wait at 0x2EEB60 until the
-- vsync count of the frame (gp-0x7CC8) reaches 2: `slti v0, v0, 2` becomes 1, as PCSX2's [50 FPS] patch for the PAL
-- disc does (PeterDelta, SLES-53635 0x2BBE7C, "might need EE Overclock at 130%"). It can be turned off in the game's
-- page.

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- The mode 0 display setup's start (0x2EF998 here): addiu sp, sp, -0x20; sq s0, 0x10(sp); sd ra, 0(sp); jal (the
-- filter flag's getter, any address); move s0, a0; beqz v0, +0x60 (the filter-off path); addiu a2, zero, -0x200;
-- lw v0, 0x150(s0). Index 4 is the jal (any), index 6 the word the fix changes (either value). Looked for by these
-- words elsewhere (2048 a vsync, 0x100000 to 0x3FFFFF, given up after 10 passes), so other discs' copies are found too.
local SETUP = {0x27BDFFE0, 0x7FB00010, 0xFFBF0000, -1, 0x0080802D, -1, 0x2406FE00, 0x8E020150}
local BRANCH_AT, BRANCH_OLD, BRANCH_NEW = 0x14, 0x10400060, 0x10000060 -- beqz v0, +0x60 -> b +0x60
local site, scanAt, passes = nil, 0x00100000, 0

local function site_at(at)
	for k = 1, #SETUP do
		local word = eeObj.ReadMem32(at + (k - 1) * 4) & 0xFFFFFFFF
		if SETUP[k] >= 0 then
			if word ~= SETUP[k] then
				return false
			end
		elseif k == 4 then
			if (word & 0xFC000000) ~= 0x0C000000 then
				return false
			end
		elseif word ~= BRANCH_OLD and word ~= BRANCH_NEW then
			return false
		end
	end
	return true
end

local function find_site()
	if site and site_at(site) then
		return site
	end
	site = nil
	if site_at(0x002EF998) then
		site = 0x002EF998
		return site
	end
	if passes >= 10 then
		return nil
	end
	local stop = scanAt + 2048 * 4
	for at = scanAt, stop - 4, 4 do
		if (eeObj.ReadMem32(at) & 0xFFFFFFFF) == 0x27BDFFE0 and site_at(at) then
			site = at
			return site
		end
	end
	scanAt = stop
	if scanAt >= 0x00400000 then
		scanAt, passes = 0x00100000, passes + 1
	end
	return nil
end

-- The frame limiter (0x2EEB60 here): lw v0, X(gp) (the frame's vsync count); slti v0, v0, 2; three nops;
-- bnez v0, back to the lw; nop; jr ra. Index 1 is any lw v0 from gp, index 2 the word the 60 FPS section changes.
local LIMIT = {-1, -1, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x00000000, 0x03E00008}
local LIMIT_AT, LIMIT_OLD, LIMIT_NEW = 4, 0x28420002, 0x28420001 -- slti v0, v0, 2 -> 1
local limit, limitScan, limitPasses = nil, 0x00100000, 0

local function limit_at(at)
	for k = 1, #LIMIT do
		local word = eeObj.ReadMem32(at + (k - 1) * 4) & 0xFFFFFFFF
		if LIMIT[k] >= 0 then
			if word ~= LIMIT[k] then
				return false
			end
		elseif k == 1 then
			if (word & 0xFFFF0000) ~= 0x8F820000 then
				return false
			end
		elseif word ~= LIMIT_OLD and word ~= LIMIT_NEW then
			return false
		end
	end
	return true
end

local function find_limit()
	if limit and limit_at(limit) then
		return limit
	end
	limit = nil
	if limit_at(0x002EEB60) then
		limit = 0x002EEB60
		return limit
	end
	if limitPasses >= 10 then
		return nil
	end
	local stop = limitScan + 2048 * 4
	for at = limitScan, stop - 4, 4 do
		if (eeObj.ReadMem32(at + 4) & 0xFFFFFFFF) == LIMIT_OLD and limit_at(at) then
			limit = at
			return limit
		end
	end
	limitScan = stop
	if limitScan >= 0x00400000 then
		limitScan, limitPasses = 0x00100000, limitPasses + 1
	end
	return nil
end

local patcher = function()
	-- [No flicker filter (DawnStation)]
	local at = find_site()
	if at and (eeObj.ReadMem32(at + BRANCH_AT) & 0xFFFFFFFF) == BRANCH_OLD then
		eeObj.WriteMem32(at + BRANCH_AT, BRANCH_NEW)
	end
	-- [60 FPS (DawnStation)]
	local lim = find_limit()
	if lim and (eeObj.ReadMem32(lim + LIMIT_AT) & 0xFFFFFFFF) == LIMIT_OLD then
		eeObj.WriteMem32(lim + LIMIT_AT, LIMIT_NEW)
	end
end

emuObj.AddVsyncHook(patcher)
