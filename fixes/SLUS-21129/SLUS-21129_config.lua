-- Tenchu: Fatal Shadows (SLUS-21129): DawnStation's fix (2026-11-02, disc loads 2026-11-03).
--
-- Jvn9207's "visual fix" from PSX-Place's "[Research] PS2 emulator configuration on PS4" thread (made on Sony's "adk"
-- emulator build, confirmed there by another player): the same five words of the game's memory, kept at 0.
-- What they are, from the game's code: the game sends its picture through both of the PS2's output circuits and blends
-- them with an alpha, PMODE = alpha << 8 | 0x23 (| 0x2B in some modes), in the two display environments its
-- sceGsSetDefDBuffDc call builds at 0x3F6240 and 0x3F6268 (set at 0x137E90 and 0x1381CC). Its vsync handler (0x1357A0)
-- puts one on circuit 2 and points circuit 1 at the same frame buffer, read from one pixel further right (DISPFB1 DBX 1,
-- DISPLAY1 DX 648 against 636): blended, a slight horizontal softening on a PS2; in Sony's core the blend leaves long
-- trails behind everything that moves (the user's clip, 2026-11-03: in a mission the whole picture smeared). The alpha
-- is the word at 0x47792C (set at 0x138134); 0x477AE8 and 0x477AEC hold it as floats that ease the blend in and out
-- (0x14EFB0). Jvn9207's values are the title's (0x10, 16.0); in a mission it is 0x80 (128.0). The fix keeps the alpha
-- at 0 for any of them, so the picture comes from circuit 2 only.
--
-- The game sets those words while it runs, so they're written again whenever it puts an alpha back (once a vsync), only
-- over the game's own kinds of values, and only once the game's code is in memory (its "ori v1, v1, 0x23" at 0x137E98).

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local okIop, iopObj = pcall(getIOPObject)

emuObj.AddVsyncHook(function()
	if eeObj.ReadMem32(0x00137E98) ~= 0x34630023 then
		return
	end
	for _, at in ipairs({0x003F6240, 0x003F6268}) do
		local pmode = eeObj.ReadMem32(at) & 0xFFFFFFFF
		if (pmode & 0xFFFF0023) == 0x23 and (pmode & 0xFF00) ~= 0 then -- both circuits, blended with ALP
			eeObj.WriteMem32(at, pmode & 0xFF) -- alpha 0
		end
	end
	local alpha = eeObj.ReadMem32(0x0047792C)
	if alpha > 0 and alpha <= 0xFF then
		eeObj.WriteMem32(0x0047792C, 0x00000000)
	end
	for _, at in ipairs({0x00477AE8, 0x00477AEC}) do
		local f = eeObj.ReadMem32(at) & 0xFFFFFFFF
		if f > 0 and f <= 0x437F0000 then -- a float above 0, up to 255.0
			eeObj.WriteMem32(at, 0x00000000)
		end
	end
end)

-- K2SoundDriver, the game's IOP module (in its ELF), reads the game's files for it: a file read at an offset that
-- isn't a multiple of 2048 goes through two 128 KB buffers in the module (module + 0x90F80 and + 0xB0F80): the disc
-- read into the first, the bytes copied into the second, and the second sent to the EE (module + 0x6768: sceSifSetDma,
-- its transfer id dropped) as soon as it's full; then the rest of the first buffer is copied into the second at once.
-- A PS2's DMA reads the buffer far faster than the IOP copies into it; Sony's core moves it later, so each 128 KB the
-- EE gets starts with up to 10 KB of the next 128 KB. A stage file's records (\STAGE\STG00.SMP, offset 0x108, its
-- event block for slot 2 of 0x66A51C, 1.4 MB) came in like that in the user's crash (2026-11-03): its record count was
-- other data (0x3EF00000), and 0x13E310 read records until it ran out of RAM (a bus error that closed the app). The
-- disc read speed doesn't change that, since the copy follows the send without a disc read in between.
local K2_SEND = 0x6768
local K2 = {base = -1, stat = -1, setDma = -1, exports = {}, imports = {}, scan = 0, passes = 0, patched = 0,
	check = 0, wait = 0}
local COUNTERS = 0x000FFFE0 -- "DFC1", the module, sceSifDmaStat, patches written, IOP scans (PS2 RAM, unused here)
-- the send as the game has it, but for the words its relocation changes (checked apart)
local K2_ORIGINAL = {
	[0x00] = 0x27BDFFE8, [0x04] = 0xAFBF0010, [0x14] = 0x00000000, [0x20] = 0x24050001, [0x28] = 0x00000000,
	[0x2C] = 0x1440000A, [0x30] = 0x00000000, [0x40] = 0x00000000, [0x44] = 0x240401F4, [0x4C] = 0x00000000,
	[0x50] = 0x1000FFED, [0x54] = 0x00000000, [0x64] = 0x00000000, [0x68] = 0x24020001, [0x6C] = 0x8FBF0010,
	[0x70] = 0x27BD0018, [0x74] = 0x03E00008, [0x78] = 0x00000000,
}
local iop32 = function(a) return iopObj.ReadMem32(a) & 0xFFFFFFFF end
local jal = function(target) return 0x0C000000 | ((target >> 2) & 0x03FFFFFF) end
local k2Original = function(base)
	for off, word in pairs(K2_ORIGINAL) do
		if iop32(base + K2_SEND + off) ~= word then
			return false
		end
	end
	-- its calls through its own import stubs: CpuSuspendIntr, sceSifSetDma, CpuResumeIntr, DelayThread, CpuResumeIntr
	return iop32(base + 0x6778) == jal(base + 0x14) and iop32(base + 0x678C) == jal(base + 0xF4)
		and iop32(base + 0x67A4) == jal(base + 0x1C) and iop32(base + 0x67B0) == jal(base + 0x1D8)
		and iop32(base + 0x67C8) == jal(base + 0x1C)
end
-- The sceSifDmaStat a patched send calls, or -1 when the send isn't patched.
local k2PatchedStat = function(base)
	local call = iop32(base + 0x67CC)
	if iop32(base + 0x6798) == 0xAFA20014 and iop32(base + 0x67C4) == jal(base + 0x1C) and (call >> 26) == 3
			and iop32(base + 0x67D0) == 0x8FA40014 and iop32(base + 0x67D4) == 0x0441FFFD
			and iop32(base + 0x67E0) == 0x27BD0018 then
		return (call & 0x03FFFFFF) << 2
	end
	return -1
end
-- A "j" instruction's target, or -1.
local jTarget = function(word) return (word >> 26) == 2 and (word & 0x03FFFFFF) << 2 or -1 end
-- sifman's tables in the IOP's memory, by the name "sifman" at +0x0C. Its export table (magic 0x41C00000, function
-- pointers from +0x14): sceSifSetDma is the 7th, sceSifDmaStat the 8th. An import table (magic 0x41E00000, then the
-- stubs, "j <function>" once linked with "li zero, <index>" after it): K2SoundDriver's sits at its +0xD0 (sceSifInit,
-- sceSifSetDChain, sceSifSetDma at +0xF4, sceSifCheckInit); other modules import sceSifDmaStat too. Memory can still
-- hold tables from before the game rebooted the IOP, so sceSifDmaStat is only taken from a table whose sceSifSetDma is
-- the one K2SoundDriver's stub jumps to.
local k2Table = function(at, magic)
	if magic == 0x41C00000 then
		K2.exports[#K2.exports + 1] = at
		return
	end
	local base = at - 0xD0
	if base >= 0 and (k2Original(base) or k2PatchedStat(base) > 0) then
		K2.base, K2.setDma = base, jTarget(iop32(base + 0xF4))
	end
	local stubs = {}
	local stub = at + 0x14
	while stub < 0x1FFFF8 and (iop32(stub + 4) >> 16) == 0x2400 do
		stubs[iop32(stub + 4) & 0xFFFF] = jTarget(iop32(stub))
		stub = stub + 8
	end
	if stubs[7] and stubs[8] then
		K2.imports[#K2.imports + 1] = {stubs[7], stubs[8]}
	end
end
local k2Stat = function()
	if K2.base < 0 or K2.setDma <= 0 then
		return -1
	end
	if k2PatchedStat(K2.base) > 0 then
		return k2PatchedStat(K2.base)
	end
	for _, at in ipairs(K2.exports) do
		if iop32(at + 0x30) == K2.setDma and iop32(at + 0x34) > 0 and iop32(at + 0x34) ~= K2.setDma then
			return iop32(at + 0x34)
		end
	end
	for _, pair in ipairs(K2.imports) do
		if pair[1] == K2.setDma and pair[2] > 0 and pair[2] ~= K2.setDma then
			return pair[2]
		end
	end
	return -1
end
local k2Counters = function()
	eeObj.WriteMem32(COUNTERS, 0x31434644)
	eeObj.WriteMem32(COUNTERS + 4, K2.base)
	eeObj.WriteMem32(COUNTERS + 8, K2.stat)
	eeObj.WriteMem32(COUNTERS + 12, K2.patched)
	eeObj.WriteMem32(COUNTERS + 16, K2.passes)
end

-- [Disc loads wait for their transfers]
-- The send (module + 0x6768) keeps its transfer id (sw v0, 0x14(sp) in the delay slot of its "queued?" branch) and,
-- after CpuResumeIntr, calls sceSifDmaStat until the transfer is done (< 0), then returns (v0 < 0: its callers only
-- test it against 0). The rewritten end fits the old one (0x67C0-0x67E0). Found by looking through the IOP's 2 MB
-- (32 KB a vsync) once the game's code is in memory: 4 looks in a row, then one every 5 s, 20 at most; written only
-- while the game has no file read out (its flags at gp - 0x60CC and gp - 0x60D8), and again if a save state brings
-- the old code back.
emuObj.AddVsyncHook(function()
	if not (okIop and iopObj) or eeObj.ReadMem32(0x00137E98) ~= 0x34630023 then
		return
	end
	if K2.base < 0 or K2.stat < 0 then
		if K2.passes >= 20 then
			return
		end
		if K2.wait > 0 then
			K2.wait = K2.wait - 1
			return
		end
		if K2.scan == 0 then
			K2.base, K2.setDma, K2.exports, K2.imports = -1, -1, {}, {}
		end
		local stop = K2.scan + 0x8000
		for at = K2.scan, stop - 4, 4 do
			local magic = iop32(at)
			if (magic == 0x41E00000 or magic == 0x41C00000) and at < 0x1FFFE0 and iop32(at + 0x0C) == 0x6D666973
					and iop32(at + 0x10) == 0x00006E61 then
				k2Table(at, magic)
			end
		end
		K2.scan = stop
		K2.stat = k2Stat()
		if stop >= 0x200000 then
			K2.scan, K2.passes = 0, K2.passes + 1
			if K2.passes >= 4 then
				K2.wait = 300
			end
			k2Counters()
		end
		if K2.base < 0 or K2.stat < 0 then
			return
		end
	else
		K2.check = K2.check + 1
		if K2.check < 60 then
			return
		end
		K2.check = 0
	end
	local base = K2.base
	if k2PatchedStat(base) == K2.stat then
		return
	end
	if not k2Original(base) then
		K2.base, K2.stat, K2.scan = -1, -1, 0
		return
	end
	if eeObj.ReadMem32(0x004777A4) ~= 0 or eeObj.ReadMem32(0x00477798) ~= 0 then
		return
	end
	local resume, state = iop32(base + 0x67C8), iop32(base + 0x67C4)
	iopObj.WriteMem32(base + 0x6798, 0xAFA20014) -- sw v0, 0x14(sp): the transfer id
	iopObj.WriteMem32(base + 0x67C4, resume) -- jal CpuResumeIntr
	iopObj.WriteMem32(base + 0x67C8, state) -- lw a0, <its state>(at)
	iopObj.WriteMem32(base + 0x67CC, jal(K2.stat)) -- jal sceSifDmaStat
	iopObj.WriteMem32(base + 0x67D0, 0x8FA40014) -- lw a0, 0x14(sp)
	iopObj.WriteMem32(base + 0x67D4, 0x0441FFFD) -- bgez v0, 0x67CC
	iopObj.WriteMem32(base + 0x67D8, 0x8FBF0010) -- lw ra, 0x10(sp)
	iopObj.WriteMem32(base + 0x67DC, 0x03E00008) -- jr ra
	iopObj.WriteMem32(base + 0x67E0, 0x27BD0018) -- addiu sp, sp, 0x18
	K2.patched = K2.patched + 1
	k2Counters()
end)
