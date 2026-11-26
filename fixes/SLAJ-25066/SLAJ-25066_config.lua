-- Burnout Revenge (SLAJ-25066, Asia): Burnout Revenge's fix (fixes/SLES-53506, where the reasons are), UNTESTED on this
-- disc (2026-11-06). The bloom's first column clear is looked for by its instructions, so no SLES-53506 address
-- has to match; if this disc's code differs, nothing is written.

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- The clear's packet code, from TEST_1's value to the sprite's second x (0x1443CC here): lui t3, 3; ori t3, t3, 3
-- (TEST_1 0x30003); addiu v0, zero, 0x47; pcpyld; sq; ... addiu a0, zero, 0x200 (x 32); dsll s3, a3, 16; or v0, t1, a0.
-- Index 2 and 20 are the two words the fix changes (either value is accepted). Looked for by these words elsewhere
-- (2048 a vsync, 0x100000 to 0x3FFFFF, given up after 10 passes), so other discs' copies are found too.
local CLEAR = {0x3C0B0003, -1, 0x24020047, 0x704B6389, 0x7DAC0000, 0x25AD0010, 0x24020001, 0x70476389, 0x7DAC0000,
	0x25AD0010, 0x0009583C, 0x24030005, 0x706B6389, 0x7DAC0000, 0x25AD0010, 0x001E9100, 0x0012383C, 0x0160482D,
	0x0007383E, -1, 0x00079C38, 0x01241025}
local TEST_OLD, TEST_NEW = 0x356B0003, 0x356B1001 -- ori t3, t3, 3 (0x1001 left by the first version of this fix)
local X_AT, X_OLD, X_NEW = 0x4C, 0x24040200, 0x24040400 -- addiu a0, zero, 0x200 -> 0x400 (x 32 -> 64)
local site, scanAt, passes = nil, 0x00100000, 0

local function site_at(at)
	for k = 1, #CLEAR do
		local word = eeObj.ReadMem32(at + (k - 1) * 4) & 0xFFFFFFFF
		if CLEAR[k] >= 0 then
			if word ~= CLEAR[k] then
				return false
			end
		elseif k == 2 then
			if word ~= TEST_OLD and word ~= TEST_NEW then
				return false
			end
		elseif word ~= X_OLD and word ~= X_NEW then
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
	if site_at(0x001443CC) then
		site = 0x001443CC
		return site
	end
	if passes >= 10 then
		return nil
	end
	local stop = scanAt + 2048 * 4
	for at = scanAt, stop - 4, 4 do
		if (eeObj.ReadMem32(at) & 0xFFFFFFFF) == 0x3C0B0003 and site_at(at) then
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
	-- [Bloom first column clear (DawnStation)]
	local at = find_site()
	if at then
		if (eeObj.ReadMem32(at + X_AT) & 0xFFFFFFFF) == X_OLD then
			eeObj.WriteMem32(at + X_AT, X_NEW)
		end
		-- a state saved with the first version of this fix holds TEST 0x31001 there: the game's own value back
		if (eeObj.ReadMem32(at + 4) & 0xFFFFFFFF) == TEST_NEW then
			eeObj.WriteMem32(at + 4, TEST_OLD)
		end
	end
end

emuObj.AddVsyncHook(patcher)
