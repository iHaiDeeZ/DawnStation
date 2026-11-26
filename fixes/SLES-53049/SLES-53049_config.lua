-- The Punisher (SLES-53049, PAL): The Punisher's fix (fixes/SLUS-20864, where the reasons are), UNTESTED on this
-- disc (2026-11-06). The routine that builds the depth read-back packets is looked for by its instructions, so
-- no SLUS-20864 address has to match; if this disc's routine differs, nothing is written.

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- The routine's register numbers (0x1A0884 on SLUS-20864): addiu t1, zero, 0x50; t3, 0x51; t6, 0x52; t7, 0x61;
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
