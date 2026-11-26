-- God Hand (SLUS-21503): DawnStation's fix (1.16).
--
-- The hang before the first picture (found in the user's 1.15 state, slot 1): the game loads its IOP modules (sio2man,
-- padman, mcman, mcserv, libsd, SDRDRV, sdhd, snddrv, cri_adxi) from MODULES\IRX.IMS. Its loader (0x2BE260) copies each
-- one into IOP memory with sceSifSetDma (0x2BE3CC) and then calls sceSifDmaStat (0x2BE3D8) again for as long as the
-- result is below 0, which means "the transfer is done": the opposite of the game's other waits (0x340350 loops while
-- the result is 0 or more). On a PS2 the first check comes while the transfer is still running, so the loop ends at
-- once. In Sony's core the transfer can be done by then, and the loop never ends: in the state, the main thread had sent
-- sio2man and padman, and kept checking mcman.irx's transfer (DMA id 0x60603, sceSifDmaStat -1) for ever.
--
-- The fix makes that loop wait until the transfer is done, as the game's other waits do (0x2BE3E8: bltz v0 -> bgez v0).
-- It's written once the game's code is in memory, over the original instruction only.
--
-- The emulator's own crash 2-3 minutes in (GS thread, core+0x124E8A) is fixed by the Options page's "Tile list fix",
-- recommended on for this game (1.18; in 1.17 the folder's gs_tile_room): the in-game menu module submits the core's GS
-- batches before their tile lists can run over (overlay/menu.c, "GS fixes").

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

emuObj.AddVsyncHook(function()
	if eeObj.ReadMem32(0x002BE3E8) == 0x0440FFFB and eeObj.ReadMem32(0x002BE3D8) == 0x0C0EC010
			and eeObj.ReadMem32(0x002BE3CC) == 0x0C0EC852 then
		eeObj.WriteMem32(0x002BE3E8, 0x0441FFFB) -- bgez v0, 0x2BE3D8
	end
end)
