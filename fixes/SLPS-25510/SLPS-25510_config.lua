-- Tekken 5 (Japan) [SLPS-25510]: the European disc's fix (fixes/SCES-53202, where the reasons are), UNTESTED on
-- this disc (2026-11-17). An emulator setting, no game addresses: Sony's field-shift compensation, so the fields of
-- the game's field-mode picture line up instead of jumping half a line every frame (the menus shook).

apiRequest(0.1)

local gsObj = getGsObject()

-- the Jak X cores have it; the older core (Bully's build) doesn't
if gsObj.SetDeinterlaceShift then
	gsObj.SetDeinterlaceShift(1)
end
