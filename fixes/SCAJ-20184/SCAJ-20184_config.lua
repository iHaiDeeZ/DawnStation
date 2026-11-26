-- Seiken Densetsu 4 (Asia) [SCAJ-20184]: the build-independent part of Dawn of Mana's config (fixes/SLUS-21574,
-- where the notes are), UNTESTED on this disc (2026-11-17). Left out: the USA disc's 16:9 and 60 FPS patches and the
-- 16:9 picture that goes with them, because they write the USA build's addresses and this build's code hasn't been
-- checked. The GS settings below and the cli.conf's emulator options don't depend on the build.

apiRequest(2.2)

local emuObj = getEmuObject()
local gsObj = getGsObject()

emuObj.PadSetLightBar(0, 100, 30, 230)
gsObj.SetDeinterlaceShift(1)

emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", {tw = 9, th = 9, psm = 49, zmsk = 1})
