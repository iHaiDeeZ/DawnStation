-- Downhill Domination (SLES-52202, Europe): the US disc's fix (fixes/SCUS-97177), for the same cloud seams at 2x.
-- Untested: there's no PAL disc here.
apiRequest(0.1)

local emuObj = getEmuObject()

-- the cloud seams: simple fetch for point-sampled (texMode 1) and bilinear (texMode 2) textures
emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", { texMode = 1 })
emuObj.SetGsTitleFix("forceSimpleFetch", "reserved", { texMode = 2 })
