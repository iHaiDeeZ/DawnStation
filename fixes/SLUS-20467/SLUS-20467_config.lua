-- Lara Croft Tomb Raider: The Angel of Darkness (USA) [SLUS-20467]: DawnStation's fix (2026-11-08, Lab), for the newer
-- core (core2).
--
-- The game stayed on a black screen from the start (the user: "i got black screen"). Seen live in the Lab: the PS2 at
-- about 55% speed (the core flipping 33 times a second) and the EE 100% at 0x207B10, in the game's PATH3 kick
-- (0x207A88, called at the end of a frame and from its VIF1 MARK 0xBA5E interrupt): it starts the GIF DMA of the
-- queued list (D2_TADR, D2_CHCR 0x105), then waits until GIF_STAT shows OPH (bit 9, "data going out") and then a
-- path active (APATH, bits 10-11), so that the VIF1 goes on only after PATH3 has the GIF. Sony's core never shows
-- either: its GIF_STAT word (core+0x7848628) read 0x4 throughout, and none of the core's 322 places that touch it
-- sets those bits; the DMA start waits in the core's event list and then runs in one go. So the first wait never
-- ends. The fix waits instead until the GIF DMA itself is done (D2_CHCR's STR clear: what the waits stood for, PATH3
-- out before the VIF1 goes on) and drops the second wait. The game's other GIF_STAT polls wait for an idle GIF, which
-- the core always shows (two of them have to wait for more: the third part below). The kick is found by its code
-- (the addresses below are this disc's), as are the other places below, and one patched already, in full or in part
-- (a save state made with this fix or an earlier one), is taken as it is and completed; if the game is already in the
-- old wait when the words go in, the new loop ends at once (its register still points at GIF_STAT, whose bit 8 is 0).
--
-- With that, the game ran at full speed into the Eidos logo video and froze in its MPEG error trap (0x1DB1A0: printf
-- "MPEG decoding error: '%s'", then an endless loop), with libmpeg's "slice_start_code(0x000001c1) out of range".
-- The game feeds the IPU its video ring 0x1000 bytes at a time (0x1DB1D8, called when the IPU waits for data); the
-- chunk sent last ended with a start code's 00 00 01 (ring + 0x1FFD), its code byte 05 in the next chunk, and the
-- 0xC1 read in its place is the first byte of the chunk's last qword (ring + 0x1FF0): when the IPU's input runs out
-- in the middle of a bit read, Sony's core gives the last qword again instead of waiting for more, as a PS2's IPU
-- does (the cause of psdevwiki's "skip the first video as it's still not fixed" on the European disc). The trap now
-- returns: libmpeg reports the picture as failed, the game prints "sceMpegGetPicture() failed" and goes on, and the
-- next picture decodes from good data, so a video shows a bad picture where it used to freeze. With both parts the
-- game plays (the user, 2026-11-08; live: both in, full speed, Lara in the first level).
--
-- In the pause menu the text did not show, and some graphics in the main menu came out wrong (the user): the textures
-- they sample were never sent. The game sends its textures to the GS through PATH3 each frame, from a queue of small
-- GIF DMA lists (built at 0x207BB8): the kick sends the frame's first one at the end of the frame (0x207C40) and the
-- others from the VIF1's MARK 0xBA5E interrupt. Right before that, the flip (0x207568) sends its own GS packet by a
-- normal GIF DMA (63 qwords: a screen-size copy and the draw buffer's clear) and waits until GIF_STAT shows no path
-- active; its CPCOND0 wait leaves the GIF channel out (it sets D_PCR from D_STAT). Sony's core takes a normal
-- transfer's first qwords into its GIF FIFO (16 at most) at the CHCR write, and sends them, moves the rest and clears
-- D2_CHCR's STR in an event later; a CHCR write while STR is set changes nothing but STR. So the kick wrote QWC 0,
-- MADR 0 and its chain start (D2_CHCR 0x105) over the flip's running transfer: the flip's packet was cut short and
-- the frame's first list never went out (seen live: the transfer's end each frame as a normal one, with the kick's
-- MADR 0 and list address, and the pause text's page, TBP 0x3200, holding a world texture instead of the font sent
-- from 0x3ABAF0). The flip's wait and the kick's first one, before it writes the registers, now wait while D2_CHCR's
-- STR is set, as the kick's own end does; the three other uploads next to them wait for the GIF channel with CPCOND0,
-- which the core keeps.
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

-- How a line is matched: the whole word; its upper half (a data address, the build's); its opcode (a call).
local F, H16, OP = "F", "H16", "OP"

-- the PATH3 kick: 56 lines from 0x207A88 here
local KICK = {
	lines = {0x3C020041, 0x8C426BE4, 0x10400033, 0x3C031000, 0x34633020, 0x00000000, 0x8C620000, 0x30420C00, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0x3C021000, 0x3C031000, 0x3442A020, 0x3463A010, 0xAC400000, 0x3C040FFF, 0xAC600000, 0x3484FFFF, 0x3C021000, 0x3C031000, 0x3C060041, 0x8CC66BE4, 0x3442A030, 0x3463A000, 0x24050105, 0x00C42024, 0xAC440000, 0xAC650000, 0x0000000F, 0x3C031000, 0x34633020, 0x00000000, 0x8C620000, 0x30420200, 0x00000000, 0x00000000, 0x00000000, 0x1040FFFA, 0x00000000, 0x3C031000, 0x34633020, 0x00000000, 0x8C620000, 0x30420C00, 0x00000000, 0x00000000, 0x00000000, 0x1040FFFA, 0x00000000, 0x8CC20008, 0x3C010041, 0xAC226BE4, 0x03E00008, 0x00000000},
	mask = {H16, H16, F, F, F, F, F, F, F, F, F, F, F, F, F, F, H16, H16, F, F, F, F, H16, H16, F, F, F, F, H16, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, H16, H16, H16, F, F},
	known = 0x00207A88,
	anchor = 25,
	patch = {
		{0x0010, 0x34633020, 0x3463A000}, -- ori v1, v1, 0x3020 -> 0xa000: before the kick, D2_CHCR, not GIF_STAT
		{0x001C, 0x30420C00, 0x30420100}, -- andi v0, v0, 0xc00 -> 0x100: wait while its STR is set, not APATH
		{0x0080, 0x34633020, 0x3463A000}, -- ori v1, v1, 0x3020 -> 0xa000: D2_CHCR, not GIF_STAT
		{0x008C, 0x30420200, 0x30420100}, -- andi v0, v0, 0x200 -> 0x100: its STR, not OPH
		{0x009C, 0x1040FFFA, 0x1440FFFA}, -- beqz -> bnez: wait while the transfer runs, not until it shows
		{0x00C4, 0x1040FFFA, 0x00000000}, -- beqz v0 (until a path shows active) -> nop
	},
}
-- the MPEG error trap: 14 lines from 0x1DB1A0 here
local TRAP = {
	lines = {0x27BDFFF0, 0x3C040041, 0xFFBF0000, 0x2484E588, 0x0C088882, 0x8CA50004, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x1000FFFA, 0x00000000, 0x00000000},
	mask = {F, H16, F, H16, OP, H16, F, F, F, F, F, F, F, F},
	known = 0x001DB1A0,
	anchor = 12,
	patch = {
		{0x0018, 0x00000000, 0xDFBF0000}, -- nop -> ld ra, 0(sp)
		{0x001C, 0x00000000, 0x0000102D}, -- nop -> move v0, zero
		{0x0020, 0x00000000, 0x03E00008}, -- nop -> jr ra: back to libmpeg instead of the endless loop below
		{0x0024, 0x00000000, 0x27BD0010}, -- nop -> addiu sp, sp, 0x10
	},
}
-- the flip's GS packet (a normal GIF DMA) and its wait: 31 lines from 0x207770 here
local FLIP = {
	lines = {0x3C031000, 0x240C0101, 0xFD420000, 0x3463A000, 0xDC820410, 0xFD620000, 0xAD0E0000, 0x8D020000, 0xAD220000, 0xACED0000, 0xACC50000, 0xAC6C0000, 0x0000000F, 0x0000040F, 0x41010007, 0x00000000, 0x41010005, 0x00000000, 0x41010003, 0x00000000, 0x4100FFF9, 0x00000000, 0x3C031000, 0x34633020, 0x8C620000, 0x30420C00, 0x00000000, 0x00000000, 0x00000000, 0x1440FFFA, 0xDFBF0000},
	mask = {F, F, H16, F, H16, H16, H16, H16, H16, H16, H16, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F},
	known = 0x00207770,
	anchor = 2,
	patch = {
		{0x005C, 0x34633020, 0x3463A000}, -- ori v1, v1, 0x3020 -> 0xa000: D2_CHCR, not GIF_STAT
		{0x0064, 0x30420C00, 0x30420100}, -- andi v0, v0, 0xc00 -> 0x100: wait while its STR is set, not APATH
	},
}

local SITES = {KICK, TRAP, FLIP}

-- The site's lines at this place, each patched line as it was or as install leaves it (a save state made with the
-- fix, or with an earlier one that had fewer of the patches).
local function site_at(site, at)
	for k = 1, #site.lines do
		local w, l, m = ee(at + (k - 1) * 4), site.lines[k], site.mask[k]
		for _, p in ipairs(site.patch) do
			if p[1] == (k - 1) * 4 and w == p[3] then
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

-- The site at this place, its lines not patched yet patched now.
local function take(site, at)
	if not site_at(site, at) then
		return false
	end
	for _, p in ipairs(site.patch) do
		if ee(at + p[1]) ~= p[3] then
			eeObj.WriteMem32(at + p[1], p[3])
		end
	end
	return true
end

-- A site found before that is gone (a save state made without the fix, or with fewer of its patches) is looked for
-- again.
local function still(site)
	for _, p in ipairs(site.patch) do
		if ee(site.at + p[1]) ~= p[3] then
			return false
		end
	end
	return true
end

-- The search while a site is missing: 512 words a vsync (each read costs the EE about 1.4 us) over the game's code,
-- four passes at most (the game loads its code at boot).
local WORDS = 512
local SCAN = {lo = 0x00100000, hi = 0x00300000, passes = 4}

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
