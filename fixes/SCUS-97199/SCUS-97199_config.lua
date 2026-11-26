-- Ratchet & Clank (SCUS-97199): DawnStation's fix (v00.85), Ratchet & Clank 2's (fixes/SCUS-97268) on this game.
-- The game froze about 20 s in (the in-game menu's freeze check, 2026-10-31): from then on the EE's thread
-- ran nothing but VU0's program (profiler: jit:_prog_vu0_exec 100%), with psdevwiki's settings and Lua on.
-- The same handshake as Ratchet & Clank 2: the game hands work to VU0, whose program takes each batch the
-- EE leaves in vf1-vf8, sets vi1 / vi2 and spins until the EE clears it; Sony's core runs VU0 on the EE's
-- thread, and where the EE needs VU0 idle it runs the program without limit, so the whole core stops.
-- R&C 1 has the same routine (psdevwiki's marker 0x7120CDA8, at 0x1EE978 in the user's freeze, VCALLMS 0
-- at marker + 4, its ten vi1 / vi2 clears at the same offsets) and the same VU0 program at the same
-- addresses (uploaded from 0x100090 and 0x100898; its eight wait loops at 0x100180 ... 0x1008F0 with the
-- same check words). psdevwiki's R&C 1 Lua differs from R&C 2's only in its hook (0x118CAC) and return
-- (j 0x118CB0). So: psdevwiki's scanner with those two, DawnStation's handshake stubs and wait points as in
-- R&C 2, the VU0 cap (vu0_sync_budget) and the CLI additions (SCUS-97199_cli.conf). R&C 2's frame counter
-- isn't here (its addresses are R&C 2's). See fixes/SCUS-97268 for how each part works.

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

local patcher = function()
	-- [psdevwiki VU0 fix]
	eeObj.WriteMem32(0x00118CAC, 0x0803FE80)
	eeObj.WriteMem32(0x000FFA00, 0x3C1B7120)
	eeObj.WriteMem32(0x000FFA04, 0x377BCDA8)
	eeObj.WriteMem32(0x000FFA08, 0x3C02000F)
	eeObj.WriteMem32(0x000FFA10, 0xAC44FFF4)
	eeObj.WriteMem32(0x000FFA0C, 0x3442FA00)
	eeObj.WriteMem32(0x000FFA14, 0xAC45FFF0)
	eeObj.WriteMem32(0x000FFA18, 0x8C44FFFC)
	eeObj.WriteMem32(0x000FFA1C, 0x8C840000)
	eeObj.WriteMem32(0x000FFA20, 0x149B0003)
	eeObj.WriteMem32(0x000FFA28, 0x0804632C)
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
	eeObj.WriteMem32(0x000FFC18, 0x0804632C)
	eeObj.WriteMem32(0x000FF914, 0x03E00008)
	eeObj.WriteMem32(0x000FF918, 0x241F0000)
	eeObj.WriteMem32(0x000FF920, 0x48C00800)
	eeObj.WriteMem32(0x000FF924, 0x1000FFF7)
	eeObj.WriteMem32(0x000FF92C, 0x48C01000)
	eeObj.WriteMem32(0x000FF930, 0x1000FFF4)
	-- [VU0 handshake (DawnStation)]
	-- 2026-10-22: the clears jump to DawnStation's stubs at 0xFFD00 (vi1) / 0xFFD40 (vi2), which
	-- make Sony's core keep VU0 ahead of the EE, as on the PS2. VU0's program here takes each batch
	-- the EE leaves in vf1-vf8, sets vi1 / vi2 and waits until the EE clears it; in the core VU0 runs
	-- behind, so a clear could come before VU0's set and get lost (VU0 then waits forever: black
	-- screen with vi1 = vi2 = 1), and the EE could overwrite a batch VU0 hadn't taken yet. Each stub:
	--   cfc2 k1, viN; bne k1, zero, +3 (VU0 already waiting: no catch-up); cfc2.i k1, viN (else let
	--   VU0 run until it sets it); ctc2 zero, viN (the clear); cfc2.i k1, viN (let VU0 take this
	--   batch); jr ra; addiu ra, zero, 0 (psdevwiki's return, as at 0xFF914)
	-- The interlocked reads run VU0 for up to vu0_sync_budget cycles (DawnStation v00.33's cap; Sony's
	-- core would run it without limit and deadlock). k1 is free in game code (the PS2 kernel's).
	-- Until v00.34 the stubs ended at psdevwiki's AdvanceClock hook (0xFF904): 395 cycles of the
	-- game's CPU time on every clear, which psdevwiki's notes call "the fix that causes the
	-- slowdowns" (60 fps, but the game felt slow). The catch-up above does what it was for.
	-- v00.35: with the next section, VU0's program ends at each wait point (the same 512-cycle runs
	-- spent most of their time in its wait loops: at 60 fps without the AdvanceClock hook the
	-- emulator ran at 30-42). The stubs now resume it there: VCALLMSR at the address it left in vi12
	-- (the wait's flag check), then an interlocked read runs it to its next wait point. Without the
	-- next section (or if VU0 is still running) vi12 stays 0 and the stubs work as before.
	eeObj.WriteMem32(0x000FF920, 0x0803FF40) -- j 0xFFD00
	eeObj.WriteMem32(0x000FF924, 0x00000000)
	eeObj.WriteMem32(0x000FF92C, 0x0803FF50) -- j 0xFFD40
	eeObj.WriteMem32(0x000FF930, 0x00000000)
	-- psdevwiki's scanner also puts cfc2.i k1, vi1 on the nop after the routine's VCALLMS 0 (marker + 8),
	-- so VU0 takes the first batch before the EE loads the second into vf1-vf8 (the core starts VU0
	-- lazily, on the PS2 it starts at once)
	eeObj.WriteMem32(0x000FFADC, 0x3C03485B) -- lui v1, 0x485B
	eeObj.WriteMem32(0x000FFAE0, 0x34630801) -- ori v1, v1, 0x0801
	eeObj.WriteMem32(0x000FFAE4, 0xAC830008) -- sw v1, 8(a0)
	local handshake = {
		{0x000FFD00, 0x485B0800, 0x48C00800}, -- vi1: cfc2 k1, vi1; ctc2 zero, vi1
		{0x000FFD40, 0x485B1000, 0x48C01000}, -- vi2
	}
	for i = 1, #handshake do
		local at, read, clear = handshake[i][1], handshake[i][2], handshake[i][3]
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
			eeObj.WriteMem32(at + (k - 1) * 4, code[k])
		end
	end
	-- [VU0 wait points (DawnStation)]
	-- v00.35: the handshake's VU0 program (uploaded by VIF0 from 0x100090, 256 instructions, and
	-- 0x100898, 72 at VU0 instruction 256) has eight wait loops: n: ibeq viN, vi0, exit; nop;
	-- b n; nop, after a first check at n-2. Each loop's first instruction becomes
	-- iaddiu vi12, vi0, n-2 with the E bit: VU0 ends there instead of spinning, and leaves where to
	-- resume (the first check, which redoes the ACC sum it starts). Only words that are still the
	-- original are written (the game uploads this program again every time it uses it).
	local waits = {
		{30, 0x50010003}, {57, 0x500207CD}, {94, 0x50010003}, {131, 0x500207B9},
		{172, 0x50010003}, {213, 0x500207B1}, {240, 0x50010003}, {267, 0x500207CD},
	}
	for i = 1, #waits do
		local n, check = waits[i][1], waits[i][2]
		local at = n < 256 and 0x00100090 + n * 8 or 0x00100898 + (n - 256) * 8
		if eeObj.ReadMem32(at) == check and eeObj.ReadMem32(at + 4) == 0x000002FF and eeObj.ReadMem32(at + 16) == 0x400007FD then
			eeObj.WriteMem32(at, 0x100C0000 + n - 2) -- iaddiu vi12, vi0, n-2
			eeObj.WriteMem32(at + 4, 0x400002FF)     -- nop, E bit
		end
	end
end

emuObj.AddVsyncHook(patcher)
