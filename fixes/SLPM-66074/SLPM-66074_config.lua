-- Sonic Gems Collection (SLPM-66074, Japan):
-- Sonic Gems Collection's fix (fixes/SLES-53350, where the reasons are), UNTESTED on this disc (2026-11-27):
-- Sonic the Fighters' palette lines, one pixel high (Sony's core draws them wrong), are drawn as one-row sprites,
-- so its characters and stages get their colours. The routine and the template are found by their words, so no
-- SLES-53350 address has to match; if this disc's code differs, nothing is written.
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

-- The rows' writer: (buffer) for 32 pages, 3 channels and 32 rows, PRIM, UV and UV again (row 0x28 bytes: PRIM, UV,
-- XYZF2, UV, XYZF2) from a row table in the scratchpad. Its words in any build ({offset, word}); +0x14 is a jal
-- (checked by kind), +0x5C loads PRIM and +0x78-0x167 is the 8-row loop body, both checked below.
local KNOWN = 0x0018C5C0
local SAME = {
	{0x000, 0x27BDFFE0}, {0x004, 0x24060080}, {0x008, 0xFFBF0010}, {0x00C, 0x7FB00000}, {0x010, 0x0080802D},
	{0x018, 0x0000202D}, {0x01C, 0x3C057000}, {0x020, 0x24030100}, {0x024, 0x34A60800}, {0x028, 0xDCA40000},
	{0x02C, 0x2063FFFF}, {0x030, 0x20A50008}, {0x034, 0x70842588}, {0x038, 0x70042788}, {0x03C, 0x700420FE},
	{0x040, 0x7CC40000}, {0x044, 0x1403FFF8}, {0x048, 0x20C60010}, {0x04C, 0x3C037000}, {0x050, 0x26090050},
	{0x054, 0x34680800}, {0x058, 0x0000602D}, {0x060, 0x25270010}, {0x064, 0x0000582D}, {0x068, 0x24E60030},
	{0x06C, 0x0000502D}, {0x070, 0x0100282D}, {0x074, 0x00000000}, {0x168, 0x15A0FFC3}, {0x16C, 0x24C60140},
	{0x170, 0x256B0001}, {0x174, 0x29640003}, {0x178, 0x1480FFBB}, {0x17C, 0x24E70530}, {0x180, 0x258C0001},
	{0x184, 0x25290FA0}, {0x188, 0x29840020}, {0x18C, 0x1480FFB4}, {0x190, 0x25080080}, {0x194, 0xDFBF0010},
	{0x198, 0x7BB00000}, {0x19C, 0x03E00008}, {0x1A0, 0x27BD0020},
}
local PRIM_AT, PRIM_LINE, PRIM_SPRITE = 0x5C, 0x24030311, 0x24030316 -- addiu v1, zero, 0x311 (or 0x316)
local RA_INSIDE = 0x18 -- ra while the routine runs its loops (after its one call)
local BODY_AT = 0x78
-- The game's loop body: a0 = t3 + a1, then 8 rows of lbu, PRIM, UV, UV (stores off a2), with the loop's counters.
local BODY_OLD = {
	0x01652021, 0x908E0000, 0x254A0008, 0x294D0020, 0x24A50020, 0x000E7138, 0xFCC30000, 0x000E7438, 0xFCCE0008,
	0x35CE03FF, 0xFCCE0018, 0x908E0004, 0x000E7138, 0xFCC30028, 0x000E7438, 0xFCCE0030, 0x35CE03FF, 0xFCCE0040,
	0x908E0008, 0x000E7138, 0xFCC30050, 0x000E7438, 0xFCCE0058, 0x35CE03FF, 0xFCCE0068, 0x908E000C, 0x000E7138,
	0xFCC30078, 0x000E7438, 0xFCCE0080, 0x35CE03FF, 0xFCCE0090, 0x908E0010, 0x000E7138, 0xFCC300A0, 0x000E7438,
	0xFCCE00A8, 0x35CE03FF, 0xFCCE00B8, 0x908E0014, 0x000E7138, 0xFCC300C8, 0x000E7438, 0xFCCE00D0, 0x35CE03FF,
	0xFCCE00E0, 0x908E0018, 0x000E7138, 0xFCC300F0, 0x000E7438, 0xFCCE00F8, 0x35CE03FF, 0xFCCE0108, 0x9084001C,
	0x00042138, 0xFCC30118, 0x00042438, 0xFCC40120, 0x348403FF, 0xFCC40130,
}
-- The fix's body, the same size (nops after it): the rows written by a loop that also writes both corners.
local BODY_NEW = {
	0x01652021, -- addu   a0, t3, a1        (this channel's row numbers, 4 bytes apart)
	0x000A7D38, -- dsll   t7, t2, 20        (y of the group's first row, at XYZF2's y)
	0x3C180010, -- lui    t8, 0x10          (one row)
	0x24190008, -- addiu  t9, zero, 8
	0x00C0102D, -- move   v0, a2
	0x908E0000, -- 1: lbu t6, 0(a0)         (the source row)
	0xFC430000, -- sd     v1, 0(v0)         PRIM (sprite)
	0x000E7538, -- dsll   t6, t6, 20
	0xFC4E0008, -- sd     t6, 8(v0)         UV (0, row)
	0x35CE03FF, -- ori    t6, t6, 0x3ff
	0xFC4E0018, -- sd     t6, 0x18(v0)      UV (63.94, row)
	0xFC4F0010, -- sd     t7, 0x10(v0)      XYZF2 (0, y)
	0x01F8782D, -- daddu  t7, t7, t8
	0x35EE03FE, -- ori    t6, t7, 0x3fe
	0xFC4E0020, -- sd     t6, 0x20(v0)      XYZF2 (63.875, y + 1)
	0x24840004, -- addiu  a0, a0, 4
	0x2739FFFF, -- addiu  t9, t9, -1
	0x1720FFF3, -- bnez   t9, 1b
	0x64420028, -- daddiu v0, v0, 0x28      (delay slot)
	0x254A0008, -- addiu  t2, t2, 8         (the game's loop counters, as before)
	0x294D0020, -- slti   t5, t2, 0x20
	0x24A50020, -- addiu  a1, a1, 0x20
}
for i = #BODY_NEW + 1, #BODY_OLD do
	BODY_NEW[i] = 0
end

-- The template's sender, right after the routine: lui a0, hi; addiu a1, zero, 0x21; addiu a0, a0, lo; jal (to VU1);
-- addiu a2, zero, 0x11. The template (PACKED, PRIM LINE): A+D CLAMP_2, then UV and XYZ2 four times, VU1 filling in
-- the UVs; XYZ2 (7.875, 0) at +0x50 and (7.875, 1) at +0x90 become a row lower for sprites.
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
local TSAME = {
	{0x00, 0x00008001}, {0x08, 0x3E3E3E3E}, {0x0C, 0x00000EEE}, {0x18, 0x00000009}, {0x30, 0x00000000},
	{0x34, 0x00000000}, {0x38, 0x00000005}, {0x54, 0x00000000}, {0x58, 0x00000005}, {0x70, 0x00100000},
	{0x74, 0x00000000}, {0x78, 0x00000005}, {0x94, 0x00000000}, {0x98, 0x00000005},
}
local TFIX = {{0x04, 0xB188C000, 0xB18B4000}, {0x50, 0x0000007E, 0x0010007E}, {0x90, 0x0010007E, 0x0020007E}}

-- "fixed", "other" (as the game has it: to be fixed) or nil (something else).
local function words_state(at, list, fixes)
	for _, s in ipairs(list) do
		if ee(at + s[1]) ~= s[2] then
			return nil
		end
	end
	local old, new = true, true
	for _, f in ipairs(fixes) do
		local v = ee(at + f[1])
		old = old and v == f[2]
		new = new and v == f[3]
	end
	return (new and "fixed") or (old and "other") or nil
end

local function routine_state(b)
	local p = ee(b + PRIM_AT)
	if p ~= PRIM_LINE and p ~= PRIM_SPRITE then
		return nil
	end
	if not words_state(b, SAME, {}) or math.floor(ee(b + 0x14) / 67108864) ~= 3 then
		return nil
	end
	local old, new = p == PRIM_LINE, p == PRIM_SPRITE
	for i = 1, #BODY_OLD do
		local v = ee(b + BODY_AT + (i - 1) * 4)
		old = old and v == BODY_OLD[i]
		new = new and v == BODY_NEW[i]
		if not old and not new then
			return nil
		end
	end
	return (new and "fixed") or "other"
end

local site, tmpl = nil, nil

-- The routine (and its template) fixed now, or taken as they are if fixed already (a save state made with this fix).
local function take(b)
	local s = routine_state(b)
	local t = s and template_of(b)
	local ts = t and words_state(t, TSAME, TFIX)
	if not ts then
		return false
	end
	if s == "other" then
		local ok, ra = pcall(eeObj.GetGpr, gpr.ra)
		if not ok or u32(ra % 4294967296) == b + RA_INSIDE then
			return false -- the EE is inside the routine: the next vsync
		end
		for i = 1, #BODY_NEW do
			local at = b + BODY_AT + (i - 1) * 4
			if ee(at) ~= BODY_NEW[i] then
				eeObj.WriteMem32(at, BODY_NEW[i])
			end
		end
		eeObj.WriteMem32(b + PRIM_AT, PRIM_SPRITE)
	end
	if ts == "other" then
		for _, f in ipairs(TFIX) do
			eeObj.WriteMem32(t + f[1], f[3])
		end
	end
	site, tmpl = b, t
	print(string.format("Sonic the Fighters fix: palette lines drawn as sprites (routine %06x, template %06x%s)", b, t,
		s == "fixed" and ts == "fixed" and ", already fixed" or ""))
	return true
end

-- Every vsync: three reads while Sonic the Fighters is there and fixed, one at the known place otherwise. The search
-- (untested discs) looks at 512 words a vsync (each read costs the EE about 1.4 us) for the routine's PRIM load.
local WORDS, LO, HI = 512, 0x00100000, 0x00300000
local scanAt = LO

local function step()
	if site then
		if ee(site + PRIM_AT) == PRIM_SPRITE and ee(site + BODY_AT + 4) == BODY_NEW[2] and ee(tmpl + 4) == TFIX[1][3] then
			return
		end
		site, tmpl = nil, nil -- gone: another game of the collection, or a save state made without the fix
	end
	if take(KNOWN) or not SEARCH then
		return
	end
	local stop = scanAt + WORDS * 4
	for at = scanAt, stop - 4, 4 do
		local v = ee(at)
		if (v == PRIM_LINE or v == PRIM_SPRITE) and at - PRIM_AT ~= KNOWN and take(at - PRIM_AT) then
			return
		end
	end
	scanAt = stop
	if scanAt >= HI then
		scanAt = LO
	end
end

-- [Sonic the Fighters' palettes drawn as sprites (DawnStation)]
emuObj.AddVsyncHook(step)
