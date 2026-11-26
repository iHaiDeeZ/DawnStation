-- The Punisher (SLUS-20864): DawnStation's fix (2026-11-06, Lab 00.08) for its slowness (the user: "the game is
-- slow, stuttering audio"; 65-69% speed by the sound, audio buffers up to 94 ms apart). The game reads pieces of its
-- depth buffer back every frame, 1x16 pixels at a time (BITBLTBUF 0x310A2300: Z24 at 0x2300, 640 wide; at 270,232,
-- 0,339 and so on). Sony's core does each such local-to-host transfer synchronously: the EE waits in its GIF FIFO read
-- (file 0xA41825) while the GS thread flushes the frame so far to the GPU and reads the pixels back. The EE thread
-- slept 33-39% of the time there, even with that wait's 4 ms / 1 ms sleeps cut to 0.1 ms. One routine (0x1A07B0)
-- builds every such packet (MSKPATH3, FLUSHA, DIRECT 6: BITBLTBUF, TRXPOS, TRXREG, FINISH, TRXDIR), TRXDIR's value from
-- `addiu s0, zero, 1` (0x1A0894); its callers (0x197CC0, 0x19C574) then read the pixels in and go through them byte
-- by byte. With TRXDIR 3 no transfer starts, and the core answers the FIFO read with zeros at once (a read with no
-- transfer running clears the buffer and returns). What the game uses the pixels for isn't known yet: if something
-- looks wrong with this on (lights, flares, aiming), the section can be turned off in the game's page.

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- The routine's register numbers (0x1A0884 here): addiu t1, zero, 0x50; t3, 0x51; t6, 0x52; t7, 0x61;
-- addiu s0, zero, 1 (TRXDIR's value); addiu v0, zero, 0x53. Once in SLUS-20864's 32 MB. Looked for by these words
-- elsewhere (2048 a vsync, 0x100000 to 0x3FFFFF, given up after 10 passes), so other discs' copies are found too.
local ROUTINE = {0x24090050, 0x240B0051, 0x240E0052, 0x240F0061, -1, 0x24020053}
local site, scanAt, passes = nil, 0x00100000, 0

local function site_at(at)
	for k = 1, #ROUTINE do
		local word = eeObj.ReadMem32(at + (k - 1) * 4) & 0xFFFFFFFF
		if ROUTINE[k] >= 0 then
			if word ~= ROUTINE[k] then
				return false
			end
		elseif word ~= 0x24100001 and word ~= 0x24100003 then
			return false
		end
	end
	return true
end

local function find_site()
	if site and site_at(site) then
		return site
	end
	site = nil
	if site_at(0x001A0884) then
		site = 0x001A0884
		return site
	end
	if passes >= 10 then
		return nil
	end
	local stop = scanAt + 2048 * 4
	for at = scanAt, stop - 4, 4 do
		if (eeObj.ReadMem32(at) & 0xFFFFFFFF) == 0x24090050 and site_at(at) then
			site = at
			return site
		end
	end
	scanAt = stop
	if scanAt >= 0x00400000 then
		scanAt, passes = 0x00100000, passes + 1
	end
	return nil
end

local patcher = function()
	-- [No depth read-backs (DawnStation)]
	local at = find_site()
	if at and (eeObj.ReadMem32(at + 16) & 0xFFFFFFFF) == 0x24100001 then
		eeObj.WriteMem32(at + 16, 0x24100003) -- addiu s0, zero, 3: TRXDIR 3, no transfer
	end
end

emuObj.AddVsyncHook(patcher)
