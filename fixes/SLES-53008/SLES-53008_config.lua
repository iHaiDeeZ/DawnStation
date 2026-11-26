-- Mercenaries: Playground of Destruction (Europe) [SLES-53008]: DawnStation's fix, the USA disc's
-- (fixes/SLUS-20932, made there in the Lab; untested here). Its frame wait is found by its lines, so it goes in
-- only where this disc has the same code; the addresses below are the USA disc's. This copy starts at 50 vsyncs a
-- second (PAL).
-- On the USA disc the game ran at a third to a half of its speed and its voices stuttered: in play the PS4's
-- GPU finishes its ~3,700 draws a frame at 2x only about 10-17 times a second, and the game waits for 30.
--
-- The game paces itself with one frame wait (0x3AD6C8 here): it waits until the vblanks since the last frame reach
-- its frame interval (0x4A55DC: 2 = 30 fps in play, 0 = every vblank on some screens), and it moves by the time that
-- passed (its own 20 fps mode, interval 3, shows it). Under emulation the game's clock slows down with the emulator,
-- so it never lowers its rate and plays in slow motion. Held live at 3, 4 and 6 vblanks the game ran at 51%, 68% and
-- 89% of its speed instead of 36%, at the same ~9-10 frames a second.
--
-- The fix: the wait's loop also waits for a floor this script sets, in the loop's two free slots (the game's compare
-- into at, then sltiu v0, v0, floor and or v0, v0, at): 0 = the game's own rate, up to 6 vblanks (10 fps). Each second
-- (os.time) it counts the vsyncs and the frames. Behind (under 95% of 59.94), the floor becomes the interval at which
-- those frames fill the vsyncs. At full speed it tries one step lower after a rest (8 s, doubled each time a try falls
-- behind, up to 16 s); a try goes back as soon as the GPU queue stays full for 8 vsyncs, or at the second's end under
-- 97%. The queue (gsObj.GetFramesInQueue: frames waiting for the GS thread; the cli's --gs-adaptive-frameskip=1 turns
-- that count on) says when the GPU is the one behind; it can be 0 while the GPU is still busy with its batches, so it
-- never says there is room.
-- 6 is the top: the game's speed check (0x3832D8) takes no rate under 10 fps.
-- The wait is found by its lines (the address below is this disc's), so the same script serves the other discs; a
-- place already changed (a save state made with the fix) is taken as it is.
apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local gsObj = getGsObject and getGsObject()

local now = os and os.time
local queue = gsObj and gsObj.GetFramesInQueue

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

-- How a line is matched: the whole word; its upper half (an address's low half: the build's); any word (one this
-- script writes, which the site's own test checks).
local F, H16, ANY = 0, 1, 2

local function site_at(site, at)
	for k = 1, #site.lines do
		local m = site.mask[k]
		if m ~= ANY then
			local w, l = ee(at + (k - 1) * 4), site.lines[k]
			if m == F then
				if w ~= l then
					return false
				end
			elseif math.floor(w / 0x10000) ~= math.floor(l / 0x10000) then
				return false
			end
		end
	end
	return site.ours(at)
end

-- The frame wait (0x3AD6C8 here): until the vblank count (0x4A55D4) moves, then while count - the last frame's
-- (0x4A55D8) < the interval (0x4A55DC); the frame's vblanks go to 0x4A55E0 and the count to the last frame's.
local WAIT = {
	lines = {0x3C02004A, 0x3C07004A, 0x8C4455D4, 0x0040302D, 0x8C4355D4, 0x14830009, 0x3C02004A, 0x00C0182D,
		0x8C6255D4, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x1082FFFA, 0x3C02004A, 0x3C03004A,
		0x8C4455D8, 0x3C05004A, 0x8C6355DC, 0x00000000, 0x8CA255D4, 0x00441023, 0x0043102B, 0x00000000,
		0x00000000, 0x1440FFFA, 0x00000000, 0x8CC355D4, 0x3C02004A, 0x8CE455D8, 0x8CC555D4, 0x00641823,
		0xAC4355E0, 0x03E00008, 0xACE555D8},
	mask = {H16, H16, H16, F, H16, F, H16, F, H16, F, F, F, F, F, H16, H16, H16, H16, H16, F, H16, F, ANY, ANY, ANY,
		F, F, H16, H16, H16, H16, F, H16, F, H16},
	known = 0x003AD6C8, -- SLUS-20932
	anchor = 14,        -- beq a0, v0: the wait for the count to move
}
-- The loop: lw v0, count / subu v0, v0, a0 (the vblanks since the last frame) / CMP / FLOOR / JOIN / bnez v0, loop.
local CMP, FLOOR, JOIN = 0x58, 0x5C, 0x60
local CMP_GAME = 0x0043102B  -- sltu v0, v0, v1: under the interval (the game's)
local CMP_AT = 0x0043082B    -- sltu at, v0, v1: the same, into at
local FLOOR_0 = 0x2C420000   -- sltiu v0, v0, floor: under the floor
local JOIN_OR = 0x00411025   -- or v0, v0, at: either
-- Both nops (the game's), or this script's three words.
function WAIT.ours(at)
	local c, f, j = ee(at + CMP), ee(at + FLOOR), ee(at + JOIN)
	return (c == CMP_GAME and f == 0 and j == 0) or
		(c == CMP_AT and math.floor(f / 0x10000) == math.floor(FLOOR_0 / 0x10000) and j == JOIN_OR)
end

-- An address from a lui (at +hi) and a load's offset (at +lo) in the wait.
local function address(at, hi, lo)
	local off = ee(at + lo) % 0x10000
	if off >= 0x8000 then
		off = off - 0x10000
	end
	return (ee(at + hi) % 0x10000) * 0x10000 + off
end

-- The search while the wait is missing: 512 words a vsync (each read costs the EE about 1.4 us), three passes over
-- the game's code at most.
local WORDS = 512
local LO, HI, PASSES = 0x00100000, 0x00500000, 3
local scan, left = LO, PASSES

local function find()
	if site_at(WAIT, WAIT.known) then
		return WAIT.known
	end
	if left <= 0 then
		return nil
	end
	local anchor, back = WAIT.lines[WAIT.anchor], (WAIT.anchor - 1) * 4
	local stop = scan + WORDS * 4
	for at = scan, stop - 4, 4 do
		if ee(at) == anchor and at - back >= LO and site_at(WAIT, at - back) then
			return at - back
		end
	end
	scan = stop
	if scan >= HI then
		scan, left = LO, left - 1
	end
	return nil
end

-- Vsyncs a second at full speed. A PAL disc's copy starts at 50 and takes 59.94 after three seconds near 60 (its
-- 60 Hz mode).
local HZ = 50
local near60 = 0
local function highest()
	return math.floor(HZ / 10 + 0.5) -- 10 fps: 6 at 59.94, 5 at 50
end

local floor = 0       -- the vblanks a frame waits for at least (0: the game's own interval)
local from = nil      -- while a lower floor is on trial: the one it came from
local trial = 0       -- full-speed seconds the trial still needs
local hold = 0        -- seconds before the next try lower after a rise
local rest = 0        -- seconds before the next try after one fell behind
local wait = 8        -- the next rest: 8 s, doubled up to 16 s; back to 8 s when a try holds
local slow = 0        -- seconds behind in a row
local counted = false -- the GPU queue was seen above 0: its count is on
local full = 0        -- vsyncs in a row, while a try is on, with 2 or more frames queued for the GS thread

-- The try lower fell short: back (or higher, if what the GPU managed says so), and a longer rest before the next.
local function fell(want)
	floor, from, trial, full = math.max(from, want or 0), nil, 0, 0
	rest, wait, hold = wait, math.min(wait * 2, 16), 0
end

-- One second: rate = vsyncs in it, frames = frames the wait ended, idle = vsyncs with no frame queued for the GPU,
-- game = the game's interval.
local function second(rate, frames, idle, game)
	if rate >= 56 and rate <= 62 then
		near60 = near60 + 1
		if near60 >= 3 then
			HZ = 59.94
		end
	else
		near60 = 0
	end
	local g = math.max(game, 1)
	if floor <= g then
		floor = 0
	end
	local e = math.max(g, floor) -- the vblanks a frame waits for now
	-- The interval at which this second's frames fill the vsyncs (what the GPU manages when it's behind).
	local want = math.min(math.ceil(HZ / math.max(frames, 1)), highest())
	if from and rate < 0.97 * HZ then
		fell(want)
	elseif rate < 0.95 * HZ then
		slow = slow + 1
		if slow >= 2 or (counted and idle < rate * 0.25) then
			-- Behind for two seconds, or at once when the GPU's queue was full nearly all of this one (a single slow
			-- second with the queue empty is a hitch): two steps at most.
			floor, hold = math.min(math.max(e + 1, math.min(want, e + 2)), highest()), 4
		end
	else
		slow = 0
		if rate >= 0.97 * HZ then
			if from then
				trial = trial - 1
				if trial <= 0 then
					from, rest, wait = nil, 0, 8 -- it held: the next step comes at once
				end
			end
			if not from and floor > g then
				if rest > 0 then
					rest = rest - 1
				elseif hold > 0 then
					hold = hold - 1
				elseif not (counted and idle < rate * 0.5) then -- (the GS thread still behind half the time: no)
					from, trial, full = floor, 2, 0
					floor = e - 1
				end
			end
		end
	end
	if floor <= g then
		floor = 0
	end
end

local site, last_at, interval_at, last
local sec, vsyncs, frames, idle = nil, 0, 0, 0
local whole = false -- the second being counted began as the clock moved on (not a part one)

-- The wait's loop as this script's, with the floor (each write makes the core compile that code again: only words
-- that differ). In this order the loop ends at every step: the floor's compare first (at 0), the game's into at,
-- then the two joined.
local function apply()
	if ee(site + CMP) ~= CMP_AT or ee(site + JOIN) ~= JOIN_OR then
		eeObj.WriteMem32(site + FLOOR, FLOOR_0)
		eeObj.WriteMem32(site + CMP, CMP_AT)
		eeObj.WriteMem32(site + JOIN, JOIN_OR)
	end
	if ee(site + FLOOR) ~= FLOOR_0 + floor then
		eeObj.WriteMem32(site + FLOOR, FLOOR_0 + floor)
	end
end

local function pace()
	if not site then
		site = find()
		if not site then
			return
		end
		last_at = address(site, 0x38, 0x40)     -- lui v0 / lw a0, last(v0)
		interval_at = address(site, 0x3C, 0x48) -- lui v1 / lw v1, interval(v1)
		last = ee(last_at)
		apply()
	end
	local s = now()
	if s ~= sec then
		local onward = sec ~= nil and s == sec + 1
		if onward then
			if not site_at(WAIT, site) then
				site, scan, left, sec = nil, LO, PASSES, nil
				return
			end
			if whole and frames > 0 then
				second(vsyncs, frames, idle, ee(interval_at))
			end
			apply()
		end
		sec, vsyncs, frames, idle, whole = s, 0, 0, 0, onward
	end
	vsyncs = vsyncs + 1
	local l = ee(last_at)
	if l ~= last then
		frames, last = frames + 1, l
	end
	if queue then
		local q = queue()
		if q == 0 then
			idle = idle + 1
		elseif q > 0 then
			counted = true
		end
		-- A try lower that the GPU can't keep up with fills the queue within a few frames: back at once (and this
		-- second doesn't count).
		if from and q >= 2 then
			full = full + 1
			if full >= 8 then
				fell()
				apply()
				whole = false
			end
		else
			full = 0
		end
	end
end

-- [Adaptive frame rate]
-- On: the frame rate drops (down to 10 fps) while the GPU can't keep up, so the game and its voices keep their speed.
-- Off: always the game's own rate, in slow motion where the GPU falls behind.
if now then
	emuObj.AddVsyncHook(pace)
end
