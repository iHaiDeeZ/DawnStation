-- Downhill Domination (SCUS-97177): DawnStation's fix. At 2x the thunderstorm's sky had a grid of dark seams where its
-- scrolling cloud texture repeats (soft lines ~20 px wide after the game's blur, moving with the clouds). Sony's
-- "simple fetch" on every draw, set live on the console (2026-11-06), took them all away and left the rest of the frame
-- as it was; ignoreUpRender on the sky dome's textures, forcePointSampling, fetchFromCurrBuff, ignoreSubBuffCov and
-- ignoreUpShiftTri didn't. Native rendering can't be the fix: core2 shows a black picture in this game.
apiRequest(0.1)

local emuObj = getEmuObject()

-- the cloud seams: simple fetch for point-sampled (texMode 1) and bilinear (texMode 2) textures
emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", { texMode = 1 })
emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", { texMode = 2 })
