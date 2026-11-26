-- Kaze no Klonoa 2 trial (SLPM-60138, Japan):
-- Klonoa 2's fix (fixes/SLUS-20151, where the reasons are), UNTESTED on this disc (2026-11-27): newlib's sinf and cosf
-- answer 0 for a division by 0, as on a PS2, so items that hang still (the winged green spheres) stay where the stage
-- puts them. Both functions are looked for by their instructions, so no SLUS-20151 address has to match; if this
-- disc's code differs, nothing is written.
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

local function hi16(v)
	return math.floor(v / 65536)
end

local function hi6(v)
	return math.floor(v / 67108864)
end

-- newlib's cosf and sinf (0x306230 and 0x306338 here) differ only in the kernels they call. From +0x40:
-- lui v0, 0x7f7f; ori v0, v0, 0xffff; slt v0, v0, a0 (|x| above 0x7F7FFFFF: a NaN or an infinity); beqz v0, +3;
-- nop; b <return>; sub.s $f0, $f12, $f12 (x - x); jal __ieee754_rem_pio2f; move a0, sp.
-- The words both have in any build ({offset, word}); the calls and the branches are checked by kind only:
local SAME = {
	{0x00, 0x44026000}, {0x04, 0x27BDFFE0}, {0x08, 0x0040202D}, {0x0C, 0x3C037FFF}, {0x10, 0x3463FFFF},
	{0x14, 0x3C023F49}, {0x18, 0x00832024}, {0x1C, 0x34420FD8}, {0x20, 0x0044102A}, {0x24, 0x14400006},
	{0x28, 0xFFBF0010}, {0x2C, 0x44806800}, {0x3C, 0xDFBF0010}, {0x40, 0x3C027F7F}, {0x50, 0x00000000},
	{0x60, 0x03A0202D},
}
local ANCHOR = 0x14 -- lui v0, 0x3f49 (pi / 4): the search's first test
local KNOWN = {0x00306230, 0x00306338} -- SLUS-20151's cosf and sinf; this disc's are looked for by their lines

-- The five words from +0x44 as the fix wants them, and the other forms they may have: as the game has them, or as
-- the first version of this fix (2026-11-26, a wrong reading) left them in a save state made with it. The fix:
-- ori v0, v0, 0xfffe (the branch now from 0x7F7FFFFF up) and, in the branch's delay slot, mtc1 zero, $f0 (returns 0).
-- The branch at +0x54 goes to the function's return, 8 instructions before the one at +0x38 does.
local function wanted(at)
	local back = 0x10000000 + (ee(at + 0x38) % 65536) - 8
	return {
		{0x44, 0x3442FFFE, {0x3442FFFF}},
		{0x48, 0x0044102A, {0x0044182A}},
		{0x4C, 0x10400003, {0x10600003}},
		{0x54, back, {0x44826000}},
		{0x58, 0x44800000, {0x460C6001, 0x00000000}},
	}
end

-- "fixed", "other" (as the game has it, or the first version: to be fixed) or nil (something else).
local function state_at(at)
	for _, s in ipairs(SAME) do
		if ee(at + s[1]) ~= s[2] then
			return nil
		end
	end
	if hi6(ee(at + 0x30)) ~= 3 or hi16(ee(at + 0x38)) ~= 0x1000 or hi6(ee(at + 0x5C)) ~= 3 then
		return nil
	end
	local fixed = true
	for _, p in ipairs(wanted(at)) do
		local v = ee(at + p[1])
		if v ~= p[2] then
			fixed = false
			local known = false
			for _, o in ipairs(p[3]) do
				if v == o then
					known = true
				end
			end
			if not known then
				return nil
			end
		end
	end
	if fixed then
		return "fixed"
	end
	return "other"
end

-- The place fixed now, or taken as it is if it is fixed already (a save state made with this fix, or the script
-- started again over fixed code).
local function take(at)
	local s = state_at(at)
	if s == "other" then
		for _, p in ipairs(wanted(at)) do
			if ee(at + p[1]) ~= p[2] then
				eeObj.WriteMem32(at + p[1], p[2])
			end
		end
		return true
	end
	return s == "fixed"
end

-- The search while a place is missing: 512 words a vsync (each read costs the EE about 1.4 us), four passes over the
-- game's code at most (it is there from the start, after the PS2 logo); the known places first.
local WORDS, LO, HI, PASSES = 512, 0x00100000, 0x00400000, 4
local sites = {}
local scanAt, left = nil, nil

local function have(at)
	for _, s in ipairs(sites) do
		if s == at then
			return true
		end
	end
	return false
end

local function step()
	local k = 1
	while k <= #sites do
		if ee(sites[k] + 0x58) == 0x44800000 then
			k = k + 1
		else
			table.remove(sites, k) -- gone (a save state made without the fix): looked for again
			left = nil
		end
	end
	if #sites == 2 then
		return
	end
	for _, at in ipairs(KNOWN) do
		if not have(at) and take(at) then
			sites[#sites + 1] = at
		end
	end
	if #sites == 2 then
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
		if ee(at) == 0x3C023F49 then
			local start = at - ANCHOR
			if start >= LO and not have(start) and take(start) then
				sites[#sites + 1] = start
				if #sites == 2 then
					return
				end
			end
		end
	end
	scanAt = stop
	if scanAt >= HI then
		scanAt, left = LO, left - 1
	end
end

-- [Division by 0 as on a PS2 in sinf and cosf (DawnStation)]
-- The fix above, at every vsync (two reads once both places are found).
emuObj.AddVsyncHook(step)
