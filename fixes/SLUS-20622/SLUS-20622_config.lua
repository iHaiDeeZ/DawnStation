-- Silent Hill 3 (USA) [SLUS-20622]: DawnStation's fix (2026-11-27, Lab 00.32) for the picture in the top half of the
-- screen with the PS2's video memory below it (psdevwiki: "top half of the screen is useable but the bottom half is a
-- glitchy mess").
--
-- As Silent Hill 2, the game runs the GS interlaced in field mode and gives the display 896 lines (DISPLAY DW 2559,
-- DH 895), twice its 448-line frame: a PS2 shows each field from the field's own start and the rest never reaches the
-- screen, but Sony's core shows all of it as one picture. The fix gives the game's display settings 448 lines (DH 447):
-- its own three (0x364E00, 0x364E28, 0x364E50: front buffer, back buffer, title) and libgraph's double-buffer pair
-- (0x1223240, 0x1223268). Each is a 0x28-byte sceGsDispEnv (PMODE, SMODE2, DISPFB, DISPLAY, BGCOLOR); the upper half
-- of DISPLAY (+0x1C) is only rewritten while it holds exactly DW 2559 and DH 895, so the screen position the player
-- sets (DX, DY) stays as it is, and another version of the disc is left alone.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

local DISPLAY_HI = {0x00364E1C, 0x00364E44, 0x00364E6C, 0x0122325C, 0x01223284}
local DH895 = 0x0037F9FF -- DW 0x9FF, DH 0x37F
local DH447 = 0x001BF9FF -- DW 0x9FF, DH 0x1BF

local patcher = function()
	for i = 1, #DISPLAY_HI do
		local at = DISPLAY_HI[i]
		if eeObj.ReadMem32(at) == DH895 then
			eeObj.WriteMem32(at, DH447)
		end
	end
end

emuObj.AddVsyncHook(patcher)
