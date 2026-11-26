-- SSX 3 (Korea, Big Hit Series) [SLKA-25200]: DawnStation's fix, the USA disc's (fixes/SLUS-20772, made there in the
-- Lab, 2026-11-08), for the newer core (core2); UNTESTED on this disc. The two waits are found by their code and
-- patched only where this disc has the same routine; the addresses below are the USA disc's.
--
-- The USA disc:
-- SSX 3 (USA) [SLUS-20772]: DawnStation's fix (2026-11-08, Lab), for the newer core (core2).
--
-- The game stayed on a black screen at 60 fps (the user: "check this game, stuck"; psdevwiki: "Blackscreen and
-- annoying noise after trying to load the maps/peaks"). Seen live in the Lab: the PS2 at full speed and the EE in
-- the loop at 0x2EC810, which waits for VIF1_STAT & 0x1F000003 (VIF1 busy, its FIFO count) to be 0 after the game has
-- read an image back from the GS through VIF1 (0x2EC738: VIF1_STAT.FDR and the GS's BUSDIR set, VIF1's DMA run the
-- other way, then its DMA and GIF waits). On a PS2 the FIFO drains and the wait ends; Sony's core leaves VIF1_STAT
-- busy after such a read, so the game waits forever. psdevwiki's script (data/wikifix/SLUS-20772.lua, not used by
-- default: a Lua-only entry, and its last line, "#Use WOTM emu", isn't Lua) turns this wait and the one before the
-- read (0x2EC678) into straight lines. This does the same, finding the two by their code (the same 11-word wait is
-- in five other places, which end on their own and are left alone), and takes a place already patched (a save state
-- made with the fix) as it is. A save state made while stuck stays stuck: start the game again. On the console
-- (2026-11-08, Lab): both waits patched, the game racing at full speed.
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

-- How a line is matched: the whole word; its upper half (a frame or struct offset, the build's); its opcode (a call).
local F, H16, OP = "F", "H16", "OP"

-- the wait before the download starts: 24 lines from 0x2EC634 here
local BEFORE = {
	lines = {0x26226510, 0x3C031000, 0xAFA2001C, 0x263464A0, 0x263664C0, 0x3463A000, 0x00000000, 0x8C620000, 0x30420100, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x3C041000, 0x3C031F00, 0x34843C00, 0x34630003, 0x8C820000, 0x00431024, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x00000000},
	mask = {H16, F, H16, H16, H16, F, F, F, F, F, F, F, F, F, F, F, F, H16, F, F, F, F, F, F},
	known = 0x002EC634,
	anchor = 15,
	patch = {{0x0058, 0x1440FFFA, 0x00000000}}, -- bnez v0, (the wait) -> nop
}
-- the wait after the download's DMA: 35 lines from 0x2EC7A0 here
local AFTER = {
	lines = {0xACA20000, 0xAC860000, 0x8C820000, 0x30420100, 0x1040000A, 0x3C031000, 0x34639000, 0x00000000, 0x8C620000, 0x30420100, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x00000000, 0x3C031000, 0x3463A000, 0x00000000, 0x8C620000, 0x30420100, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x3C041000, 0x3C031F00, 0x34843C00, 0x34630003, 0x8C820000, 0x00431024, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x00000000},
	mask = {H16, H16, H16, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, H16, F, F, F, F, F, F},
	known = 0x002EC7A0,
	anchor = 26,
	patch = {{0x0084, 0x1440FFFA, 0x00000000}}, -- bnez v0, (the wait) -> nop
}

local SITES = {BEFORE, AFTER}

-- The site's lines at this place, as they were (patched false) or as install leaves them (patched true).
local function site_at(site, at, patched)
	for k = 1, #site.lines do
		local w, l, m = ee(at + (k - 1) * 4), site.lines[k], site.mask[k]
		for _, p in ipairs(site.patch) do
			if patched and p[1] == (k - 1) * 4 then
				l, m = p[3], F
			end
		end
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

-- The site at this place: patched now, or taken as it is if it is patched already.
local function take(site, at)
	if site_at(site, at, false) then
		for _, p in ipairs(site.patch) do
			eeObj.WriteMem32(at + p[1], p[3])
		end
		return true
	end
	return site_at(site, at, true)
end

-- A site found before that is gone (a save state made without the fix) is looked for again.
local function still(site)
	local p = site.patch[1]
	return ee(site.at + p[1]) == p[3]
end

-- The search while a site is missing: 512 words a vsync (each read costs the EE about 1.4 us) over the game's code,
-- four passes at most (the game loads its code at boot; the waits come with the first mountain).
local WORDS = 512
local SCAN = {lo = 0x00200000, hi = 0x00400000, passes = 4}

-- Each site at its known place first, then searched (its anchor line first).
local function step(s)
	local pending = false
	for _, site in ipairs(SITES) do
		if site.at and not still(site) then
			site.at = nil
			s.left = nil
		end
		if not site.at then
			if take(site, site.known) then
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
		local w = ee(at)
		for _, site in ipairs(SITES) do
			local start = at - (site.anchor - 1) * 4
			if not site.at and w == site.lines[site.anchor] and start >= s.lo and take(site, start) then
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
	step(SCAN)
end)
