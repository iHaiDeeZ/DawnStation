-- Nickelodeon Barnyard (SLUS-21277): DawnStation's fix (v1.08).
--
-- The cause of the stuck loading and of the earlier sound hangs (found in the user's 1.07 state, slot 1): FMOD
-- (the IOP module FMOD.IRX and its EE library) sends every message from one buffer (IOP: +0x3000 in its port
-- record at 0xD0310 + port x 0x48F0; EE: +0x3000 at 0x4F48E0 + port x 0x4920) and writes the next message into
-- it as soon as sceSifSendCmd has queued the transfer, before the DMA has read it. A PS2 moves the 0x60 bytes at
-- once; in Sony's core the transfer can wait until the other side takes it, and then it carries the next
-- message: the other side gets that one twice and never the first. In the state: the IOP got command 0x20 (its
-- port 0 ring, entry 9125), carried it out and sent its "done" (0x98554), then answered command 0x25 (entry
-- 9126); the EE's ring has the 0x25 answer twice (9293, 9294) and no 0x20 at all, so the game's count of open
-- 0x20s (0x4D9A60) stayed 1 and the loading loop (0x35B898: sleep until the byte there is 0) waited for ever.
-- The earlier hangs in the sound update (WaitSema(31) at 0x4A2124) were lost "send more stream data" messages.
--
-- The fix is the "SIF send waits" section: FMOD's sends wait until the DMA is done (sceSifDmaStat < 0), as
-- FMOD's own data transfer (IOP 0x967EC) already does. The other sections are safety nets that should never be
-- needed now; their counters show it ("game fix counters" in menu.log with System > Diagnostics: "DFC1" at
-- 0xFFFE0, sound waits given up at 0xFFFE4, loading rescues at 0xFFFEC).

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local okIop, iopObj = pcall(getIOPObject)

-- A word read as 0..0xFFFFFFFF, whether the core gives it signed or not.
local function u32(v)
	if v < 0 then
		return v + 4294967296
	end
	return v
end

-- The sound update's wait for the IOP's "send more stream data" (WaitSema(31) at 0x4A2124) with a limit: the
-- call goes to 0xFF400 (unused memory below the game), which tries the semaphore (PollSema, 0x43FDB0) and sleeps
-- 1 ms between tries (the game's DelayThread, 0x4462F0: the thread really sleeps and the others run), up to
-- 2,000 times (about 2 s); then it goes on without the answer (that update is skipped) and counts it at 0xFFFE4.
-- 1.01-1.07 polled 20,000 times without sleeping (about 10 ms); that routine stays at 0xFF000 for a thread a save
-- state caught inside it.
local WAIT_AT = 0x000FF400
local WAIT = {
	0x27BDFFD0, 0xFFBF0020, 0xFFA40000, 0x240207D0, 0xFFA20008, 0xDFA40000,
	0x0C10FF6C, 0x00000000, 0x0441000F, 0x00000000, 0x0C1118BC, 0x240403E8,
	0xDFA20008, 0x2442FFFF, 0x1440FFF6, 0xFFA20008, 0x3C190010, 0x2739FFE0,
	0x3C093143, 0x35294644, 0xAF290000, 0x8F280004, 0x25080001, 0xAF280004,
	0xDFBF0020, 0x03E00008, 0x27BD0030,
}

local patcher = function()
-- [Sound wait limit]
	local at = eeObj.ReadMem32(0x004A2124)
	if (at == 0x0C10FF68 or at == 0x0C03FC00) and u32(eeObj.ReadMem32(0x004A2128)) == 0x8C4499AC then
		for i = 1, #WAIT do
			eeObj.WriteMem32(WAIT_AT + (i - 1) * 4, WAIT[i])
		end
		eeObj.WriteMem32(0x004A2124, 0x0C03FD00)
	end
end

emuObj.AddVsyncHook(patcher)

-- 1.04-1.07's sleep fallback is gone: it was built on a wrong reading (that the game's sleeps never end), and
-- every sleep in the user's 1.07 state ended (0 give-ups). States saved with it get DelayThread's own
-- WaitSema(0x43FDA0) back at 0x446390; a thread inside the old routine (0xFF200) finishes there. 1.03's routine
-- (0xFF100) has its limit made "reached" for a thread caught inside it, as before.
emuObj.AddVsyncHook(function()
	local at = eeObj.ReadMem32(0x00446390)
	if (at == 0x0C03FC80 or at == 0x0C03FC40) and eeObj.ReadMem32(0x00446394) == 0x0200202D then
		eeObj.WriteMem32(0x00446390, 0x0C10FF68)
	end
	if eeObj.ReadMem32(0x000FF100) == 0x27BDFF80 and eeObj.ReadMem32(0x000FF18C) == 0x0043102B then
		eeObj.WriteMem32(0x000FF18C, 0x24020001) -- addiu v0, zero, 1
	end
end)

-- [SIF send waits]
-- IOP, FSOUND_Command_Send (0x9681C): after sceSifSendCmd (0x969B8) queued the message, 0x969C4 keeps its DMA id
-- (move s6, v0) and a send that wants no answer goes to 0x969E8 (beqz s2), now a loop on sceSifDmaStat (FMOD's
-- own import, 0xBDBA8) until the DMA is done, then frees the buffer as before (0x969F8). A send that wants an
-- answer waits for it as before: the answer only comes once the message has arrived. 0x969E8-0x969F4 held the
-- "failed to send" message, unused since "SIF retries" sends again (0x969C0 -> beqz v0, 0x969A4; written here too).
-- EE, FMOD's command send (0x4A4808): its sceSifSendCmd call (0x4A4A5C) goes to 0xFF300, which calls it and then
-- the kernel's sceSifDmaStat (0x440100) until the DMA is done; a failed send is sent again (0x4A4A64 -> beqz v0,
-- 0x4A4A48, which sets the arguments up again) instead of being printed and dropped.
local SEND_AT = 0x000FF300
local SEND = {
	0x27BDFFE0, 0xFFBF0010, 0x0C111AF6, 0x00000000, 0x10400008, 0xFFA20000,
	0xDFA40000, 0x0C110040, 0x00000000, 0x0441FFFC, 0x00000000, 0xDFA20000,
	0x00000000, 0xDFBF0010, 0x03E00008, 0x27BD0020,
}
emuObj.AddVsyncHook(function()
	if okIop and iopObj and iopObj.ReadMem32(0x000969B8) == 0x0C02F6DF and iopObj.ReadMem32(0x000969C8) == 0x1240000B
			and iopObj.ReadMem32(0x000969E8) == 0x3C04000C then
		local c0 = iopObj.ReadMem32(0x000969C0)
		if c0 == 0x10400009 or c0 == 0x1040FFF8 then
			iopObj.WriteMem32(0x000969F4, 0x00000000) -- nop
			iopObj.WriteMem32(0x000969F0, 0x0441FFFD) -- bgez v0, 0x969E8
			iopObj.WriteMem32(0x000969EC, 0x02C02021) -- move a0, s6
			iopObj.WriteMem32(0x000969E8, 0x0C02F6EA) -- jal sceSifDmaStat
			iopObj.WriteMem32(0x000969C4, 0x0040B021) -- move s6, v0
			iopObj.WriteMem32(0x000969C0, 0x1040FFF8) -- beqz v0, 0x969A4
			iopObj.WriteMem32(0x000969C8, 0x12400007) -- beqz s2, 0x969E8
		end
	end
	if eeObj.ReadMem32(0x004A4A5C) == 0x0C111AF6 and eeObj.ReadMem32(0x004A4A64) == 0x10400009 then
		for i = 1, #SEND do
			eeObj.WriteMem32(SEND_AT + (i - 1) * 4, SEND[i])
		end
		eeObj.WriteMem32(0x004A4A64, 0x1040FFF8)
		eeObj.WriteMem32(0x004A4A5C, 0x0C03FCC0)
	end
end)

-- [SIF retries]
-- 1.07: FMOD gives a packet up when the SIF DMA queue is momentarily full: the IOP's FSOUND_Command_Send prints
-- "failed to send command! sceSifSendCmd failed." (0x969B8 sceSifSendCmd; 0x969C0 beqz v0 -> the message at
-- 0x969E8), its SendToIOP DMA does the same ("DMA failed", 0x967B0 sceSifSetDma, message at 0x967C4), and the
-- EE's stream send (0x4B1FF4 sceSifSetDma) prints and returns after it has already counted the packet. All three
-- try again until the transfer is queued: IOP 0x969C0 -> beqz v0, 0x969A4 (set the arguments up and send again);
-- IOP 0x967C4 -> b 0x9679C; EE 0x4B2008 -> b 0x4B1FDC with its delay slot (a load through the 0 result) a nop.
-- Each is written only over the original instruction (the same in all of the user's states).
emuObj.AddVsyncHook(function()
	if okIop and iopObj then
		if iopObj.ReadMem32(0x000969C0) == 0x10400009 and iopObj.ReadMem32(0x000969B8) == 0x0C02F6DF then
			iopObj.WriteMem32(0x000969C0, 0x1040FFF8)
		end
		if iopObj.ReadMem32(0x000967C4) == 0x3C04000C and iopObj.ReadMem32(0x000967B0) == 0x0C02F6E8 then
			iopObj.WriteMem32(0x000967C4, 0x1000FFF5)
		end
	end
	if eeObj.ReadMem32(0x004B2008) == 0x3C020050 and eeObj.ReadMem32(0x004B1FF4) == 0x0C110048 then
		eeObj.WriteMem32(0x004B200C, 0x00000000)
		eeObj.WriteMem32(0x004B2008, 0x1000FFF4)
	end
end)

-- [Loading rescue]
-- For a "done" lost before this fix (a save state stuck in the loading, like the user's 1.07 slot 1): when the
-- count of open 0x20 commands (0x4D9A60) stays non-zero for 2 s while the IOP has carried out every command it
-- got (FMOD.IRX port 0: read 0xD4BE0 = write 0xD4BE4, with its handler 0x97564 at 0xD4BD0) and the EE has taken
-- every message (0x4F91E0 = 0x4F91E4), nothing is coming any more: the count is set to 0 and the loading goes on.
-- Counted at 0xFFFEC.
local rescueVsyncs = 0
emuObj.AddVsyncHook(function()
	local open = eeObj.ReadMem32(0x004D9A60)
	if open ~= 0 and okIop and iopObj and iopObj.ReadMem32(0x000D4BD0) == 0x00097564
			and iopObj.ReadMem32(0x000D4BE0) == iopObj.ReadMem32(0x000D4BE4)
			and eeObj.ReadMem32(0x004F91E0) == eeObj.ReadMem32(0x004F91E4) then
		rescueVsyncs = rescueVsyncs + 1
	else
		rescueVsyncs = 0
	end
	if rescueVsyncs >= 120 then
		rescueVsyncs = 0
		eeObj.WriteMem32(0x004D9A60, 0)
		eeObj.WriteMem32(0x000FFFE0, 0x31434644)
		eeObj.WriteMem32(0x000FFFEC, eeObj.ReadMem32(0x000FFFEC) + 1)
	end
end)
