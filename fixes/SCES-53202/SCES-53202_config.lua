-- Tekken 5 (Europe) [SCES-53202]: DawnStation's fix (2026-11-17, made live in the Lab on the Jak X core).
--
-- The menus shook (the user: "the menus are shaking"). The game shows its picture in the PS2's field mode (SMODE2
-- INT 1 FFMD 1, PAL: each vsync one field of 256 lines, the two fields half a line apart on a TV). In six paused
-- frames of the Time Attack ranking every frame stood half a field line (2.07 px at 1080p) above or below the one
-- before. Sony's field-shift compensation, gsObj.SetDeinterlaceShift(1) (as in Sony's own and many psdevwiki
-- scripts; off by default), lines the fields up: turned on live, the title screen's frames came out with no shift,
-- and the user saw the menus steady. An emulator setting, no game addresses, so the other discs get it as it is.

apiRequest(0.1)

local gsObj = getGsObject()

-- the Jak X cores have it; the older core (Bully's build) doesn't
if gsObj.SetDeinterlaceShift then
	gsObj.SetDeinterlaceShift(1)
end
