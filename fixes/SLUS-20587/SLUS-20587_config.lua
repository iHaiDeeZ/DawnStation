-- Driv3r (USA) [SLUS-20587]: DawnStation's fix (2026-11-08, Lab), for the newer core (core2).
--
-- The game ran at 7-9 fps (the user: "driver runs like shit"). Not the emulation: psdevwiki's config, which the
-- launcher adds, slows each VU1 program 27 times (--vu1-mpg-cycles=2700) so that the PS4's GPU keeps up; without it
-- the game wants ~30 fps but the emulation drops to a third of full speed. The GPU's load is the game's own lighting:
-- every 24-vertex strip is drawn twice from the same vertices, pass A with colour 2 (ambient and two sky lights)
-- into the main buffer (FBP 0xC8), pass B with colour 1 (the sun) into a second buffer (FBP 0x100), and the frame's
-- last sprites add the second buffer to the first. The core starts a new draw group at every switch between the two
-- buffers: ~9,300 a frame.
--
-- The fix draws each strip once. In VU1's lighting loops (MPG uploads from PS2 RAM, which the display list sends
-- all the time), colour 1 becomes colour 2 plus the sun; the sub-programs with a sun take their pass A geometry tag
-- from colour 1 (init IADDIU vi1, vi0, 0x51f2 -> 0x5f12); and VU1's resident kernel no longer re-kicks the sun pass
-- (its fast path, ISUBIU vi11, vi11, 0x383 -> 0x384; the pass's own routine 0x383 is an empty stub). Two places the
-- second buffer was still used are moved to the main one: the cars' paint layers (template headers 0x44 and 0x4C,
-- written every frame by EE code at 0x298C14 here), and the frame-end sprite that blacks the sun out where the
-- shadow mask (FBP 0x180) is set (EE code at 0x29504C here); with the sun now in the main buffer that sprite darkens
-- by 40% (FIX 0x33) instead, about what the game's shadows took away in the scenes measured. Live (Lab, 2026-11-08):
-- draw groups a frame 11,300 -> 2,900; with the VU1 cost at 900, 30 fps at full speed where the game had 20. This
-- script on the console: 26.6 fps at full speed in the city at dusk (the user: "I think the game runs ok").
--
-- Each place is found by its own words (the addresses below are this disc's), all of them before any is patched,
-- and a place already patched (a save state made with the fix) is taken as it is. The VU1 cost goes to 900 once
-- all are in.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()

-- A word read as 0..0xFFFFFFFF, whether the core gives it signed or not.
local function u32(v)
	if v < 0 then
		return v + 4294967296
	end
	return v
end

local function ee(at)
	return u32(eeObj.ReadMem32(at))
end

-- How a line is matched: the whole word; its upper half (an absolute address's lui, an access whose offset is the
-- build's); its opcode only.
local F, H16, OP = "F", "H16", "OP"

-- the resident kernel, VU 0-255 (MPG code at 0x34f444): 6 words from 0x34fb20
local KERNEL = {
	lines = {0x090B605D, 0x000002FF, 0x082B5859, 0x000002FF, 0x120B5B83, 0x000002FF},
	known = 0x0034FB20,
	anchor = 1,
	patch = {
		{0x0010, 0x120B5B83, 0x120B5B84}, -- kernel 221: no sun re-kick
	},
}
-- program 1, VU 896-1151 (MPG code at 0x351134): 8 words from 0x3515b8
local P1A = {
	lines = {0x52020798, 0x000002FF, 0x8000033C, 0x000002FF, 0x40000000, 0x800002FF, 0x114101F2, 0x00800062},
	known = 0x003515B8,
	anchor = 1,
	patch = {
		{0x0018, 0x114101F2, 0x11610712}, -- P1 init 1043 tag REGS
	},
}
-- program 1, VU 1152-1407 (MPG code at 0x35193c): 6 words from 0x3519b0
local P1B_1 = {
	lines = {0x8000033C, 0x01E2F9BF, 0x8000033C, 0x01E2F069, 0x8022233C, 0x01DC003D},
	known = 0x003519B0,
	anchor = 5,
	patch = {
		{0x0014, 0x01DC003D, 0x01C032BC}, -- P1 1168 slot 1 = col2 + sun
	},
}
-- program 1, VU 1152-1407 (MPG code at 0x35193c): 24 words from 0x351ad8
local P1B_2 = {
	lines = {0x52010007, 0x01E2F9BF, 0x0A201FFE, 0x01E2F069, 0x8022233C, 0x01DC003D, 0x8000033C, 0x019C295B, 0x520417DC, 0x01C393C8, 0x8000033C, 0x01C109FF, 0x400006CF, 0x000002FF, 0x082300AD, 0x000002FF, 0x42090008, 0x000002FF, 0x0A2F1FFF, 0x000002FF, 0x81E203BC, 0x000002FF, 0x8022233C, 0x01DC003D},
	known = 0x00351AD8,
	anchor = 3,
	patch = {
		{0x0014, 0x01DC003D, 0x01C032BC}, -- P1 1205
		{0x005C, 0x01DC003D, 0x01C032BC}, -- P1 1214 (clipped-vertex exit)
	},
}
-- program 1, VU 1152-1407 (MPG code at 0x35193c): 8 words from 0x352098
local P1B_3 = {
	lines = {0x520207C5, 0x000002FF, 0x8000033C, 0x000002FF, 0x40000000, 0x800002FF, 0x114101F2, 0x00800062},
	known = 0x00352098,
	anchor = 1,
	patch = {
		{0x0018, 0x114101F2, 0x11610712}, -- P1 init 1390 tag REGS
	},
}
-- program 1, VU 1408-1663 (MPG code at 0x352144): 6 words from 0x352498
local P1C_1 = {
	lines = {0x01C11000, 0x01C109FF, 0x01841002, 0x01C010DC, 0x8000033C, 0x01DC7BC1},
	known = 0x00352498,
	anchor = 3,
	patch = {
		{0x0014, 0x01DC7BC1, 0x01C67BE8}, -- P1 1516 slot 1 += col2
	},
}
-- program 1, VU 1408-1663 (MPG code at 0x352144): 12 words from 0x3528a0
local P1C_2 = {
	lines = {0x802C333C, 0x01EB98BD, 0x8000033C, 0x01CBA30A, 0x8000033C, 0x01DC6314, 0x03E16002, 0x000002FF, 0x8000033C, 0x01CB9318, 0x8000033C, 0x01DC6301},
	known = 0x003528A0,
	anchor = 2,
	patch = {
		{0x001C, 0x000002FF, 0x01CBA0BE}, -- P1 clipper 1646 ACC = col2
		{0x0024, 0x01CB9318, 0x01CB9308}, -- P1 clipper 1647 MADDx
		{0x002C, 0x01DC6301, 0x000002FF}, -- P1 clipper 1648 no bias
	},
}
-- program 4, VU 1408-1663 (MPG code at 0x354164): 8 words from 0x354368
local P4C_1 = {
	lines = {0x5202079D, 0x000002FF, 0x8000033C, 0x000002FF, 0x40000000, 0x800002FF, 0x114101F2, 0x00800062},
	known = 0x00354368,
	anchor = 1,
	patch = {
		{0x0018, 0x114101F2, 0x11610712}, -- P4 init 1475 tag REGS
	},
}
-- program 4, VU 1408-1663 (MPG code at 0x354164): 8 words from 0x354668
local P4C_2 = {
	lines = {0x10021003, 0x01D081FF, 0x806123FC, 0x01C4213C, 0x800A0874, 0x01C1093C, 0x80010870, 0x01DC7BC1},
	known = 0x00354668,
	anchor = 2,
	patch = {
		{0x001C, 0x01DC7BC1, 0x01C77BE8}, -- P4 1571 slot 1 += col2
	},
}
-- program 2, VU 896-1151 (MPG code at 0x355774): 8 words from 0x355a70
local P2A_1 = {
	lines = {0x520207C6, 0x000002FF, 0x8000033C, 0x000002FF, 0x40000000, 0x800002FF, 0x114101F2, 0x00800062},
	known = 0x00355A70,
	anchor = 1,
	patch = {
		{0x0018, 0x114101F2, 0x11610712}, -- P2 init 994 tag REGS
	},
}
-- program 2, VU 896-1151 (MPG code at 0x355774): 6 words from 0x355df0
local P2A_2 = {
	lines = {0x10021004, 0x01E4213D, 0x38010000, 0x01C1093D, 0x8000033C, 0x01C07BE2},
	known = 0x00355DF0,
	anchor = 2,
	patch = {
		{0x0014, 0x01C07BE2, 0x01C77BE8}, -- P2 1105 slot 1 += col2
	},
}
-- program 2, VU 1152-1407 (MPG code at 0x355f7c): 12 words from 0x356360
local P2B = {
	lines = {0x802C3B3C, 0x01EB98BD, 0x8000033C, 0x01CBA30A, 0x8000033C, 0x01DC6314, 0x03E16002, 0x000002FF, 0x8000033C, 0x01CB9318, 0x8000033C, 0x01C06322},
	known = 0x00356360,
	anchor = 1,
	patch = {
		{0x001C, 0x000002FF, 0x01CBA0BE}, -- P2 clipper 1279 ACC = col2
		{0x0024, 0x01CB9318, 0x01CB9308}, -- P2 clipper 1280 MADDx
		{0x002C, 0x01C06322, 0x000002FF}, -- P2 clipper 1281 no bias
	},
}
-- program 2, VU 1664-1919 (MPG code at 0x356f8c): 8 words from 0x357018
local P2D_1 = {
	lines = {0x520207E9, 0x000002FF, 0x8000033C, 0x000002FF, 0x40000000, 0x800002FF, 0x114101F2, 0x00800062},
	known = 0x00357018,
	anchor = 1,
	patch = {
		{0x0018, 0x114101F2, 0x11610712}, -- P2 init 1684 tag REGS
	},
}
-- program 2, VU 1664-1919 (MPG code at 0x356f8c): 8 words from 0x357230
local P2D_2 = {
	lines = {0x8000033C, 0x01E798BD, 0x8000033C, 0x01C7A34A, 0x8000033C, 0x01DC6301, 0x8000033C, 0x01DC6B41},
	known = 0x00357230,
	anchor = 2,
	patch = {
		{0x0014, 0x01DC6301, 0x01DC6B41}, -- P2 sub 3 1750 col2 + bias first
		{0x001C, 0x01DC6B41, 0x01CD6328}, -- P2 sub 3 1751 slot 1 += col2
	},
}
-- program 2, VU 1664-1919 (MPG code at 0x356f8c): 8 words from 0x3576e8
local P2D_3 = {
	lines = {0x8000033C, 0x01E798BD, 0x802C5BFD, 0x01C7A34A, 0x802D5BFD, 0x01DC6301, 0x8000033C, 0x01DC6B41},
	known = 0x003576E8,
	anchor = 2,
	patch = {
		{0x0014, 0x01DC6301, 0x01DC6B41}, -- P2 sub 3 clipper 1901
		{0x001C, 0x01DC6B41, 0x01CD6328}, -- P2 sub 3 clipper 1902
	},
}
-- program 3, VU 1152-1407 (MPG code at 0x35836c): 8 words from 0x358510
local P3B_1 = {
	lines = {0x520207CA, 0x000002FF, 0x8000033C, 0x000002FF, 0x40000000, 0x800002FF, 0x114101F2, 0x00800062},
	known = 0x00358510,
	anchor = 1,
	patch = {
		{0x0018, 0x114101F2, 0x11610712}, -- P3 init 1207 tag REGS
	},
}
-- program 3, VU 1152-1407 (MPG code at 0x35836c): 8 words from 0x358880
local P3B_2 = {
	lines = {0x81E203BC, 0x01C089BF, 0x8000033C, 0x01C498BD, 0x8000033C, 0x01C4A18A, 0x8044033D, 0x01C493D8},
	known = 0x00358880,
	anchor = 2,
	patch = {
		{0x0014, 0x01C4A18A, 0x01C4A0BE}, -- P3 1316 MADDAz
		{0x001C, 0x01C493D8, 0x01C493C8}, -- P3 1317 MADDx
	},
}
-- program 3, VU 1152-1407 (MPG code at 0x35836c): 8 words from 0x358968
local P3B_3 = {
	lines = {0x81E203BC, 0x01C089BF, 0x03E33802, 0x01C498BD, 0x8000033C, 0x01C4A18A, 0x8044033D, 0x01C493D8},
	known = 0x00358968,
	anchor = 3,
	patch = {
		{0x0014, 0x01C4A18A, 0x01C4A0BE}, -- P3 1345 MADDAz
		{0x001C, 0x01C493D8, 0x01C493C8}, -- P3 1346 MADDx
	},
}
-- program 3, VU 1408-1483 (MPG code at 0x358b74): 10 words from 0x358d08
local P3C = {
	lines = {0x8000033C, 0x01DC6314, 0x8000033C, 0x01EC617C, 0x03E16002, 0x000002FF, 0x802C333C, 0x000002FF, 0x8000033C, 0x01CB9318},
	known = 0x00358D08,
	anchor = 4,
	patch = {
		{0x0014, 0x000002FF, 0x01CBA0BE}, -- P3 clipper 1460 ACC = col2
		{0x0024, 0x01CB9318, 0x01CB9308}, -- P3 clipper 1462 MADDx
	},
}
local SHADOW = {
	lines = {0x3C04003C, 0x8C84D024, 0x24053000, 0x3C070010, 0x3C062800, 0x0080402D, 0x000212C2, 0x00042182, 0x3C013F80, 0x44810000, 0x00041BB8, 0x3C180018, 0x00651825, 0x00042438, 0x00671825, 0x3405A000, 0x00052CB8, 0x00661825, 0x00441025, 0x00651825, 0x3C040A00, 0x34058000, 0x00052CF8, 0x00441025, 0x00651825, 0x2406004C, 0x3405C000, 0x00052D78, 0x24040006, 0x00651825, 0x70C23389, 0x70832389, 0x34028000, 0x00021638, 0x34420064, 0x24030042},
	mask = {H16, H16, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F, F},
	known = 0x0029504C,
	anchor = 3,
	patch = {
		{0x0018, 0x000212C2, 0x240200C8}, -- srl v0, v0, 0xb -> addiu v0, zero, 0xc8: the main buffer
		{0x0080, 0x34028000, 0x34023300}, -- ori v0, zero, 0x8000 -> 0x3300: FIX 0x80 -> 0x33
	},
}
local PAINT = {
	lines = {0x8EE30000, 0x8C6202C8, 0x10400004, 0x00000000, 0x8C62025C, 0x24040001, 0x0002200B, 0x54800004, 0x7AC24740, 0x7AC24700, 0x10000002, 0x7AC34740, 0x7AC34700, 0x7EC24780, 0x7EC34800},
	mask = {F, F, F, F, F, F, F, F, F, F, F, F, F, F, F},
	known = 0x00298C14,
	anchor = 14,
	patch = {
		{0x0020, 0x7AC24740, 0x7AC24700}, -- layer A (header 0x44): the main buffer's FRAME, not the sun buffer's
		{0x002C, 0x7AC34740, 0x7AC34700}, -- layer B (header 0x4C): the same
	},
}

local SITES = {KERNEL, P1A, P1B_1, P1B_2, P1B_3, P1C_1, P1C_2, P4C_1, P4C_2, P2A_1, P2A_2, P2B, P2D_1, P2D_2, P2D_3,
	P3B_1, P3B_2, P3B_3, P3C, SHADOW, PAINT}

-- Each site's words as install leaves them, by line.
for _, site in ipairs(SITES) do
	site.new = {}
	for _, p in ipairs(site.patch) do
		site.new[p[1] / 4 + 1] = p[3]
	end
end

-- The site's lines at this place, as they were (patched false) or as install leaves them (patched true).
local function site_at(site, at, patched)
	for k = 1, #site.lines do
		local w, l, m = ee(at + (k - 1) * 4), site.lines[k], site.mask and site.mask[k] or F
		if patched and site.new[k] then
			l, m = site.new[k], F
		end
		if m == F then
			if w ~= l then
				return false
			end
		elseif m == H16 then
			if math.floor(w / 0x10000) ~= math.floor(l / 0x10000) then
				return false
			end
		elseif math.floor(w / 0x4000000) ~= math.floor(l / 0x4000000) then
			return false
		end
	end
	return true
end

-- The site at this place, as it was or patched already (a save state made with this fix, or the script started again
-- over patched memory). The whole window is compared either way: program 2's clippers are program 1's with other
-- registers, so their patched words alone would match each other's.
local function here(site, at)
	return site_at(site, at, false) or site_at(site, at, true)
end

-- A site still patched: its first new word is there (a save state made without the fix puts the old one back).
local function still(site)
	local p = site.patch[1]
	return ee(site.at + p[1]) == p[3]
end

-- The search while a site is missing: 512 words a vsync (each read costs the EE about 1.4 us), three passes over the
-- game's memory at most (its code and VU1 programs are there from the start).
local WORDS = 512
local SCAN = {sites = SITES, lo = 0x00100000, hi = 0x00600000, passes = 3}

-- Each site at its known place first, then searched (its anchor line first). Nothing is patched until every site is
-- found, and then all of them are: a disc with other VU1 programs or other code keeps the game's own two passes, not
-- half of each. True once all are in.
local function step(s)
	local pending = false
	for _, site in ipairs(s.sites) do
		if site.done and not still(site) then
			site.done = false
		end
		if not site.at and here(site, site.known) then
			site.at = site.known
		end
		pending = pending or not site.at
	end
	if pending then
		if not s.left then
			s.left, s.at = s.passes, s.lo
		end
		if s.left > 0 then
			local stop = s.at + WORDS * 4
			for at = s.at, stop - 4, 4 do
				local w = ee(at)
				for _, site in ipairs(s.sites) do
					local start = at - (site.anchor - 1) * 4
					if not site.at and w == site.lines[site.anchor] and start >= s.lo and here(site, start) then
						site.at = start
					end
				end
			end
			s.at = stop
			if s.at >= s.hi then
				s.at, s.left = s.lo, s.left - 1
			end
		end
		return false
	end
	-- Every site found: the ones not in yet are checked again where they were found (one gone since is searched for
	-- again), then patched; one found patched already is taken as it is.
	local all = true
	for _, site in ipairs(s.sites) do
		if not site.done and not here(site, site.at) then
			site.at, s.left, all = nil, nil, false
		end
	end
	if not all then
		return false
	end
	for _, site in ipairs(s.sites) do
		if not site.done then
			if site_at(site, site.at, false) then
				for _, p in ipairs(site.patch) do
					eeObj.WriteMem32(site.at + p[1], p[3])
				end
			end
			site.done = true
		end
	end
	return true
end

-- [One-pass lighting (DawnStation)]
-- Off: the game's own two passes, at psdevwiki's VU1 cost (2700), so about 7-9 fps again. The cost is lowered only
-- once every site is patched: on a disc where one is missing the game keeps its two passes and their cost.
local fast = false
emuObj.AddVsyncHook(function()
	if step(SCAN) and not fast then
		eeObj.Vu1MpgCycles(900)
		fast = true
	end
end)
