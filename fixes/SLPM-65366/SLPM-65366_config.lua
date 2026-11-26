-- DEAR BOYS Fast Break! (SLPM-65366): DawnStation's fix (v00.83).
--
-- The court, the stands and parts of the players come out as black triangles and slivers, and the
-- intro movie stays black. From the user's save state (2026-10-31): at the start of every frame the
-- game resets the 24-bit depth buffer (ZBUF_1 = 0x10000e0) to 0 with a full-screen sprite drawn with
-- TEST_1 = 0x32001: alpha test NEVER passes, AFAIL = ZB_ONLY (a failed pixel still writes its depth),
-- depth test ALWAYS (routine 0x11C950; packet: TEST_1, PRIM 6, two XYZ2, TEST_1 = 0). The court is then
-- drawn with depth test GREATER. If the emulator doesn't write depth for pixels that fail the alpha
-- test, the depth buffer is never reset, and whatever lies at the same depth as the frame before (the
-- floor, the stands, a still camera, a movie frame) fails GREATER: black, with slivers where moving
-- players overlap where they were. v00.82 made the test "alpha LESS than 0": no change, so the emulator
-- doesn't do that kind of depth-only write at all.
--
-- This clears the depth the way every renderer does it: no alpha test, depth test ALWAYS, and colour
-- writes masked. To leave the game's own drawing state (context 1) as it is, the sprite is drawn in the
-- GS's second context: at 0x11C9A4 the routine jumps to the code below (0xFF000, unused memory below
-- the game), which writes FRAME_2 (all colour bits masked), ZBUF_2 (the game's ZBUF_1, from the packet
-- just before), TEST_2 (depth ALWAYS), XYOFFSET_2 and SCISSOR_2 (the game's 512x448 screen), the sprite
-- in context 2 at the routine's depth, then PRIM 6 and TEST_1 0 as the game's packet leaves them, and
-- goes back to the routine's end. The packet is 0x50 bytes longer (0xC0). Built and checked against the
-- user's save state (tools/dearboys-depth-clear.py assembles it).

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

local CAVE_AT = 0x000FF000
local CAVE = {
	0x3C19002B, 0x8F2843C8, 0x8F2943CC, 0x00085043, 0x00095843, 0x240C0800,
	0x018A6823, 0x000D6900, 0x018B7023, 0x000E7100, 0x018A7821, 0x000F7900,
	0x018BC021, 0x0018C100, 0x0010283C, 0x3C031000, 0x3463000B, 0xFC430000,
	0x3C035000, 0x3463000B, 0x0003183C, 0xFC430008, 0x3C031000, 0x0003183C,
	0x3463800A, 0xFC430010, 0x2403000E, 0xFC430018, 0x00082183, 0x00042400,
	0x2403FFFF, 0x0003183C, 0x00641825, 0xFC430020, 0x2403004D, 0xFC430028,
	0xDC43FFF0, 0xFC430030, 0x2403004F, 0xFC430038, 0x3C030003, 0xFC430040,
	0x24030048, 0xFC430048, 0x000E203C, 0x008D2025, 0xFC440050, 0x24030019,
	0xFC430058, 0x2504FFFF, 0x00042400, 0x2526FFFF, 0x0006343C, 0x00862025,
	0xFC440060, 0x24030041, 0xFC430068, 0x24030206, 0xFC430070, 0xFC400078,
	0x000E2438, 0x008D2025, 0x00852025, 0xFC440080, 0x24030005, 0xFC430088,
	0x00182438, 0x008F2025, 0x00852025, 0xFC440090, 0xFC430098, 0x24030006,
	0xFC4300A0, 0xFC4000A8, 0xFC4000B0, 0x24030047, 0xFC4300B8, 0x0C045DD4,
	0x244400C0, 0x080472A5, 0x00000000,
}

local patcher = function()
-- [Depth clear]
	local at = eeObj.ReadMem32(0x0011C9A4)
	if at == 0x0010183C or (at == 0x0803FC00 and eeObj.ReadMem32(CAVE_AT) ~= CAVE[1]) then
		for i = 1, #CAVE do
			eeObj.WriteMem32(CAVE_AT + (i - 1) * 4, CAVE[i])
		end
		eeObj.WriteMem32(0x0011C9A8, 0x00000000)
		eeObj.WriteMem32(0x0011C9A4, 0x0803FC00)
	end
end

emuObj.AddVsyncHook(patcher)
