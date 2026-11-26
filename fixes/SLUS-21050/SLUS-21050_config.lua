-- Burnout 3: Takedown (SLUS-21050): DawnStation's fix (2026-11-26, Lab 00.29) for the strip of colour down the left of
-- the screen (psdevwiki: "Stripes of colour on the left part of the screen"), Burnout Revenge's (fixes/SLES-53506,
-- where the reasons are). It is the bloom's first column. The bloom works in page columns of a 128-wide buffer that
-- lives in the Z buffer's memory (pages 0xD2 / 0xD3, blocks 0x1A40 / 0x1A60): a column is cleared to the bloom
-- threshold (0xBF in the race seen), the frame is blended into it, and it is halved and blurred. The first column's
-- clear is one 32x448 sprite with FRAME_1 and ZBUF_1 at the same address, colour (alpha masked) and Z24 both written
-- (TEST_1 0x30003): on a PS2 the Z half lands on the other 32 pixels of the page, so the whole column is cleared.
-- Sony's core keeps colour and depth apart, so half of that column kept old data, and the bloom drew it. The fix
-- makes that clear 64 pixels wide (colour and Z, as before), which leaves the same pixels in memory.
--
-- The freeze on the first race's loading screen is other work: the in-game menu's stronger VU1 program hash (the newer
-- core, Jak X build), on for this disc by default.
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

-- The clear's packet code (0x26565C here), from TEST_1's value to the sprite's second corner going out: lui t3, 3;
-- sq t4, 0x30(t7) (ALPHA_1); addiu t2, zero, 0x47; ori t4, t3, 3 (TEST_1 0x30003); ... sll t3, a2, 4 (the height);
-- ... dsll v1, t2, 16; pcpyld s3, s3, t1; ori v1, v1, 0x200 (x 32); or t1, t5, v1 (the threshold as Z); pcpyld;
-- sq s5, 0x70(t7). Line 18 is the one the fix changes.
local LINES = {0x3C0B0003, 0x7DEC0030, 0x240A0047, 0x356C0003, 0x714C5389, 0x7DEA0040, 0x35721001, 0x71C35389,
	0x240C0005, 0x7DEA0050, 0x00065900, 0x718D1B89, 0x000B503C, 0x7DE30060, 0x000A503E, 0x000A1C38, 0x72699B89,
	0x34630200, 0x01A34825, 0x7189AB89, 0x7DF50070}
local X_LINE, X_OLD, X_NEW = 18, 0x34630200, 0x34630400 -- ori v1, v1, 0x200 -> 0x400: x 32 -> 64
local ANCHOR = 4 -- ori t4, t3, 3 (TEST_1's value): the search's first test
local KNOWN = 0x0026565C -- SLUS-21050

-- The clear's code at this place, with this word as its x line.
local function code_at(at, x)
	for k = 1, #LINES do
		local want = LINES[k]
		if k == X_LINE then
			want = x
		end
		if ee(at + (k - 1) * 4) ~= want then
			return false
		end
	end
	return true
end

-- The place patched now, or taken as it is if it is patched already (a save state made with this fix, or the script
-- started again over patched code).
local function take(at)
	if code_at(at, X_OLD) then
		eeObj.WriteMem32(at + (X_LINE - 1) * 4, X_NEW)
		return true
	end
	return code_at(at, X_NEW)
end

-- The search while the place is missing: 512 words a vsync (each read costs the EE about 1.4 us), four passes over
-- the game's code at most (it is there from the start, after the PS2 logo); the known place first.
local WORDS, LO, HI, PASSES = 512, 0x00100000, 0x00400000, 4
local site, scanAt, left = nil, nil, nil

local function step()
	if site then
		if ee(site + (X_LINE - 1) * 4) == X_NEW then
			return
		end
		site, left = nil, nil -- gone (a save state made without the fix): looked for again
	end
	if take(KNOWN) then
		site = KNOWN
		return
	end
	if not left then
		left, scanAt = PASSES, LO
	end
	if left <= 0 then
		return
	end
	local stop = scanAt + WORDS * 4
	for at = scanAt, stop - 4, 4 do
		if ee(at) == LINES[ANCHOR] then
			local start = at - (ANCHOR - 1) * 4
			if start >= LO and take(start) then
				site = start
				return
			end
		end
	end
	scanAt = stop
	if scanAt >= HI then
		scanAt, left = LO, left - 1
	end
end

-- [Bloom first column clear (DawnStation)]
-- The fix above, at every vsync (one read once the place is found).
emuObj.AddVsyncHook(step)
