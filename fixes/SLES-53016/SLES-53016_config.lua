-- Tenchu: Fatal Shadows (SLES-53016, Europe): DawnStation's fix (2026-11-02, disc loads 2026-11-03).
--
-- Jvn9207's "visual fix" with the PAL disc's addresses, from the same PSX-Place post as the US one (fixes/SLUS-21129, which
-- explains it: it keeps the alpha of the game's blend of the PS2's two output circuits at 0; in Sony's core that blend
-- leaves long trails in missions). DawnStation doesn't have the PAL disc's code to check against, so each word is only
-- written over the values the game puts there, once a vsync: PMODE 0x1023 (title) or 0x8023 (missions), | 0x08 in the
-- game's other mode; the alpha 0x10 or 0x80; its float copies 16.0 or 128.0 (the US disc's values, 2026-11-03).

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local okIop, iopObj = pcall(getIOPObject)
local PMODES = {[0x00001023] = true, [0x0000102B] = true, [0x00008023] = true, [0x0000802B] = true}
local seen = false -- the game's values have been there once (its code runs)

emuObj.AddVsyncHook(function()
	for _, at in ipairs({0x003F6B40, 0x003F6B68}) do
		local pmode = eeObj.ReadMem32(at) & 0xFFFFFFFF
		if PMODES[pmode] then
			eeObj.WriteMem32(at, pmode & 0xFF) -- alpha 0
			seen = true
		end
	end
	local alpha = eeObj.ReadMem32(0x0047722C)
	if alpha == 0x00000010 or alpha == 0x00000080 then
		eeObj.WriteMem32(0x0047722C, 0x00000000)
	end
	for _, at in ipairs({0x004773E8, 0x004773EC}) do
		local f = eeObj.ReadMem32(at)
		if f == 0x41800000 or f == 0x43000000 then -- 16.0, 128.0
			eeObj.WriteMem32(at, 0x00000000)
		end
	end
end)

-- The US disc's crash after a mission is picked (fixes/SLUS-21129 explains it): the game's IOP module K2SoundDriver
-- sends each 128 KB of a file read to the EE and copies the next bytes into the same buffer before the DMA has read
-- it, so the stage data comes in wrong. The PAL disc's module is taken to be the same: this looks for it the same way
-- and patches it only if its send (module + 0x6768) is exactly the US one. Untested (no PAL disc): there are no PAL
-- addresses for the game's "file read out" flags, so the patch is written as soon as the module is found.
local K2_SEND = 0x6768
local K2 = {base = -1, stat = -1, setDma = -1, exports = {}, imports = {}, scan = 0, passes = 0, patched = 0,
	check = 0, wait = 0}
local COUNTERS = 0x000FFFE0 -- "DFC1", the module, sceSifDmaStat, patches written, IOP scans (PS2 RAM, unused here)
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
	return iop32(base + 0x6778) == jal(base + 0x14) and iop32(base + 0x678C) == jal(base + 0xF4)
		and iop32(base + 0x67A4) == jal(base + 0x1C) and iop32(base + 0x67B0) == jal(base + 0x1D8)
		and iop32(base + 0x67C8) == jal(base + 0x1C)
end
local k2PatchedStat = function(base)
	local call = iop32(base + 0x67CC)
	if iop32(base + 0x6798) == 0xAFA20014 and iop32(base + 0x67C4) == jal(base + 0x1C) and (call >> 26) == 3
			and iop32(base + 0x67D0) == 0x8FA40014 and iop32(base + 0x67D4) == 0x0441FFFD
			and iop32(base + 0x67E0) == 0x27BD0018 then
		return (call & 0x03FFFFFF) << 2
	end
	return -1
end
local jTarget = function(word) return (word >> 26) == 2 and (word & 0x03FFFFFF) << 2 or -1 end
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
-- As fixes/SLUS-21129's section of that name: the send keeps its transfer id and calls sceSifDmaStat until it is done.
-- Looked for once the game's display values have shown up: 4 looks in a row, then one every 5 s, 20 at most.
emuObj.AddVsyncHook(function()
	if not (okIop and iopObj) or not seen then
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
