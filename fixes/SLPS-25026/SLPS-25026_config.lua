-- DEAD OR ALIVE 2 HARD*CORE (SLPS-25026, Japan): DawnStation's fix.
--
-- The crash 1.2 s after the PlayStation logo (IOP PC 0xFFFFFFFF on both cores): the game's sound calls (0x2B6010)
-- build each request in one buffer, 0x699940, that is also where the IOP's answer goes (16 bytes), and send most of
-- them without waiting (mode 1, so the game never waits for that answer). In Sony's cores the answer to one call lands
-- after the game has written the next request and before that request is sent, so the next request carries the answer
-- instead ({1, 0x03580A35, 0x2FE00444, 0x6E000}). Tecmo's sound driver then reads a sound bank header from offset
-- 0x03580A35 with size 0x2FE00444: its copy (SetVH -> userMemCopy) runs over the top of IOP memory into its own thread
-- stacks, and the next thread switch loads a context of 0xFF bytes. Fix 1: those calls ask for no answer (0x2B6678:
-- li t2, 0x10 -> li t2, 0). The game reads the answer only after the calls that wait (0x8000 commands).
--
-- Fix 2 (psdevwiki's "fixes music/sound effects", written there for the US disc into the driver's file buffer at
-- 0x1D77E4, which the IOP has already relocated by then): the driver's sound effect tick (ATick) turns off the SIF1
-- DMA interrupt (DisableIntr 0x2B) around a copy and turns interrupts back on with CpuResumeIntr, so the interrupt that
-- brings the EE's requests stays off. It becomes CpuSuspendIntr, in the loaded driver (tlsnd_driver at 0x088930).
--
-- Both are written once the code is in memory, over the original words only.

apiRequest(0.1)

local eeObj = getEEObject()
local emuObj = getEmuObject()
local okIop, iopObj = pcall(getIOPObject)
local iopRead = okIop and iopObj and pcall(function() return iopObj.ReadMem32(0x00088930) end)

emuObj.AddVsyncHook(function()
	if eeObj.ReadMem32(0x002B6678) == 0x240A0010 and eeObj.ReadMem32(0x002B666C) == 0x24060001
			and eeObj.ReadMem32(0x002B667C) == 0x0C0EFD2A then
		eeObj.WriteMem32(0x002B6678, 0x240A0000) -- li t2, 0: no answer for the calls that don't wait
	end
	if iopRead and iopObj.ReadMem32(0x0008A874) == 0x2404002B and iopObj.ReadMem32(0x0008A878) == 0x0C0254FF
			and iopObj.ReadMem32(0x0008A87C) == 0x27C50010 then
		iopObj.WriteMem32(0x0008A874, 0x27C40010) -- addiu a0, s8, 0x10
		iopObj.WriteMem32(0x0008A878, 0x0C025503) -- jal CpuSuspendIntr (the driver's import, 0x09540C)
		iopObj.WriteMem32(0x0008A87C, 0x00000000) -- nop
	end
end)
