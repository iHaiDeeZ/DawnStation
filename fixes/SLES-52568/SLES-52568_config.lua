-- Crash Twinsanity (Europe) [SLES-52568]: DawnStation's fix, the USA disc's (fixes/SLUS-20909, made there in the Lab;
-- untested here; psdevwiki's addresses for this disc are 0x790 past the USA disc's). Its patches are found
-- by their lines, so they go in only where this disc has the same code. The addresses below are the USA
-- disc's.
--
-- The game froze after the PS2 logo (the user: "it froze after the ps image"). Seen live in the Lab on the newer
-- core: the main thread spinning in the frame limiter's "elapsed time modulo one frame" loop (0x191C48: while the
-- time since the frame began is over a frame, take a frame, 9,600 ticks, off it), with the elapsed time negative
-- (0xFFFFD31A831D21EA as an unsigned 64-bit number): about 10^15 rounds. The game's clock (0x191920) is timer 0
-- (bus/256, 576,000 ticks a second, its overflow interrupt only) as (overflows << 16) | T0_COUNT, the overflows
-- counted by its interrupt handler (0x191980). The clock allows for one race only: a count read as exactly 0 just
-- before the handler has run. On a PS2 the interrupt comes within that tick; the core can take it later, so the
-- count reads 1, 2, ... while the overflow count is still the old one, and the clock goes back 65,536 ticks. The
-- frame begun at 0x12E616 (overflow 0x12, the clock's last overflow when it stopped) then ended "before" it began.
-- psdevwiki's config ("Fix random crashes") takes the loop's branch out; this one keeps the game's timing.
--
-- The fix: the clock's return goes through a stub at 0xFFE00 (free memory below the game) that keeps the last time
-- it returned (0xFFFF0) and, for a time less than one overflow (0x10000 ticks) behind it, adds the overflow whose
-- interrupt hasn't come yet; a time further back is a reset of the timer and taken as it is. And the limiter's two
-- compares become signed, so that a negative elapsed time ends its loop at once if it ever comes again. Both are
-- found by their lines (the addresses below are this disc's), so the same script serves the European disc too; a
-- place already patched (a save state made with the fix) is taken as it is.
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

-- How a line is matched: the whole word; its upper half (a gp-relative access, whose offset is the build's); its
-- opcode only (a jal, whose target is the build's).
local F, H16, OP = 0, 1, 2

local function site_at(site, at)
	for k = 1, #site.lines do
		local w, l, m = ee(at + (k - 1) * 4), site.lines[k], site.mask[k]
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

-- The clock (0x191920 here): its whole body, up to jr ra and the store in its delay slot.
local CLOCK = {
	lines = {0x24020001, 0x3C031000, 0xA38282E9, 0x8C650000, 0xDF8482E0, 0x938282E9, 0x14400006, 0x00000000,
		0x3C051000, 0x8CA50000, 0xDF8482E0, 0x10000006, 0x00000000, 0x14A00004, 0xDF828F78, 0x64830001,
		0x00441026, 0x0062200A, 0xDF8382E0, 0x30A2FFFF, 0x00042438, 0x00821025, 0x03E00008, 0xFF838F78},
	mask = {F, F, H16, F, H16, H16, F, F, F, F, H16, F, F, F, H16, F, F, F, H16, F, F, F, F, H16},
	known = 0x00191920, -- SLUS-20909 v2.00
	anchor = 18,        -- movz a0, v1, v0: the count-0 case
	done = {{0x58, 0x0803FF80}},
}
local STUB_AT, LAST_AT = 0x000FFE00, 0x000FFFF0

function CLOCK.install(at)
	ee_write(LAST_AT, {0, 0})
	ee_write(STUB_AT, {
		0x3C010010,              -- lui   at, 0x10
		0xDC24FFF0,              -- ld    a0, -0x10(at): the last time returned (0xFFFF0)
		0x0082282F,              -- dsubu a1, a0, v0: how far the new one is behind it
		0x18A00005,              -- blez  a1, out: not behind
		0x3C030001,              -- lui   v1, 1 (delay slot): one overflow, 0x10000 ticks
		0x00A3282F,              -- dsubu a1, a1, v1
		0x04A10002,              -- bgez  a1, out: an overflow or more behind: the timer reset, taken as it is
		0x00000000,              -- nop
		0x0043102D,              -- daddu v0, v0, v1: the overflow whose interrupt hasn't come yet
		0x03E00008,              -- out: jr ra
		0xFC22FFF0,              -- sd    v0, -0x10(at) (delay slot): kept for the next time
	})
	eeObj.WriteMem32(at + 0x58, 0x0803FF80)      -- j 0xFFE00 (for jr ra; the store in its delay slot stays)
	return true
end

function CLOCK.adopt()
	return ee(STUB_AT) == 0x3C010010 and ee(STUB_AT + 0x24) == 0x03E00008
end

-- The frame limiter (0x191BD0 here): from its first line to the end of its loop.
local LIMIT = {
	lines = {0x27BDFFE0, 0xFFB00000, 0xFFB10008, 0x0080802D, 0xFFB20010, 0xFFBF0018, 0x8E020070, 0x8E030068,
		0x44820000, 0x00000000, 0x46800020, 0x0043001B, 0x46006302, 0x46006024, 0x44030000, 0x0060902D,
		0x00001012, 0x0002103C, 0x0C000000, 0x0002883E, 0xDE030078, 0xDE040080, 0x0223282D, 0x0044182F,
		0x00A3102B, 0x1040000B, 0x0223102F, 0x00A0202D, 0x0071182F, 0x00000000, 0x0083102B, 0x00000000,
		0x00000000, 0x00000000, 0x5440FFFB, 0x0071182F, 0x0223102F},
	mask = {F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, OP, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F,
		F, F},
	known = 0x00191BD0, -- SLUS-20909 v2.00
	anchor = 12,        -- divu v0, v1: ticks a frame
	done = {{0x60, 0x00A3102A}, {0x78, 0x0083102A}},
}

function LIMIT.install(at)
	eeObj.WriteMem32(at + 0x60, 0x00A3102A)      -- slt v0, a1, v1 (was sltu): over a frame, as a signed number
	eeObj.WriteMem32(at + 0x78, 0x0083102A)      -- slt v0, a0, v1 (was sltu): the loop's test, the same
	return true
end

-- A site already patched (a save state made with this fix, or the script started again over patched code): the
-- words its install writes at fixed values, and its anchor line.
local function patched_at(site, at)
	for _, d in ipairs(site.done) do
		if ee(at + d[1]) ~= d[2] then
			return false
		end
	end
	return ee(at + (site.anchor - 1) * 4) == site.lines[site.anchor]
end

-- The site at this place: patched now, or taken as it is if it is patched already.
local function take(site, at)
	if site_at(site, at) then
		return site.install(at)
	end
	return patched_at(site, at) and (not site.adopt or site.adopt(at))
end

-- A site found before that is gone (a save state made without the fix) is looked for again.
local function still(site)
	return ee(site.at + site.done[1][1]) == site.done[1][2]
end

-- The search while a site is missing: 512 words a vsync (each read costs the EE about 1.4 us), three passes over the
-- game's memory at most (its code is there from the start).
local WORDS = 512
local SCAN = {sites = {CLOCK, LIMIT}, lo = 0x00100000, hi = 0x00600000, passes = 3}

-- Each site at its known place first, then searched (its anchor line first).
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

-- [Colour scan lines (psdevwiki)]
-- psdevwiki's title fix for the game ("Eliminate color scan lines", made on the Code Veronica X emulator): Sony's
-- simple fetch for point-sampled (texMode 1) textures, as Crash Bandicoot: The Wrath of Cortex's underwater stripes.
emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", { texMode = 1 })
