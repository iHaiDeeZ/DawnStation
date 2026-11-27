-- Sonic Gems Collection (SLKA-25308, Korea):
-- Sonic Gems Collection's fix (fixes/SLES-53350, where the reasons are), UNTESTED on this disc (2026-11-27): the
-- game uploads Sonic the Fighters' palette data instead of drawing it, and DawnStation's in-game module (this
-- folder's gs_pal_cpu) makes each 3D quad's 16 colours: right colours, without the draws that made it slow. The
-- routine and the template are found by their words, so no SLES-53350 address has to match; if this disc's code
-- differs, nothing is written.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local gpr = require("ee-gpr-alias")

-- SLES-53350's places are tried first; this disc's may be elsewhere, so they're looked for too (512 words a vsync
-- while Sonic the Fighters' routine isn't found).
local SEARCH = true

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

local function hi16(v)
	return math.floor(v / 65536)
end

-- The routine (buffer): its first 19 words expand the row table in the scratchpad (0x70000800: page * 128 + row * 4 +
-- channel), the same in every version; +0x14 is a jal (checked by kind). From +0x4C, 86 words: the game's ramp lines,
-- the first version's or this one's.
local KNOWN = 0x0018C5C0
local HEAD = {
	{0x00, 0x27BDFFE0}, {0x04, 0x24060080}, {0x08, 0xFFBF0010}, {0x0C, 0x7FB00000}, {0x10, 0x0080802D},
	{0x18, 0x0000202D}, {0x1C, 0x3C057000}, {0x20, 0x24030100}, {0x24, 0x34A60800}, {0x28, 0xDCA40000},
	{0x2C, 0x2063FFFF}, {0x30, 0x20A50008}, {0x34, 0x70842588}, {0x38, 0x70042788}, {0x3C, 0x700420FE},
	{0x40, 0x7CC40000}, {0x44, 0x1403FFF8}, {0x48, 0x20C60010},
}
local ANCHOR, ANCHOR_AT = 0x70842588, 0x34 -- the search's first test (a rare MMI word)
local RA_INSIDE = 0x18 -- ra while the routine runs (after its one call)
local TAIL_AT = 0x4C

-- The game's tail: PRIM 0x311 loaded, then for each page, channel and 8 rows, lbu + PRIM, UV, UV (stores off a2).
local GAME_BODY = {
	0x01652021, 0x908E0000, 0x254A0008, 0x294D0020, 0x24A50020, 0x000E7138, 0xFCC30000, 0x000E7438, 0xFCCE0008,
	0x35CE03FF, 0xFCCE0018, 0x908E0004, 0x000E7138, 0xFCC30028, 0x000E7438, 0xFCCE0030, 0x35CE03FF, 0xFCCE0040,
	0x908E0008, 0x000E7138, 0xFCC30050, 0x000E7438, 0xFCCE0058, 0x35CE03FF, 0xFCCE0068, 0x908E000C, 0x000E7138,
	0xFCC30078, 0x000E7438, 0xFCCE0080, 0x35CE03FF, 0xFCCE0090, 0x908E0010, 0x000E7138, 0xFCC300A0, 0x000E7438,
	0xFCCE00A8, 0x35CE03FF, 0xFCCE00B8, 0x908E0014, 0x000E7138, 0xFCC300C8, 0x000E7438, 0xFCCE00D0, 0x35CE03FF,
	0xFCCE00E0, 0x908E0018, 0x000E7138, 0xFCC300F0, 0x000E7438, 0xFCCE00F8, 0x35CE03FF, 0xFCCE0108, 0x9084001C,
	0x00042138, 0xFCC30118, 0x00042438, 0xFCC40120, 0x348403FF, 0xFCC40130,
}
-- The first version's loop body: the rows written as one-row sprites (PRIM 0x316), both corners included.
local V1_BODY = {
	0x01652021, 0x000A7D38, 0x3C180010, 0x24190008, 0x00C0102D, 0x908E0000, 0xFC430000, 0x000E7538, 0xFC4E0008,
	0x35CE03FF, 0xFC4E0018, 0xFC4F0010, 0x01F8782D, 0x35EE03FE, 0xFC4E0020, 0x24840004, 0x2739FFFF, 0x1720FFF3,
	0x64420028, 0x254A0008, 0x294D0020, 0x24A50020,
}
local function tail_of(prim, body)
	local t = {0x3C037000, 0x26090050, 0x34680800, 0x0000602D, prim, 0x25270010, 0x0000582D, 0x24E60030, 0x0000502D,
		0x0100282D, 0x00000000}
	for i = 1, 60 do
		t[#t + 1] = body[i] or 0
	end
	for _, w in ipairs({0x15A0FFC3, 0x24C60140, 0x256B0001, 0x29640003, 0x1480FFBB, 0x24E70530, 0x258C0001,
			0x25290FA0, 0x29840020, 0x1480FFB4, 0x25080080, 0xDFBF0010, 0x7BB00000, 0x03E00008, 0x27BD0020}) do
		t[#t + 1] = w
	end
	return t
end
local TAIL_GAME = tail_of(0x24030311, GAME_BODY)
local TAIL_V1 = tail_of(0x24030316, V1_BODY)
-- This version's tail: page 0's DMA tag becomes NEXT (262 qwords, then on at buffer + 0x1F450, past the 32 ramp
-- blocks), followed by A+D BITBLTBUF (0x3400, width 1, CT32), TRXPOS 0, TRXREG 64x16, TRXDIR (host to GS) and an IMAGE
-- tag of 256 qwords, then the scratchpad's 4 KB row table copied in after it, 32 bytes a turn. The rest are nops.
local TAIL_FIX = {
	0x3C090001, 0x3529F450, 0x0209482D, 0x0009483C, 0x3C0A2000, 0x354A0106, 0x012A4825, 0xFE090050,
	0x3C0A5100, 0x354A0106, 0x000A503C, 0xFE0A0058, 0x3C0A4000, 0x000A503C, 0x354A0001, 0xFE0A0060,
	0x340AEEEE, 0xFE0A0068, 0x3C0A0001, 0x354A3400, 0x000A503C, 0xFE0A0070, 0x340A0050, 0xFE0A0078,
	0xFE000080, 0x340A0051, 0xFE0A0088, 0x340A0010, 0x000A503C, 0x354A0040, 0xFE0A0090, 0x340A0052,
	0xFE0A0098, 0xFE0000A0, 0x340A0053, 0xFE0A00A8, 0x3C0A0800, 0x000A503C, 0x354A0100, 0xFE0A00B0,
	0xFE0000B8, 0x3C0B7000, 0x356B0800, 0x660C00C0, 0x240D0080, 0x796E0000, 0x796F0010, 0x25ADFFFF,
	0x656B0020, 0x7D8E0000, 0x7D8F0010, 0x15A0FFF9, 0x658C0020, 0xDFBF0010, 0x7BB00000, 0x03E00008,
	0x27BD0020,
}
for i = #TAIL_FIX + 1, #TAIL_GAME do
	TAIL_FIX[i] = 0
end

-- The template's sender, right after the routine (+0x264): lui a0, hi; addiu a1, zero, 0x21 (its VU1 qword); addiu
-- a0, a0, lo; jal; addiu a2, zero, 0x11 (qwords).
local function template_of(b)
	local hi, lo = ee(b + 0x264), ee(b + 0x26C)
	if hi16(hi) ~= 0x3C04 or ee(b + 0x268) ~= 0x24050021 or hi16(lo) ~= 0x2484 or
			math.floor(ee(b + 0x270) / 67108864) ~= 3 or ee(b + 0x274) ~= 0x24060011 then
		return nil
	end
	local l = lo % 65536
	if l >= 32768 then
		l = l - 65536
	end
	return (hi % 65536) * 65536 + l
end
-- The template's first 13 qwords (the 14th, the quad's TEST_1/TEX0_1/TEX1_1 packet's tag, stays). The game's (PACKED,
-- PRIM LINE: A+D CLAMP_2, then UV and XYZ2 four times, A+D TEXFLUSH, CLAMP_2; then a spare CLAMP_2 outside the
-- packet: before each quad VU1 fills in the UVs and copies that 13th qword over the 2nd) and the first version's
-- (sprites) share these words and differ in three:
local T_OLD = {
	{0x00, 0x00008001}, {0x08, 0x3E3E3E3E}, {0x0C, 0x00000EEE}, {0x18, 0x00000009}, {0x30, 0}, {0x34, 0}, {0x38, 5},
	{0x54, 0}, {0x58, 5}, {0x70, 0x00100000}, {0x74, 0}, {0x78, 5}, {0x94, 0}, {0x98, 5}, {0xA8, 0x3F}, {0xB8, 9},
	{0xC8, 9},
}
local T_GAME = {{0x04, 0xB188C000}, {0x50, 0x0000007E}, {0x90, 0x0010007E}}
local T_V1 = {{0x04, 0xB18B4000}, {0x50, 0x0010007E}, {0x90, 0x0020007E}}
-- This version's: PACKED, 8 x A+D; VU1 still fills in the UV slots' first two words (U, V) and copies the 13th qword
-- over the 2nd, so both hold BITBLTBUF (Lab 00.32's first try had 0 there: every upload went to the last
-- BITBLTBUF's place, none to 0x3360, and the models came out white).
local T_FIX = {
	0x00000001, 0x80000000, 0xEEEEEEEE, 0, -- the tag: NLOOP 1, NREG 8, all A+D (no PRIM: nothing drawn)
	0, 0x00013360, 0x50, 0,                 -- BITBLTBUF: block 0x3360, width 1, CT32
	0, 0, 0x35, 0,                          -- U1, V: MIPTBP1_2
	0, 0, 0x51, 0,                          -- TRXPOS 0
	0, 0, 0x37, 0,                          -- U2, V: MIPTBP2_2
	8, 2, 0x52, 0,                          -- TRXREG 8x2
	0, 0, 0x34, 0,                          -- U3, V: MIPTBP1_1
	0, 0, 0x53, 0,                          -- TRXDIR: host to GS
	0, 0, 0x36, 0,                          -- U4, V: MIPTBP2_1
	0x00008004, 0x08000000, 0, 0,           -- IMAGE, 4 qwords (the last one the next packet's tag)
	0x4E574144, 0x314C4150, 0x494E4F53, 0x52544643, -- "DAWNPAL1SONICFTR": the module's mark
	0, 0, 0, 0,
	0, 0x00013360, 0x50, 0,                 -- BITBLTBUF again: VU1 copies it over the 2nd qword before each quad
}

-- "fix", "v1", "game" or nil (something else).
local function routine_state(b)
	for _, s in ipairs(HEAD) do
		if ee(b + s[1]) ~= s[2] then
			return nil
		end
	end
	if math.floor(ee(b + 0x14) / 67108864) ~= 3 then
		return nil
	end
	local fix, v1, game = true, true, true
	for i = 1, #TAIL_GAME do
		local v = ee(b + TAIL_AT + (i - 1) * 4)
		fix = fix and v == TAIL_FIX[i]
		v1 = v1 and v == TAIL_V1[i]
		game = game and v == TAIL_GAME[i]
		if not fix and not v1 and not game then
			return nil
		end
	end
	return (fix and "fix") or (v1 and "v1") or "game"
end

-- "fix", "v2a" (Lab 00.32's first try, as in a save state made with it: the 13th qword 0), "v1", "game" or nil.
local function template_state(t)
	local fix, v2a = true, true
	for i = 1, #T_FIX do
		local v = ee(t + (i - 1) * 4)
		if v ~= T_FIX[i] then
			fix = false
			v2a = v2a and i > 48 and v == 0
		end
	end
	if fix then
		return "fix"
	elseif v2a then
		return "v2a"
	end
	for _, s in ipairs(T_OLD) do
		if ee(t + s[1]) ~= s[2] then
			return nil
		end
	end
	local game, v1 = true, true
	for i = 1, 3 do
		game = game and ee(t + T_GAME[i][1]) == T_GAME[i][2]
		v1 = v1 and ee(t + T_V1[i][1]) == T_V1[i][2]
	end
	return (game and "game") or (v1 and "v1") or nil
end

local site, tmpl = nil, nil

-- The routine and its template made this version now, or taken as they are if they are already (a save state made
-- with this fix, or the script started again over fixed code).
local function take(b)
	local s = routine_state(b)
	local t = s and template_of(b)
	local ts = t and template_state(t)
	if not ts then
		return false
	end
	if s ~= "fix" then
		local ok, ra = pcall(eeObj.GetGpr, gpr.ra)
		if not ok or u32(ra % 4294967296) == b + RA_INSIDE then
			return false -- the EE is inside the routine: the next vsync
		end
		for i = 1, #TAIL_FIX do
			local at = b + TAIL_AT + (i - 1) * 4
			if ee(at) ~= TAIL_FIX[i] then
				eeObj.WriteMem32(at, TAIL_FIX[i])
			end
		end
	end
	if ts ~= "fix" then
		-- the tag first made one that sends nothing (NLOOP 0, EOP), last made this version's: a template DMA'd to VU1
		-- while it is written is never half one thing and half the other
		eeObj.WriteMem32(t, 0x00008000)
		for i = 3, #T_FIX do
			eeObj.WriteMem32(t + (i - 1) * 4, T_FIX[i])
		end
		eeObj.WriteMem32(t + 4, T_FIX[2])
		eeObj.WriteMem32(t, T_FIX[1])
	end
	site, tmpl = b, t
	print(string.format("Sonic the Fighters fix: palettes uploaded for DawnStation's module (routine %06x was %s, " ..
		"template %06x was %s)", b, s, t, ts))
	return true
end

-- Every vsync: five reads while Sonic the Fighters is there and fixed, one at the known place otherwise. The search
-- (untested discs) looks at 512 words a vsync (each read costs the EE about 1.4 us) for the routine's MMI word.
local WORDS, LO, HI = 512, 0x00100000, 0x00300000
local scanAt = LO

local function step()
	if site then
		if ee(site + TAIL_AT) == TAIL_FIX[1] and ee(site + 0x100) == TAIL_FIX[46] and ee(tmpl) == T_FIX[1] and
				ee(tmpl + 0xA0) == T_FIX[41] and ee(tmpl + 0xC4) == T_FIX[50] then
			return
		end
		site, tmpl = nil, nil -- gone: another game of the collection, or a save state made without the fix
	end
	if ee(KNOWN + ANCHOR_AT) == ANCHOR and take(KNOWN) or not SEARCH then
		return
	end
	local stop = scanAt + WORDS * 4
	for at = scanAt, stop - 4, 4 do
		if ee(at) == ANCHOR and at - ANCHOR_AT ~= KNOWN and take(at - ANCHOR_AT) then
			return
		end
	end
	scanAt = stop
	if scanAt >= HI then
		scanAt = LO
	end
end

-- [Sonic the Fighters' palettes made by DawnStation (DawnStation)]
emuObj.AddVsyncHook(step)
