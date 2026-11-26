-- Burnout 3: Takedown (SLES-52585, Europe): Burnout 3's fix (fixes/SLUS-21050, where the reasons are), UNTESTED on
-- this disc (2026-11-26): the bloom's first column cleared 64 pixels wide, against the strip down the left. The
-- clear is looked for by its instructions, so no SLUS-21050 address has to match; if this disc's code differs,
-- nothing is written.
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
local KNOWN = 0x0026565C -- SLUS-21050's place; this disc's is looked for by the lines above

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
