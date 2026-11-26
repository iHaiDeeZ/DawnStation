-- Spider-Man 2 (SLUS-20776): DawnStation's fix, built into the app since v00.41 (data/fixes/SLUS-20776;
-- a folder of your own in /data/dawn/fixes/SLUS-20776 replaces it).
--
-- The game shadows buildings with stencil shadows: box-shaped shadow volumes (obb_shadow models)
-- drawn into a half-size screen mask (256x224 at GS page 352) through a copy of the depth buffer as
-- Z24, depth comparisons by subtraction blending with COLCLAMP off (wrap-around), and the mask's
-- alpha read back as 8-bit palette indexes (T8H); the mask then darkens the frame. Sony's core gets
-- that mask wrong: dark shapes in the wrong places, even across the sky (psdevwiki's list: "Shadows
-- are rendered incorrectly"; PCSX2 needs autoFlush, cpuSpriteRenderBW and halfPixelOffset for it).
-- Found 2026-10-23 from the user's save state (tools/gs-vram.py, tools/gif-scan.py).

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

local patcher = function()
	-- [Stencil shadows off (DawnStation)]
	-- Treyarch's developer options (145 flags; their names at 0x608320) have DISABLE_STENCIL_SHADOWS,
	-- flag 83. The stencil shadow renderer (0x3AEF74) asks for it first (get_flag, 0x4326D8, called at
	-- 0x3AEFC4) and returns at once when it's set. The options object (vtable 0x66AB48, its pointer at
	-- 0x608940) keeps flag n at +4 + 4n, so flag 83 is at +0x150. Spider-Man's own shadow is a
	-- separate pass and stays. Set every vsync, and only when the name table and the object are the
	-- expected ones.
	if eeObj.ReadMem32(0x0060846C) == 0x00668D60 then -- flag 83's name: "DISABLE_STENCIL_SHADOWS"
		local options = eeObj.ReadMem32(0x00608940)
		if options >= 0x00100000 and options < 0x01F00000 and eeObj.ReadMem32(options) == 0x0066AB48 then
			eeObj.WriteMem32(options + 0x150, 1)
		end
	end
end

emuObj.AddVsyncHook(patcher)
