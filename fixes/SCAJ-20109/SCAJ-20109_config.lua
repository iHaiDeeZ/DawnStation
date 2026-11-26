-- Ratchet & Clank 3: Up Your Arsenal (SCAJ-20109, Asia): Ratchet & Clank: Up Your Arsenal's fix (fixes/SCUS-97353, and
-- fixes/SCUS-97465 for the reasons), UNTESTED on this disc (2026-11-06). The hook is looked for by its lines, the
-- VU0 routine by psdevwiki's marker and VU0's wait points by their words, so no SCUS-97353 address is used;
-- psdevwiki's scanner still takes the routine's ten clears to be at the same offsets from its marker (as they
-- are in Ratchet & Clank 1, 2, 3 and Deadlocked).

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- [Hook site (DawnStation)]
-- lui v1, 0x1000; ori v1, v1, 0xF000; NOP (the hook: psdevwiki's j 0xFFA00 once written); lw v0, 0(v1);
-- andi v0, v0, 4; bnez v0, +4; nop; lw v0, 0(sp); beqz v0, -6 (0x11F384 on SCUS-97353). Looked for in the game's first
-- MB, 2048 words a vsync (a pass in about 2 s), until found; given up after 20 passes.
local SITE = {0x3C031000, 0x3463F000, -1, 0x8C620000, 0x30420004, 0x14400004, 0x00000000, 0x8FA20000, 0x1040FFFA}
local site, scanAt, passes = nil, 0x00100000, 0

local function site_at(at)
	for k = 1, #SITE do
		local word = eeObj.ReadMem32(at + (k - 1) * 4) & 0xFFFFFFFF
		if SITE[k] >= 0 then
			if word ~= SITE[k] then
				return false
			end
		elseif word ~= 0 and word ~= 0x0803FE80 then
			return false
		end
	end
	return true
end

local function find_site()
	if site and site_at(site) then
		return site
	end
	site = nil
	if passes >= 20 then
		return nil
	end
	local stop = scanAt + 2048 * 4
	for at = scanAt, stop - 4, 4 do
		if (eeObj.ReadMem32(at) & 0xFFFFFFFF) == 0x3C031000 and site_at(at) then
			site = at
			return site
		end
	end
	scanAt = stop
	if scanAt >= 0x00200000 then
		scanAt, passes = 0x00100000, passes + 1
	end
	return nil
end

local patcher = function()
	local at = find_site()
	if not at then
		return
	end
	local back = 0x08000000 | ((at + 12) >> 2) -- j to the lw after the hook (0x08047CE4 on SCUS-97353)
	-- [psdevwiki VU0 fix]
	eeObj.WriteMem32(at + 8, 0x0803FE80)
	eeObj.WriteMem32(0x000FFA00, 0x3C1B7120)
	eeObj.WriteMem32(0x000FFA04, 0x377BCDA8)
	eeObj.WriteMem32(0x000FFA08, 0x3C02000F)
	eeObj.WriteMem32(0x000FFA10, 0xAC44FFF4)
	eeObj.WriteMem32(0x000FFA0C, 0x3442FA00)
	eeObj.WriteMem32(0x000FFA14, 0xAC45FFF0)
	eeObj.WriteMem32(0x000FFA18, 0x8C44FFFC)
	eeObj.WriteMem32(0x000FFA1C, 0x8C840000)
	eeObj.WriteMem32(0x000FFA20, 0x149B0003)
	eeObj.WriteMem32(0x000FFA28, back)
	eeObj.WriteMem32(0x000FFA2C, 0x241B0000)
	eeObj.WriteMem32(0x000FFA34, 0xAC43FFF8)
	eeObj.WriteMem32(0x000FFA38, 0x3C040010)
	eeObj.WriteMem32(0x000FFA3C, 0x24840004)
	eeObj.WriteMem32(0x000FFA40, 0x8C830000)
	eeObj.WriteMem32(0x000FFA44, 0x107B0003)
	eeObj.WriteMem32(0x000FFA4C, 0x1000FFFB)
	eeObj.WriteMem32(0x000FFA54, 0xAC44FFFC)
	eeObj.WriteMem32(0x000FFA64, 0x3C030C03)
	eeObj.WriteMem32(0x000FFA68, 0x3463FE48)
	eeObj.WriteMem32(0x000FFA6C, 0xAC8300BC)
	eeObj.WriteMem32(0x000FFA78, 0xAC8301FC)
	eeObj.WriteMem32(0x000FFA84, 0xAC830354)
	eeObj.WriteMem32(0x000FFA90, 0xAC830494)
	eeObj.WriteMem32(0x000FFA9C, 0xAC8305EC)
	eeObj.WriteMem32(0x000FFAA8, 0xAC83072C)
	eeObj.WriteMem32(0x000FFAAC, 0x3C030C03)
	eeObj.WriteMem32(0x000FFAB0, 0x3463FE4B)
	eeObj.WriteMem32(0x000FFAB4, 0xAC83015C)
	eeObj.WriteMem32(0x000FFAC0, 0xAC8302AC)
	eeObj.WriteMem32(0x000FFACC, 0xAC8303F4)
	eeObj.WriteMem32(0x000FFAD8, 0xAC830544)
	eeObj.WriteMem32(0x000FFC0C, 0x8C44FFF4)
	eeObj.WriteMem32(0x000FFC10, 0x8C45FFF0)
	eeObj.WriteMem32(0x000FFC14, 0x8C43FFF8)
	eeObj.WriteMem32(0x000FFC18, back)
	eeObj.WriteMem32(0x000FF914, 0x03E00008)
	eeObj.WriteMem32(0x000FF918, 0x241F0000)
	eeObj.WriteMem32(0x000FF920, 0x48C00800)
	eeObj.WriteMem32(0x000FF924, 0x1000FFF7)
	eeObj.WriteMem32(0x000FF92C, 0x48C01000)
	eeObj.WriteMem32(0x000FF930, 0x1000FFF4)
	-- [VU0 handshake (DawnStation)]
	-- As in Ratchet & Clank 1 and 2 (fixes/SCUS-97268 says why): the clears jump to DawnStation's stubs at 0xFFD00
	-- (vi1) / 0xFFD40 (vi2), which keep VU0 ahead of the EE as on the PS2, under the VU0 cap (vu0_sync_budget):
	--   cfc2 k1, viN; bne k1, zero, +3 (VU0 already waiting: no catch-up); cfc2.i k1, viN (else let VU0 run
	--   until it sets it); ctc2 zero, viN (the clear); with VU0 stopped at a wait point (the next section) it is
	--   resumed there, VCALLMSR at the address it left in vi12; cfc2.i k1, viN (let VU0 take this batch);
	--   jr ra; addiu ra, zero, 0 (psdevwiki's return, as at 0xFF914)
	eeObj.WriteMem32(0x000FF920, 0x0803FF40) -- j 0xFFD00
	eeObj.WriteMem32(0x000FF924, 0x00000000)
	eeObj.WriteMem32(0x000FF92C, 0x0803FF50) -- j 0xFFD40
	eeObj.WriteMem32(0x000FF930, 0x00000000)
	-- psdevwiki's scanner also puts cfc2.i k1, vi1 on the nop after the routine's VCALLMS 0 (marker + 8)
	eeObj.WriteMem32(0x000FFADC, 0x3C03485B) -- lui v1, 0x485B
	eeObj.WriteMem32(0x000FFAE0, 0x34630801) -- ori v1, v1, 0x0801
	eeObj.WriteMem32(0x000FFAE4, 0xAC830008) -- sw v1, 8(a0)
	local handshake = {
		{0x000FFD00, 0x485B0800, 0x48C00800}, -- vi1: cfc2 k1, vi1; ctc2 zero, vi1
		{0x000FFD40, 0x485B1000, 0x48C01000}, -- vi2
	}
	for i = 1, #handshake do
		local addr, read, clear = handshake[i][1], handshake[i][2], handshake[i][3]
		local code = {
			read,       -- cfc2 k1, viN
			0x17600002, -- bne k1, zero, +2 (set: VU0 isn't behind)
			0x00000000,
			read + 1,   -- cfc2.i k1, viN: behind: let it get to its wait point
			clear,      -- ctc2 zero, viN: the clear
			0x485BE800, -- cfc2 k1, vi29 (VPU-STAT)
			0x337B0001, -- andi k1, k1, 1 (VU0 busy)
			0x17600005, -- bne k1, zero, +5: still running: it sees the clear by itself
			0x485B6000, -- cfc2 k1, vi12: the wait point it stopped at (0: none)
			0x13600003, -- beq k1, zero, +3
			0x48C06000, -- ctc2 zero, vi12
			0x48DBD800, -- ctc2 k1, vi27 (CMSAR0)
			0x4A00D839, -- vcallmsr vi27: resume at the wait's flag check
			read + 1,   -- cfc2.i k1, viN: run it to its next wait point (batch taken, results done)
			0x03E00008, -- jr ra
			0x241F0000, -- addiu ra, zero, 0 (psdevwiki's return, as at 0xFF914)
		}
		for k = 1, #code do
			eeObj.WriteMem32(addr + (k - 1) * 4, code[k])
		end
	end
	-- [VU0 wait points (DawnStation)]
	-- Each of the program's eight wait loops (n: ibeq viN, vi0, exit; nop; b n; nop) starts with
	-- iaddiu vi12, vi0, n-2 and the E bit instead: VU0 ends there rather than spin, and leaves where to resume.
	-- Only words that are still the original are written (the game uploads the program again each time).
	local waits = {
		{30, 0x50010003}, {57, 0x500207CD}, {94, 0x50010003}, {131, 0x500207B9},
		{172, 0x50010003}, {213, 0x500207B1}, {240, 0x50010003}, {267, 0x500207CD},
	}
	for i = 1, #waits do
		local n, check = waits[i][1], waits[i][2]
		local addr = n < 256 and 0x00100090 + n * 8 or 0x00100898 + (n - 256) * 8
		if eeObj.ReadMem32(addr) == check and eeObj.ReadMem32(addr + 4) == 0x000002FF and eeObj.ReadMem32(addr + 16) == 0x400007FD then
			eeObj.WriteMem32(addr, 0x100C0000 + n - 2) -- iaddiu vi12, vi0, n-2
			eeObj.WriteMem32(addr + 4, 0x400002FF)     -- nop, E bit
		end
	end
end

emuObj.AddVsyncHook(patcher)
