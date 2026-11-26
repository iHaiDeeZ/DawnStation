-- Harry Potter og Mysteriekammeret (Norway) [SLES-51215]: DawnStation's fix, the European English disc's (fixes/SLES-51192, tested there on
-- the older core, core1; untested here). Its patches are found by their lines, so they go in only where this
-- disc has the same code. The addresses below are the English disc's.
-- The game sends a frame's display lists to VIF1 in two parts: the frame itself (the main thread, state 1), and a queue
-- (0x544178 here: nodes {buffer, next}) that a timer 0 callback (0x1F6E18 here) sends a node at a time (state 3). The
-- VIF1 DMA's completion callback (0x1F59E0 here) moves it on: after the frame, state 2 and timer 0 armed once (its
-- COMP the time left, as little as 1 tick; COUNT 0, MODE 0xFC2: bus/256, reset at COMP, compare interrupt); after a
-- queued node, the frame waiting in 0x544188 sent (state 1) or idle (state 0). The state is at 0x54416C here.
-- The root of it: timer 0 is used once per arming. The timer library's interrupt handler (0x1F6FA0 here) leaves
-- T0_MODE alone after a callback whose node says so (flags bit 1, as the queue's has), so EQUF stays set: on a PS2
-- that raises no more interrupts until the next arming, but core2 raises one at every compare match, every tick with
-- COMP 1: 575,000 handler calls a second measured (the Lab, 2026-11-07), the EE drowned in them (the intros and the
-- loading screens crawled) and the queue's callback called with nothing to send.
-- What that did:
-- 1. A crash 10-15 s in ("Unhandled PageFault" at 0xFF592D78 or 0xFF592D7C): timer 0's callback sends the head and makes
--    head->next the head without looking whether there is a head. With the queue empty, "next" is read from address 4,
--    where the emulator's PS2 kernel has its TLB refill code: 0xFF592D78 (sd t9, 0x2d78(k0)) became the head, and the
--    next append or timer 0 call followed it (the crash in the append's walk at 0x1FC580, in the timer handler, in
--    memset: the same word each time).
-- 2. A freeze: the callback sends through 0x203260 with "wait until VIF1's channel is free", inside timer 0's interrupt.
--    With instant VIF1 transfers the transfer before has already run to a VIFcode's interrupt bit, where VIF1 waits for
--    the game's VIF1 interrupt handler, which can't come while timer 0's handler runs (the emulator's kernel serves the
--    highest pending cause first: timer 0 (9) before VIF1 (5)). The EE stayed in the wait at 0x2032A8.
-- 3. A loading screen that went on for many minutes: the storm, the loading thread getting little of the EE.
-- 4. A cutscene whose sound played and whose picture stood still: with the queue empty in state 2, nothing moved the
--    state on (fix 1 alone sent nothing), so the frame waiting in 0x544188 was never sent and the main thread waited for
--    it at 0x1FCC98 for good.
-- 5. Crashes on the first level's loading screen at a different place each time (a read at 0x8F5A2D44, a write at
--    0xCA9863B1): the storm. One of them read a NULL structure's field at 0x18, the kernel's TLB refill code again
--    (0x8F5A2D40, lw k0, 0x2d40(k0)).
-- Not a fault: the game's clock is timer 1 at 100 ticks a second (0x19BC40 here sets it from the rate in 0x5C82F8, 100:
-- bus/256, COMP 5760), which core2 delivers at 100 (measured 100.0). A Lab version of this fix (2026-11-07) took it for
-- the bus clock (25,600 a second) and made the clock count that fast: the intro movie's picture stopped while its
-- sound went on, the first level's loader crashed (its finish task clearing the loader at 0x5542C0 mid-load), and on
-- core1 the cutscenes' voices went.
-- The fixes: the timer library's handler stops the timer it serves and clears its flags before anything else
-- (T_MODE 0xC00, as Kozarovv's Prisoner of Azkaban patch does): one interrupt per arming, as on a PS2; the handler
-- itself starts it again for the nodes that ask (MODE 0xFC2), the game's arming for the rest. Timer 0's callback, with
-- the queue empty in state 2, does what a finished queued node does (state 3, then the completion callback itself: the
-- waiting frame sent, or idle); with the queue empty otherwise it does nothing; with VIF1 busy it arms timer 0 again
-- (COMP 0x7F, the node's own period, 222 us) and leaves the head for then, instead of waiting; else it goes on as
-- before; it returns 1 as it always does. The game's async file read sends a read that would land below the game
-- (where the kernel is) to a spare buffer instead, counted at 0xFFB00 (on core1 it never has). All three are found by
-- their lines (the addresses taken from them), so the same Lua serves every disc of the game. The stubs sit at
-- 0xFFC00, 0xFFD00 and 0xFFF40, free below the game's code. And the TLB refill vector (0x0-0x7F) is cleared, so that a
-- NULL structure's fields read 0 (a
-- NULL the game's checks catch) instead of the kernel's instructions: core2 never takes a TLB refill exception (an
-- unmapped access is a bus error that ends the app), so that code never runs; the other vectors (0x80, 0x100, 0x180,
-- 0x200) stay.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- Lab only: true counts the timer library's interrupts at 0xFFF20 + 4 * timer (DawnStation Lab, tools/dawnlab.py peek)
local LAB_COUNT_TIMER_IRQS = false

local function word(at)
	return eeObj.ReadMem32(at) & 0xFFFFFFFF
end

local function low(at)
	return word(at) & 0xFFFF
end

local function write_all(at, words)
	for k = 1, #words do
		eeObj.WriteMem32(at + (k - 1) * 4, words[k])
	end
end

local F, H16, JAL = 0xFFFFFFFF, 0xFFFF0000, 0xFC000000

-- [Timer 0 queue (DawnStation)]
-- The callback (26 lines: addiu sp, -0x20; lui a3, hi; ...; mfc0 a2, Count; lui s0, qhi; ...; lw v1, qlo(s0); ...;
-- jal send; ...; lui a2, shi; ...; sw a0, slo(a2); ...; jr ra) and the start of the function after it, which adds the
-- VIF1 completion callback (lui a1, chi; sq ra; addiu a1, clo; li a0, 1; jal add_dma_callback).
local QUEUE = {
	lines = {0x27BDFFE0, 0x3C070000, 0x7FBF0010, 0x7FB00000, 0x40064800, 0x3C100000, 0x3C040FFF, 0x8E030000,
		0x3484FFFF, 0x3C050002, 0xACE60000, 0x8C620000, 0x34A50040, 0x0C000000, 0x00442024, 0x8E050000,
		0x3C060000, 0x24040003, 0x7BBF0010, 0x8CA30004, 0x24020001, 0xACC40000, 0xAE030000, 0x7BB00000,
		0x03E00008, 0x27BD0020, 0x27BDFFF0, 0x3C050000, 0x7FBF0000, 0x24A50000, 0x24040001, 0x0C000000},
	mask = {F, H16, F, F, F, H16, F, H16, F, F, H16, F, F, JAL, F, H16, H16, F, F, F, F, H16, H16, F, F, F, F, H16, F,
		H16, F, JAL},
	known = 0x001F6E18, -- SLES-51192
	anchor = 5,          -- mfc0 a2, Count: the rare line
}

function QUEUE.install(at)
	local qhi, qlo = low(at + 0x14), low(at + 0x1C)
	local shi, slo = low(at + 0x40), low(at + 0x54)
	local clo = low(at + 0x74)
	local done = (low(at + 0x6C) << 16) + (clo >= 0x8000 and clo - 0x10000 or clo) -- the VIF1 completion callback
	write_all(0x000FFD00, {
		0x3C010000 | qhi,        -- lui   at, qhi
		0x8C210000 | qlo,        -- lw    at, qlo(at): the queue's head
		0x1420000C,              -- bnez  at, head
		0x00000000,              -- nop
		0x3C010000 | shi,        -- lui   at, shi: the queue is empty
		0x8C280000 | slo,        -- lw    t0, slo(at): the state
		0x24090002,              -- li    t1, 2
		0x15090010,              -- bne   t0, t1, out: not waiting on the queue, nothing to do
		0x3C0A1001,              -- lui   t2, 0x1001 (delay slot)
		0x8D4A9000,              -- lw    t2, -0x7000(t2): D1_CHCR
		0x314A0100,              -- andi  t2, t2, 0x100: STR
		0x1540000E,              -- bnez  t2, again: VIF1 busy
		0x24090003,              -- li    t1, 3 (delay slot)
		0x08000000 | ((done >> 2) & 0x3FFFFFF), -- j the completion callback: as if a queued node had finished
		0xAC290000 | slo,        -- sw    t1, slo(at) (delay slot): state 3
		0x3C011001,              -- head: lui at, 0x1001
		0x8C219000,              -- lw    at, -0x7000(at): D1_CHCR
		0x30210100,              -- andi  at, at, 0x100: STR
		0x14200007,              -- bnez  at, again: VIF1 busy, the head waits
		0x00000000,              -- nop
		word(at),                -- addiu sp, sp, -0x20
		word(at + 4),            -- lui   a3, hi
		0x08000000 | ((at + 8) >> 2), -- j the callback's third line
		0x00000000,              -- nop
		0x03E00008,              -- out: jr ra
		0x24020001,              -- li    v0, 1 (delay slot), as the callback returns
		0x3C011000,              -- again: lui at, 0x1000
		0xAC200000,              -- sw    zero, 0(at): T0_COUNT
		0x2408007F,              -- li    t0, 0x7f
		0xAC280020,              -- sw    t0, 0x20(at): T0_COMP, 222 us
		0x24080FC2,              -- li    t0, 0xfc2
		0xAC280010,              -- sw    t0, 0x10(at): T0_MODE, as the game arms it
		0x03E00008,              -- jr    ra
		0x24020001,              -- li    v0, 1 (delay slot)
	})
	eeObj.WriteMem32(at + 4, 0x00000000)                   -- the jump's delay slot
	eeObj.WriteMem32(at, 0x08000000 | (0x000FFD00 >> 2))  -- j 0xFFD00
end

-- [Timer interrupts one per arming (DawnStation)]
-- The timer library's INTC handler (a0 = the cause, 9-12 for timers 0-3): its first 32 lines (sq of the s registers,
-- addiu s3, a0, -9; jal di; the callback lists' address 0x544210 here; the first node's fields), the di's address and
-- the lists' left out.
local TIMER = {
	lines = {0x27BDFF70, 0x7FB50050, 0x7FB30030, 0x00C0A82D, 0x7FB70070, 0x0080982D, 0x7FB40040, 0x2673FFF7,
		0x7FB10010, 0x0000A02D, 0x7FB00000, 0x3C11FFFF, 0x7FBF0080, 0x3631FFFF, 0x7FB60060, 0x0C000000,
		0x7FB20020, 0x3C020000, 0x00131880, 0x0040B82D, 0x24420000, 0x00621821, 0x8C700000, 0x1200001C,
		0x00000000, 0x3C160001, 0x8E020014, 0x00000000, 0x8E040018, 0x00563021, 0x8E120008, 0x00C4102B},
	mask = {F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, JAL, F, H16, F, F, H16, F, F, F, F, F, F, F, F, F, F, F},
	known = 0x001F6FA0, -- SLES-51192
	anchor = 8,          -- addiu s3, s3, -9
}

function TIMER.install(at)
	local stub = {
		0x2489FFF7,              -- addiu t1, a0, -9: the timer
		0x00094AC0,              -- sll   t1, t1, 11: its registers, 0x800 apart
		0x3C011000,              -- lui   at, 0x1000
		0x00290821,              -- addu  at, at, t1
		0x24080C00,              -- li    t0, 0xc00
		0xAC280010,              -- sw    t0, 0x10(at): T_MODE 0xC00, stopped, EQUF and OVFF cleared
	}
	if LAB_COUNT_TIMER_IRQS then
		for a = 0x000FFF20, 0x000FFF2C, 4 do
			eeObj.WriteMem32(a, 0)
		end
		for _, w in ipairs({
			0x2489FFF7,          -- addiu t1, a0, -9
			0x00094880,          -- sll   t1, t1, 2
			0x3C010010,          -- lui   at, 0x10
			0x00290821,          -- addu  at, at, t1
			0x8C28FF20,          -- lw    t0, -0xe0(at): the timer's count at 0xFFF20 + 4 * timer
			0x25080001,          -- addiu t0, t0, 1
			0xAC28FF20,          -- sw    t0, -0xe0(at)
		}) do
			stub[#stub + 1] = w
		end
	end
	stub[#stub + 1] = word(at)                          -- addiu sp, sp, -0x90
	stub[#stub + 1] = 0x08000000 | ((at + 8) >> 2)      -- j the handler's third line
	stub[#stub + 1] = word(at + 4)                      -- sq s5, 0x50(sp) (delay slot)
	write_all(0x000FFF40, stub)
	eeObj.WriteMem32(at + 4, 0x00000000)                  -- the jump's delay slot
	eeObj.WriteMem32(at, 0x08000000 | (0x000FFF40 >> 2)) -- j 0xFFF40
end

-- [Reads kept out of the kernel (DawnStation)]
-- The game's async file read (0x1979A0 here: a0 the file, a1 the position, a2 where to, a3 the size; t0 and t1 also
-- arguments): its first 24 lines (the s registers saved, a request taken with jal, its fields filled), the jal's
-- target left out. A read that would land below the game (where the PS2's kernel is) goes to a spare buffer at 0xA0000
-- (256 KB at most) instead, counted at 0xFFB00 with the last one's caller, file, position, place and size.
local READS = {
	lines = {0x27BDFF80, 0x7FB60060, 0x7FB50050, 0x00C0B02D, 0x7FB40040, 0x00A0A82D, 0x7FB30030, 0x0080A02D,
		0x7FB10010, 0x00E0982D, 0x7FB00000, 0x0100882D, 0x7FB20020, 0x7FBF0070, 0x0C000000, 0x0120802D,
		0x0040902D, 0x3C03FF0F, 0x8E420000, 0x3463FFFF, 0x3C040040, 0xAE500014, 0x00431024, 0xAE510010},
	mask = {F, F, F, F, F, F, F, F, F, F, F, F, F, F, JAL, F, F, F, F, F, F, F, F, F},
	known = 0x001979A0, -- SLES-51192
	anchor = 18,         -- lui v1, 0xff0f
}

function READS.install(at)
	for a = 0x000FFB00, 0x000FFB14, 4 do
		eeObj.WriteMem32(a, 0)
	end
	write_all(0x000FFC00, {
		0x3C010010,              -- lui   at, 0x10
		0x00C1082B,              -- sltu  at, a2, at: below the game?
		0x1020000F,              -- beqz  at, go
		0x00000000,              -- nop
		0x3C0A0010,              -- lui   t2, 0x10
		0x8D4BFB00,              -- lw    t3, -0x500(t2): the count
		0x256B0001,              -- addiu t3, t3, 1
		0xAD4BFB00,              -- sw    t3, -0x500(t2)
		0xAD5FFB04,              -- sw    ra, -0x4fc(t2): the caller
		0xAD44FB08,              -- sw    a0, -0x4f8(t2): the file
		0xAD45FB0C,              -- sw    a1, -0x4f4(t2): the position
		0xAD46FB10,              -- sw    a2, -0x4f0(t2): where it was going
		0xAD47FB14,              -- sw    a3, -0x4ec(t2): the size
		0x3C06000A,              -- lui   a2, 0xa: the spare buffer, 0xA0000
		0x3C0B0004,              -- lui   t3, 4
		0x0167502B,              -- sltu  t2, t3, a3
		0x016A380B,              -- movn  a3, t3, t2: 256 KB at most
		0x00000000,              -- nop
		word(at),                -- go: addiu sp, sp, -0x80
		0x08000000 | ((at + 8) >> 2), -- j the function's third line
		word(at + 4),            -- sq    s6, 0x60(sp) (delay slot)
	})
	eeObj.WriteMem32(at + 4, 0x00000000)                  -- the jump's delay slot
	eeObj.WriteMem32(at, 0x08000000 | (0x000FFC00 >> 2)) -- j 0xFFC00
end

local function site_at(site, at)
	for k = 1, #site.lines do
		if (word(at + (k - 1) * 4) & site.mask[k]) ~= site.lines[k] then
			return false
		end
	end
	return true
end

local SITES = {QUEUE, TIMER, READS}
local scanAt = 0x00100000

-- [NULL reads read 0 (DawnStation)]
-- Sony's kernel for the emulator, by its TLB refill vector's first words (lui k0, 0x8001; sd t9, 0x2d78(k0)); cleared
-- again if the kernel is ever loaded anew.
local function clear_tlb_refill()
	if word(0x00000000) == 0x3C1A8001 and word(0x00000004) == 0xFF592D78 then
		for at = 0x00000000, 0x0000007C, 4 do
			eeObj.WriteMem32(at, 0)
		end
	end
end

-- each site at its known place first, then in the game's code, 4096 words a vsync (its anchor line first)
local patcher = function()
	clear_tlb_refill()
	local pending = false
	for _, site in ipairs(SITES) do
		if not site.done then
			if site_at(site, site.known) then
				site.install(site.known)
				site.done = true
			else
				pending = true
			end
		end
	end
	if not pending then
		return
	end
	local stop = scanAt + 4096 * 4
	for at = scanAt, stop - 4, 4 do
		local w = word(at)
		for _, site in ipairs(SITES) do
			local start = at - (site.anchor - 1) * 4
			if not site.done and w == site.lines[site.anchor] and start >= 0x00100000 and site_at(site, start) then
				site.install(start)
				site.done = true
			end
		end
	end
	scanAt = stop
	if scanAt >= 0x00600000 then
		scanAt = 0x00100000
	end
end

emuObj.AddVsyncHook(patcher)
