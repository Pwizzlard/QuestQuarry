# QuestQuarry

RestedXP-style target and quest item buttons for WoW Classic "Forever" (interface 16001).
Uses [Questie](https://github.com/Questie/Questie)'s QuestieDB when installed.

- Skull rows target and mark the mobs for your pinned and selected quests (kill, loot-drop and kill-credit objectives).
- When a quest is complete, the rows switch to the turn-in NPC.
- Item buttons show usable quest items, with count and cooldown.
- Pin up to 5 quests with **+**, and unpin with **x**.
- **Quest Only Tab** checkbox: Tab cycles only your quest mobs. The **Next target >** button does the same.

## Install

Copy this folder to `World of Warcraft/_forever_/Interface/AddOns/QuestQuarry`.

## Commands

```
/qt add [Name, Name...]   add manual targets (no name = current target)
/qt item <link or id>     add a manual item
/qt del <name or item>    remove a manual entry
/qt clear                 clear manual entries
/qt pin | unpin           pin selected quest / clear all pins
/qt follow                always show the selected quest (default on)
/qt auto                  toggle quest-based targets
/qt mark                  toggle skull marking
```
