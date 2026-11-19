# Bow / Bowgun Auto Fire

A REFramework script for Monster Hunter Wilds that turns firing into a toggle. Click once and your Bow, Heavy Bowgun or Light Bowgun keeps firing on its own. Click again to stop. No more spamming the button.

The shots go through the game's own input system, so it works with mouse, keyboard and controller. Your own click still goes through to the game as normal. The script only adds the repeated shots on top.

## Key features

- One press of the toggle button starts auto fire. Another press stops it, and so does pressing your fire button.
- Works with the Bow, Heavy Bowgun and Light Bowgun. Each one can be switched off separately.
- The toggle button can be rebound to any key, mouse button or controller button.
- Learns your fire button by itself. You fire once normally and the script records which game input that was.
- Delay between shots and press length are adjustable, so charge-and-release weapons shoot properly instead of just charging.
- Supports combos. While you hold a combo key (such as the keys for Dragon Piercer, Power Shot, Charging Sidestep or Ready Tracer), auto fire pauses so it does not interfere, then resumes by itself.
- Stays out of the way. It stops firing and ignores the toggle while your weapon is sheathed, you hold any other weapon, you ride your Seikret, the REFramework menu is open, or you press a stop key (Esc by default).
- Has a reset button that puts every setting back to its default.

## Requirements

- Monster Hunter Wilds (PC, Steam)
- [REFramework](https://github.com/praydog/REFramework) for Monster Hunter Wilds

## Installation

1. Install REFramework if you do not have it.
2. Copy `Bow_Bowgun_AutoFire.lua` into `reframework/autorun/` in your game folder.
3. Start the game and load into a hunt or the training area. Open the REFramework menu (Insert by default) and find **Bow / Bowgun Auto Fire**.
4. Press **Auto-detect fire output**, close the menu, draw your bow or bowgun, stand still and fire once with your normal fire button.
5. Wait while the script tests the output (about ten seconds). Open the menu again to see the result.
6. Draw your weapon and press the toggle button (left click by default).

To uninstall, delete `Bow_Bowgun_AutoFire.lua`. Your settings are in `reframework/data/Bow_Bowgun_AutoFire.json`.

## Settings

- **Auto-detect fire output**: learns which game input fires your weapon, then checks that sending it really makes your character shoot. Run it once, and again if you change your key bindings.
- **Toggle button**: left click by default. Press Rebind, let go of everything, then press the key, mouse button or controller button you want.
- **Output type**: how the repeated shots are sent. Game virtual input is the default and what Auto-detect selects. The other types (controller input, mouse input hooks, mouse device write) are fallbacks that Auto-detect also tries.
- **Fire virtual key numbers**: filled in by Auto-detect. You can edit the list by hand.
- **Press length** (default 120 ms): how long each shot is held. For a charge-and-release weapon this is the charge time before the arrow is released.
- **Delay between shots** (default 300 ms): the pause after each shot before the next one starts. Raise it if your weapon charges instead of shooting.
- **Stop auto fire when I press the fire button myself**: on by default. A fire press made while a combo key is held does not stop it, so combos that include the fire button still work.
- **Combo keys**: the keys that pause auto fire while held. The default is E, F, R and Space. Edit the list, or press Add a combo key and press the key.
- **Wait after a combo key is released** (default 600 ms): how long auto fire stays paused after you let go, so the move can finish before shots resume.
- **Bow, Heavy Bowgun, Light Bowgun**: which weapons the script works on.
- **Stop and ignore the toggle while the game cursor is visible**: the menu check. Turn it off only if it blocks you by mistake.
- **Keys that stop auto fire**: a comma list of Windows virtual key numbers. Esc is 27.
- **Reset everything to defaults**: restores all settings, which is useful when testing.
- **Debug log**: writes what the script does to the REFramework log.

The panel also shows the weapon it detects, your character's current action, the status of the input hook, and a list of the mouse hooks the game uses.

## Compatibility

- The script writes into the game's virtual input once per frame. Other mods that change the same input can interfere with it.
- It is meant for single-player use. Do not use it in online or multiplayer sessions.

## Known issues

- Auto-detect needs you to stand still with the weapon drawn while it runs, because it watches your character's action to see whether a shot happened. It may briefly press a few controller buttons (R2, Y, B, R1) if the main method does not work.
- Combo keys are keyboard and mouse keys. Combos made with controller buttons do not pause auto fire.
- The menu check relies on the game reporting whether its cursor is visible. If your menus are not detected, rely on the stop keys, or turn the check off if it blocks you wrongly.
- Timing follows your frame rate, so very short delays and press lengths can be uneven at low FPS.

## Troubleshooting

- **Nothing happens when I click**: check the status line in the panel. It tells you why the script is idle (sheathed, wrong weapon, menu open, no fire keys learned, and so on).
- **"no fire keys learned yet"**: run Auto-detect fire output once.
- **Auto-detect says no virtual input key changed**: make sure the weapon is drawn, the REFramework menu is closed and you only click the fire button. Moving or pressing other buttons during the 2 seconds after your click can confuse it. Try again.
- **"Virtual input hook: NOT installed"**: this game version does not have the input class the script uses. Report it with the REFramework log.
- **Auto fire starts but the weapon charges instead of shooting**: raise Delay between shots and adjust Press length.
- **Want a clean start**: press Reset everything to defaults, then run Auto-detect again.
- **Menu missing**: check that the file sits in `reframework/autorun/` and that REFramework shows no script errors.

## Credits

- [praydog](https://www.nexusmods.com/profile/praydog?gameId=6993), for REFramework.
- [combolee](https://www.nexusmods.com/profile/combolee?gameId=6993), for One-Tap Carve and Gather, whose way of writing into the game's virtual input this script follows.
- [johnminer](https://www.nexusmods.com/profile/johnminer?gameId=6993), for MHWild Hammer Charge Toggle, whose input-reading approach the early versions used.
