-- Dawn of Mana (USA) [SLUS-21574]: the user's config for this game (2026-11-17), built into DawnStation with the
-- cli.conf beside it. A PS4 PS2 Classics config: Red-Tv's 60 FPS patch (PCSX2 forums) and 16:9, made on the Jak X v2
-- emulator (Core 64 from the next update, which has no in-game menu). DawnStation's recommended options run the game
-- on the Jak X core (Core 1: the same branch, four months older, with the in-game menu), which has every Lua call
-- below and every option of the cli.conf. Not played in DawnStation yet.
--
-- What DawnStation changed (the game's memory ends up the same as with the original):
-- - The 60 FPS patch is a section of its own, so the game's Options list it under DawnStation's fix, where it can
--   be turned off (its author: dialogues in play still go out of sync at 60).
-- - Each word is written only where memory differs, and in cutscenes only the 30 fps values. The original wrote the
--   60 fps values every vsync and then, in cutscenes, the 30 fps ones over them: two of those words are the game's
--   code, and every write there makes the recompiler throw away the code it compiled from it.
-- - ThrottleMax ("reduce load times and screens") lifts the emulator's speed limit: the launcher leaves it out while
--   the game's Speed limit option is on (the default).
--
-- The original's notes:
-- Dawn of Mana NTSC
-- 60fps by Red-Tv @PCSX2 forums
-- ported to PS4
-- emu used=jakx v2
-- Note: This patch(60FPS) will revert cutscenes back to 30fps in order to avoid sync issues. unfortunately, dialogues
-- during gameplay still have sync issues. If the game feels too slow you can change the last line
-- eeObj.WriteMem32(0x205C8734,0x3eX00000) (here the cutscene value 0x3e400000): X = the higher the number the faster
-- the game is.

apiRequest(2.2)

local gpr = require("ee-gpr-alias")

local emuObj = getEmuObject()
local eeObj = getEEObject()
local gsObj = getGsObject()
local eeOverlay = eeObj.getOverlayObject()
local iopObj = getIOPObject()

emuObj.PadSetLightBar(0, 100, 30, 230)
emuObj.SetDisplayAspectWide()
gsObj.SetDeinterlaceShift(1)

-- One word, written only where it differs. The original wrote some through the PS2's uncached view of RAM
-- (0x20000000 up, as in PCSX2 codes); they are compared at the RAM address itself and still written as given.
local function put(addr, value)
	if eeObj.ReadMem32(addr % 0x20000000) ~= value then
		eeObj.WriteMem32(addr, value)
	end
end

local WS = function()
	emuObj.ThrottleMax() -- reduce load times and screens
	put(0x0012ae74, 0x3c013f40) -- 16:9
	-- [60 FPS, cutscenes at 30] by Red-Tv (PCSX2 forums)
	if eeObj.ReadMem16(0xA137C4) == 0x0001 then -- a cutscene: 30 fps
		put(0x20115AE8, 0x00000000)
		put(0x205C8734, 0x3e400000)
	else
		put(0x00115AE8, 0x14600003)
		put(0x005C8734, 0x3f800000)
	end
end

emuObj.AddVsyncHook(WS)

emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", {tw = 9, th = 9, psm = 49, zmsk = 1})
