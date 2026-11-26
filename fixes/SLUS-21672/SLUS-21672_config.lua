-- Guitar Hero III: Legends of Rock (USA) [SLUS-21672]: DawnStation's fix (2026-11-17, Lab), for the Jak X core.
--
-- The game stayed on a black screen (the user: "it have black screen issue"). Seen live in the Lab: the PS2 at full
-- speed and the EE in the loop at 0x1A0188, which waits for VIF1_STAT & 0x1F000003 to be 0 after the game has read
-- an image back from the GS through VIF1. The routine (0x19FEF0, called every frame from 0x19ED28) goes through a
-- list of read-backs at [0x373308] (the one seen: 64 x 32 pixels, 512 qwords from GS block 0x3F80 into 0x415F80).
-- With VIF1_STAT.FDR set the core shows FQC from its count of read-back data still owed (core2 file 0x804FF18, set
-- from the transfer's size at TRXDIR, lowered by what is read), and that count stays at 16 or more after the game's
-- DMA has taken the whole image, so the wait never ends. VIF1's own FIFO is empty then, and BUSDIR going back to 0
-- drops what the core still holds, so that wait's bnez becomes a nop (SSX 3's hang and fix, fixes/SLUS-20772).
--
-- The place is found by its code (21 lines), the USA disc's place first; a place already fixed is taken as it is.
-- Code left by this fix's test versions in a save state is put back as the game has it: the reset in that wait's
-- loop, the nop on the wait before the read-back, the read-back routine's forced early return.
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

-- The VIF1-idle wait after the read-back, then FDR cleared: 21 lines from 0x1A0158 here.
local AFTER = {
	lines = {0xAE330000, 0x0000000F, 0x8E430000, 0x3C021F00, 0x34420003, 0x00621824, 0x1060000B, 0x00000000, 0x3C041000, 0x3C031F00, 0x34843C00, 0x34630003, 0x8C820000, 0x00431024, 0x00000000, 0x00000000, 0x1440FFFB, 0x00000000, 0x92420002, 0x3042007F, 0xA2420002},
	known = 0x001A0158,
	anchor = 11,
	want = {[0x40] = 0x00000000}, -- bnez v0, (the wait) -> nop
	olds = { -- a test version's VIF1 reset in the wait's loop
		{[0x30] = 0x8E440020, [0x34] = 0x8E450030, [0x38] = 0x24020001, [0x3C] = 0xAE420010, [0x40] = 0xAE440020, [0x44] = 0xAE450030},
	},
	key = 0x40,
}
-- The FINISH wait and the VIF1-idle wait before the read-back: 20 lines from 0x19FFF0 here. Wanted as the game has it.
local BEFORE = {
	lines = {0x3C031200, 0x0004983C, 0x0013983F, 0x34631000, 0xDC620000, 0x30420002, 0x00000000, 0x00000000, 0x1040FFFB, 0x3C041000, 0x3C031F00, 0x34843C00, 0x34630003, 0x00000000, 0x8C820000, 0x00431024, 0x00000000, 0x00000000, 0x1440FFFB, 0x00000000},
	known = 0x0019FFF0,
	anchor = 12,
	want = {},
	olds = {{[0x48] = 0x00000000}}, -- a test version's nop on that wait's bnez
	key = 0x48,
}
-- The read-back routine's register saves, its "list empty" branch and its I/O constants: 24 lines from 0x19FF00 here.
-- Wanted as the game has it.
local EXIT = {
	lines = {0xFFB10008, 0xFFB20010, 0xFFB30018, 0xFFB40020, 0xFFB50028, 0xFFB60030, 0xFFB70038, 0xFFBE0040, 0x120000A6, 0xFFBF0048, 0x3C111000, 0x3C1E1200, 0x3C171200, 0x3C161000, 0x3C151000, 0x3C121000, 0x3C141200, 0x36319000, 0x37DE1010, 0x36F71000, 0x36D69020, 0x36B59010, 0x36523C00, 0x36941040},
	known = 0x0019FF00,
	anchor = 19,
	want = {},
	olds = {{[0x20] = 0x100000A6}}, -- a test version's "b" in place of the beqz
	key = 0x20,
}

local SITES = {AFTER, BEFORE, EXIT}

-- The site's lines at this place in a form (its words over the lines; nil: the game's own code).
local function form_at(site, at, form)
	for k = 1, #site.lines do
		local off = (k - 1) * 4
		local w = site.lines[k]
		if form and form[off] then
			w = form[off]
		end
		if ee(at + off) ~= w then
			return false
		end
	end
	return true
end

-- The site at this place: as wanted already, or brought there from the game's own code or an earlier version's.
local function take(site, at)
	if form_at(site, at, site.want) then
		return true
	end
	local ok = form_at(site, at, nil)
	for _, old in ipairs(site.olds) do
		ok = ok or form_at(site, at, old)
	end
	if not ok then
		return false
	end
	for k = 1, #site.lines do
		local off = (k - 1) * 4
		local w = site.want[off] or site.lines[k]
		if ee(at + off) ~= w then
			eeObj.WriteMem32(at + off, w)
		end
	end
	return true
end

-- A site found before is looked for again once its key word changes (a save state loaded since).
local function still(site)
	local w = site.want[site.key] or site.lines[site.key / 4 + 1]
	return ee(site.at + site.key) == w
end

-- The search while a site is missing: 512 words a vsync (each read costs the EE about 1.4 us) over the game's code
-- (0x100000-0x340000), from near the USA disc's place first, four passes at most.
local WORDS = 512
local SCAN = {lo = 0x00100000, hi = 0x00340000, start = 0x00180000, passes = 4}

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
		s.left, s.at = s.passes, s.start
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
