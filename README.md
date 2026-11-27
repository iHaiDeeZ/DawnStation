<h1 align="center">DawnStation compatibility list</h1>

<p align="center">
  <img alt="Games tested" src="https://img.shields.io/badge/games%20tested-50-6f42c1">
  <img alt="Discs covered" src="https://img.shields.io/badge/discs%20covered-183-f0883e">
  <img alt="PS4 homebrew" src="https://img.shields.io/badge/PS4-homebrew-003791">
</p>

<h3 align="center">PS2 games tested on DawnStation, and what was done to make them run</h3>

<p align="center">
  <a href="#statuses">Statuses</a> ·
  <a href="#the-list">The list</a> ·
  <a href="#good-to-know">Good to know</a> ·
  <a href="#game-fixes">Game fixes</a> ·
  <a href="#thanks">Thanks</a>
</p>

---

## Overview

DawnStation runs PS2 games on a PS4 through the emulators Sony made for its PS2 Classics. Many games need help on
those emulators. This is every game tested on DawnStation so far: how far it gets, what was wrong and what DawnStation
does about it. The fixes and settings are built in and apply by themselves when the game starts: there's nothing to
install or set.

**50 games tested:** 39 Playable, 10 Ingame, 1 Loadable. **133 more discs** (other regions, demos)
get the same fixes or settings, untested.

## Statuses

| Status | Meaning |
|---|---|
| **Playable** | Start to finish, no game-breaking issues |
| **Ingame** | Goes in-game, with issues: graphics, speed or a crash later |
| **Intro** | Pictures or menus only |
| **Loadable** | Boots to a black or loading screen only |
| **Nothing** | Doesn't boot |

**Set:** what DawnStation sets for the game by itself (the core, and the emulator options the fix needs).
Cores are named as in a game's Options: Core 0 (Bully), Core 1 (Jak X), and so on.
*Next update* marks a fix that isn't in the current release yet.

## The list

| # | Game | Disc tested | Status | Notes | Same fix, untested |
|---|---|---|---|---|---|
| 1 | Ratchet & Clank | SCUS-97199 | Playable | Froze about 20 s in: fixed (the VU0 handshake, as in Ratchet & Clank 2). **Set:** Core 1 (Jak X), VU1 sync off, psdevwiki Lua script | |
| 2 | Ratchet & Clank 2: Going Commando | SCUS-97268 | Ingame | Plays with DawnStation's VU0 fix; 30-42 fps in places. **Set:** Core 1 (Jak X), CPU speed 125%, VU1 sync off, psdevwiki Lua script | |
| 3 | Ratchet & Clank: Up Your Arsenal | SCUS-97353 | Playable | Black screen after the first cutscene: fixed (VU0 handshake). **Set:** Core 1 (Jak X), VU1 sync off, psdevwiki Lua script | SCUS-97518, SCES-52456, SCAJ-20109, SCPS-15084, SCPS-19309 |
| 4 | Ratchet: Deadlocked | SCUS-97465 | Ingame | Freeze after the main menu: fixed (VU0 handshake); runs at about 74% speed. **Set:** Core 1 (Jak X), VU1 sync off, psdevwiki Lua script | SCES-53285, SCAJ-20157, SCPS-15099, SCPS-15100, SCPS-19321, SCPS-19328 |
| 5 | Downhill Domination | SCUS-97177 | Ingame | A block over the picture and a white, untextured rider: fixed; the speed effect's strips remain. **Set:** VU1 sync on | SLES-52202 |
| 6 | God of War | SCUS-97399 | Playable | Lines along edges and a low frame rate: fixed (psdevwiki's config) | |
| 7 | The Punisher | SLUS-20864 | Playable | Slowness: fixed (the game's depth read-backs); about 86% speed in heavy areas. **Set:** Core 1 (Jak X) | SLES-53047, SLES-53049, SLES-53195 |
| 8 | Burnout Revenge | SLES-53506 | Playable | Freeze on the first race's loading screen (VU1 program cache) and a strip down the left (the bloom effect): fixed | SLES-53507, SLUS-21242, SLAJ-25066 |
| 9 | NASCAR 06: Total Team Control | SLUS-21266 | Playable | Shaking menus: fixed; races run at the game's own 30 fps. **Set:** the 60 FPS patch off | SLES-53635 |
| 10 | Crash Bandicoot: The Wrath of Cortex | SLES-50386 | Playable | Stripes underwater: fixed | SLUS-20238, SLPM-62114 |
| 11 | Crash Nitro Kart | SLUS-20649 | Ingame | Stutter: fixed; 40-59 fps, slow in heavy races. **Set:** VU1 jump cache: Per program, VU1 sync on, psdevwiki Lua script | SLES-51511, SLPM-65580, SLPM-66067 (the same settings) |
| 12 | Crash Twinsanity | SLUS-20909 | Playable | Froze after the PS2 logo (the game's clock ran backwards): fixed. On Core 1 (Jak X) Crash's model breaks up. **Set:** Core 0 (Bully) | SLES-52568 |
| 13 | Dead or Alive 2: Hardcore | SLPS-25026 | Playable | Crash after the PS2 logo (the game's sound call): fixed. **Set:** Core 0 (Bully) | |
| 14 | Need for Speed: Underground 2 | SLUS-21065 | Playable | Full speed with psdevwiki's speed fix; with the 60 FPS patch, about 42 fps instead of a locked 30. **Set:** psdevwiki Lua script, 60 FPS on | |
| 15 | Grand Theft Auto: San Andreas | SLUS-20946 | Playable | Widescreen and no ghosting (patches from PCSX2's patch collection) | SLES-52541, SLES-52927 |
| 16 | Grand Theft Auto: San Andreas (Japan) | SLPM-65984 | Playable | Ghosting off and no stray polygons (the USA disc's emulator settings) | SLPM-55092, SLPM-55292, SLPM-66788 |
| 17 | Tenchu: Wrath of Heaven | SLUS-20397 | Ingame | Hang about 30 s in: fixed; coloured specks on plants remain. **Set:** Core 1 (Jak X), VU1 sync off | |
| 18 | Tenchu: Fatal Shadows | SLUS-21129 | Playable | Long trails over everything: fixed (Jvn9207's fix); disc loads and the grass fixed too. **Set:** Core 1 (Jak X) | SLES-53016 |
| 19 | Nickelodeon Barnyard | SLUS-21277 | Ingame | Hang in Chapter One: fixed; wrong tiles on loading screens, slow cutscenes. **Set:** Mipmaps on, Texture uploads: Hash | |
| 20 | Spider-Man 2 | SLUS-20776 | Ingame | Open: thin lines in cutscenes at 2x, wrong shadows. **Set:** Core 1 (Jak X) | |
| 21 | Spider-Man 3 | SLUS-21552 | Ingame | Open: hitches, and a freeze after the doors open | |
| 22 | Dear Boys: Fast Break! | SLPM-65366 | Ingame | Open: black triangles on the court and the players. **Set:** Recompiler shortcuts: All off, VU accuracy: Flags and branches | |
| 23 | God Hand | SLUS-21503 | Loadable | Open: hangs before its first picture. **Set:** Float clamping: VU (+ COP2), Tile list fix | SLES-54490, SLPM-66550, SLPM-74241 (the same settings) |
| 24 | Harry Potter and the Chamber of Secrets | SLES-51192 | Playable | Fixed on Core 0 (Bully); Core 1 (Jak X) crashes entering the Burrow. **Set:** Core 0 (Bully) | SLES-51193 to 51196, SLES-51214 to 51219, SLUS-20576, SLPS-20234, SLPM-62513 |
| 25 | SpongeBob SquarePants: Globs of Doom | SLUS-21818 | Playable | Loading hang and the health bar's portrait: fixed; full speed. **Set:** Mipmaps on | SLES-55271, SLES-55272, SLES-55402 |
| 26 | The Simpsons Game | SLES-54906 | Playable | Characters drawn wrong, and slow cutscenes: fixed. Core 0 (Bully) crashes | SLES-54904, SLES-54905, SLES-55020, SLUS-21665 |
| 27 | Driv3r | SLUS-20587 | Playable | Slowness: fixed (lighting drawn in one pass); 26-30 fps at full speed, shadows approximate | SLES-50876, SLES-52153, SLPM-65741, SLPM-61092 |
| 28 | Shadow Hearts: Covenant | SLUS-21041 (disc 1) | Playable | Two black screens (at start-up, and where play starts): fixed | SLUS-21044 (disc 2), SLES-82030, SLES-82031, SLPS-25317 / 25318, SLPS-25334 / 25335, SLPS-73214 / 73215, SLPM-60214, SLPM-60219, SLPM-60226 |
| 29 | SSX 3 | SLUS-20772 | Playable | Black screen when a race loads: fixed (as psdevwiki's Lua script) | SLES-51697, SLKA-25118, SLKA-25200, SLKA-90502, SLPM-55077, SLPM-65449, SLPM-65793 |
| 30 | Tomb Raider: The Angel of Darkness | SLUS-20467 | Playable | Black screen, and the missing pause text and menu graphics: fixed. A video can show a bad picture | SLES-51227, SCAJ-20044, SLPS-25246 |
| 31 | Mortal Kombat: Shaolin Monks | SLUS-21087 | Playable | psdevwiki's fix, without its cheats | |
| 32 | Scarface: The World Is Yours | SLUS-21111 | Playable | Black screen after the PS2 logo and frame-rate dips in play: fixed; a steady 60 fps. **Set:** Core 1 (Jak X) | SLUS-21492, SLES-54182, SLES-54183, SLES-54184, SLES-54271, SLES-54534 |
| 33 | Dawn of Mana | SLUS-21574 | Playable | iHaiDeeZ's config: Red-Tv's 60 FPS patch (cutscenes at 30; a switch in the game's Options), 16:9 and Sony's own emulator settings. **Set:** Core 1 (Jak X) | SLPM-66576, SCAJ-20184 (the emulator settings only) |
| 34 | Tekken 5 | SCES-53202 | Playable | Shaking menus: fixed, on the Jak X cores | SLUS-21059, SLPS-25510, SLPS-73223, SCAJ-20125, SCAJ-20126, SCAJ-20199 |
| 35 | Guitar Hero III: Legends of Rock | SLUS-21672 | Playable | Black screen, an emulator crash 30-110 s later, striped text, the floor as static and the guitar as noise: fixed. **Set:** Core 1 (Jak X), VU1 sync on | SLES-54962, SLES-54974 |
| 36 | Devil May Cry | SLES-50358 | Playable | Dante's and Trish's faces in cutscenes (nose, mouth and chin missing): fixed | SLUS-20216, SLPM-65038, SLPM-66502, SLPM-74230, SLPM-67502 (Korea), SLED-50359, SLPM-61008, SLPM-61010, SLPM-65023, SLPM-65025 |
| 37 | Evil Dead: Regeneration | SLUS-21048 | Playable | Wrong sound effects on Core 1 (Jak X), the shotgun and others: Core 8 is used instead, as psdevwiki's list advises. **Set:** Core 8 (Bully v2) | SLES-53457 (the same core) |
| 38 | FIFA Street 2 | SLUS-21369 | Playable | Scrambled flags on Select Team: fixed; matches at about 37-39 fps. iHaiDeeZ's own Lua fix (in Vika2364's collection) fixes it too. **Set:** Core 41 (Resident Evil Code: Veronica X), Texture uploads: Hash | SLES-53796, SLES-53797, SLED-53953 (the same settings) |
| 39 | Mercenaries: Playground of Destruction | SLUS-20932 | Playable | Slow motion and stuttering voices: fixed. The frame rate drops (down to 10 fps) while the PS4 can't keep up, so the game keeps its speed (Options: Adaptive frame rate); full speed in play on a PS4, 30 fps on a PS4 Pro | SLES-52588, SLES-52589, SLES-52590, SLES-53008, SLED-52979, SLUS-29137 |
| 40 | Battlefield 2: Modern Combat | SLUS-21026 | Playable | 3-second freezes every 5 s in play: fixed (tested on a PS4 Pro). **Set:** Core 62 (Jak II v2), VU1 jump cache: Per program | SLES-53729, SLES-53730, SLED-53731, SLUS-29117, SLUS-29152, SLUS-29172 (the same settings) |
| 41 | Pac-Man World 2 | SLUS-20224 | Playable | Black screen, then a crash at start on Core 42 and 16 more cores: fixed since 1.52. Shaky menus: Vika2364's config, with its framebuffer fix made to run (*next update*). **Set:** vk2364 config on (*next update*) | |
| 42 | Burnout 3: Takedown | SLUS-21050 | Playable | *Next update:* the freeze on the first race's loading screen, the strip down the left (the bloom effect) and a loud buzz over all the sound, at any volume, are fixed. What the game sends through its distortion effect isn't heard on these emulators. **Set:** Core 1 (Jak X) | SLES-52584, SLES-52585 |
| 43 | Area 51 | SLUS-20595 | Ingame | Open: slow spots (about 83-92% speed in places), and now and then the picture turns one flat colour for a moment (the gun scanner's picture-in-picture) | |
| 44 | Klonoa 2: Lunatea's Veil | SLUS-20151 | Playable | *Next update:* items in the wrong places are fixed: in the rainy cave the two winged green spheres sat on a ledge by the waterfall instead of up in the branches. Tested on a PS4 Pro | SCES-50354, SLPS-25033, SLUS-28004, SLPM-60138 |
| 45 | Sonic Gems Collection | SLES-53350 | Playable | *Next update:* Sonic the Fighters' grey and black characters and stages are fixed, and it runs at full speed (60 fps, from about 17): DawnStation makes its 3D palettes itself. The collection's other games run well. Tested on a PS4 Pro | SLPM-66074, SLKA-25308 |
| 46 | Guitar Hero II | SLUS-21447 | Playable | *Next update:* the black screen at start is fixed, and songs run at full speed (60 fps, from about 24) with the right sound and no freeze. Tested on a PS4 Pro | SLES-54442, SLED-54509, SLUS-29198 |
| 47 | Silent Hill 2 | SLUS-20228 | Playable | *Next update:* the picture squashed into the top half of the screen and the intro movie shown twice are fixed: psdevwiki's 480p script, now on by default for the Greatest Hits disc (v2.01). The first release (same serial) isn't covered. Tested on a PS4 Pro | |
| 48 | Silent Hill 3 | SLUS-20622 | Playable | *Next update:* the picture in the top half of the screen, with a glitchy mess below it, is fixed. Tested on a PS4 Pro | |
| 49 | Silent Hill 4: The Room | SLUS-20873 | Playable | Runs well without a fix. Tested on a PS4 Pro | |
| 50 | Dragon Ball Z: Budokai Tenkaichi 3 | SLUS-21678 | Playable | Runs well without a fix. Tested on a PS4 Pro | |

## Good to know

- **Other discs:** a game's other regions and demos get the same fix by themselves. They haven't been played, so
  they may still need work.
- **Keep the core:** most fixes are made for one core. DawnStation picks it; choosing another core in a game's
  Options can leave the fix out.
- **Your settings come first:** an option you change in a game's Options replaces the one DawnStation recommends, and
  **Recommended options** at the top of that page puts them all back.
- **Not on the list:** not tested yet, which doesn't mean it doesn't work.
- **Two consoles:** games were tested on a PS4 and a PS4 Pro; where they differ, the notes say so.

## Game fixes

DawnStation users don't need these: they're built in. The [fixes](fixes) folder has them for anyone who wants to read
them or try them elsewhere, one folder per disc: the tested disc's, and the copies the game's other regions and demos
get (untested). They're in the PS2 Classics format, so they can be tried in a PS2 Classics package made for the game.
They were made on DawnStation's cores, though: the list's **Set:** column names the core a game needs, and the notes at
the top of each file say what was wrong and what the fix does.

| File | What it is |
|---|---|
| `<serial>_config.lua` | The game's Lua script: the fix itself |
| `<serial>_cli.conf`, `config-emu-ps4.txt` | Emulator options |
| `vu0_sync_budget`, `vu1_round`, `vu1_matrix`, `vif1_finish_now`, `vif1_mfifo_wait`, `gs_pal_cpu`, `gs_clut_wait` | Switches for fixes built into DawnStation itself; they do nothing anywhere else |

Not in the folder: fixes that are other people's work, used as they are. God of War, Crash Bandicoot: The Wrath of
Cortex, Mortal Kombat: Shaolin Monks and Silent Hill 2 use psdevwiki's; Grand Theft Auto: San Andreas uses PCSX2's
patches and settings from Vika2364's collection.

## Thanks

- **psdevwiki**, for its PS2 Classics configs, scripts and compatibility notes.
- **PCSX2**, for its patch collection and its research into how games use the PS2.
- **Jvn9207** (PSX-Place), for Tenchu: Fatal Shadows' fix.
- **Red-Tv**, for Dawn of Mana's 60 FPS patch.
- **Vika2364**, for a collection of PS2 Classics configs (Pac-Man World 2's includes felixthecat1970's work).
- **RPCS3**, whose compatibility statuses this list uses.

## Disclaimer

DawnStation and this list have no ties to Sony Interactive Entertainment or to the games' publishers. PlayStation,
PS2 and PS4 are trademarks of Sony Interactive Entertainment; game names belong to their owners. Play games you own.
