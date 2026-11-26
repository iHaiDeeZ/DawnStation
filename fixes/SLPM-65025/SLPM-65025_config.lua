-- Devil May Cry (Japan, trial version, Nightmare Returns Pack disc 2) [SLPM-65025]: the European disc's fix
-- (fixes/SLES-50358, where the reasons are), UNTESTED on this disc (2026-11-18): the routine that adds the cutscene
-- faces' morph deltas builds each position in a 128-bit register whose upper half Sony's core doesn't keep at 0 (the
-- mouth's Z came out wrong, the faces broken); it is replaced by the same sum on the FPU. The routine is found by its
-- code (the European disc's place is only tried first), so nothing is written where this disc's routine differs.
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

local function ee_write(at, words)
	for k = 1, #words do
		eeObj.WriteMem32(at + (k - 1) * 4, words[k])
	end
end

local function words_at(at, words)
	for k = 1, #words do
		if ee(at + (k - 1) * 4) ~= words[k] then
			return false
		end
	end
	return true
end

-- The face delta (0x1B2090 on the European disc, called from its delta loop 0x1B1740): a0 the vertex written, a1
-- the vertex read (the same one, or the rest pose's), a2 the record, f12 the weight. Its 29 lines, up to jr ra and its
-- delay slot.
local DELTA = {
	lines = {0x70801E28, 0x70C02628, 0x70003489, 0xDC840000, 0x9CA60000, 0x70063FC9, 0x9CA60004, 0x00E63825,
		0x70073FC9, 0x9CA60008, 0x00E63825, 0x700737C9, 0x70042988, 0x70A42588, 0x44086000, 0x48A61000,
		0x48A41800, 0x48A82000, 0x4BE3193D, 0x4A22033C, 0x4BC418D8, 0x4BC310A8, 0x48261000, 0xAC660000,
		0x700637C9, 0xAC660004, 0x700637C9, 0x03E00008, 0xAC660008},
	fixed = {
		0x3C083D80, -- lui   t0, 0x3d80
		0x44881800, -- mtc1  t0, f3: 1/16
		0x84C80000, -- lh    t0, 0(a2): dx
		0x460C18C2, -- mul.s f3, f3, f12: the weight / 16
		0x44880000, -- mtc1  t0, f0
		0x84C80002, -- lh    t0, 2(a2): dy
		0x46800020, -- cvt.s.w f0, f0
		0x44880800, -- mtc1  t0, f1
		0x84C80004, -- lh    t0, 4(a2): dz
		0x46800860, -- cvt.s.w f1, f1
		0x44881000, -- mtc1  t0, f2
		0x46030002, -- mul.s f0, f0, f3
		0x468010A0, -- cvt.s.w f2, f2
		0x46030842, -- mul.s f1, f1, f3
		0x46031082, -- mul.s f2, f2, f3
		0xC4A30000, -- lwc1  f3, 0(a1): x
		0x46001800, -- add.s f0, f3, f0
		0xC4A30004, -- lwc1  f3, 4(a1): y
		0x46011840, -- add.s f1, f3, f1
		0xC4A30008, -- lwc1  f3, 8(a1): z
		0x46021880, -- add.s f2, f3, f2
		0xE4800000, -- swc1  f0, 0(a0)
		0xE4810004, -- swc1  f1, 4(a0)
		0x03E00008, -- jr    ra
		0xE4820008, -- swc1  f2, 8(a0) (delay slot)
		0x00000000, 0x00000000, 0x00000000, 0x00000000},
	known = 0x001B2090, -- the European disc's place (SLES-50358), only tried first
	anchor = 3,         -- pand a2, zero, zero: once in the European disc's code
	fixedAnchor = 4,    -- mul.s f3, f3, f12
}

-- The routine at this place: replaced now, or taken as it is if it is replaced already (a save state made with this
-- fix, or the script started again).
local function take(site, at)
	if words_at(at, site.lines) then
		ee_write(at, site.fixed)
		return true
	end
	return words_at(at, site.fixed)
end

-- A routine replaced before that is back (a save state made without the fix) is replaced again.
local function still(site)
	return ee(site.at + (site.fixedAnchor - 1) * 4) == site.fixed[site.fixedAnchor]
end

-- The search while it is missing: 512 words a vsync (each read costs the EE about 1.4 us), three passes over the
-- game's code at most (it is there from the start).
local WORDS = 512
local SCAN = {sites = {DELTA}, lo = 0x00100000, hi = 0x00400000, passes = 3}

local function step(s)
	local pending = false
	for _, site in ipairs(s.sites) do
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
		for _, site in ipairs(s.sites) do
			if not site.at then
				local start
				if w == site.lines[site.anchor] then
					start = at - (site.anchor - 1) * 4
				elseif w == site.fixed[site.fixedAnchor] then
					start = at - (site.fixedAnchor - 1) * 4
				end
				if start and start >= s.lo and take(site, start) then
					site.at = start
				end
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
