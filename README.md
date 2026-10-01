# Action Bar Planner

Open with `/abp` or the minimap button.

![image](https://media.forgecdn.net/attachments/description/null/description_c4bc3963-e529-4d39-917a-553e6c0bbbdf.png)

Action Bar Planner is used for planning out binds. It shows all the abilities your class learns, at what level, and whether they're currently bound somewhere (or planned in the planner). You can drag the abilities, items, or macros onto the bars to plan out your bars in advance.

![image](https://media.forgecdn.net/attachments/description/null/description_924082c7-4966-4768-b14b-222aaa8072a3.png)

- `Auto-place` will automatically place spells in the correct spots on your action bars when you learn new abilities, at max rank or at a specific rank you've pinned (e.g. rank 1 Frostbolt).
- `Preview` shows you a preview of your planned abilities on your action bar.
- `Keybinds` allows quick-keybinding from within the addon, and shows a list of keyboard buttons and what they're currently assigned to, and which ones are currently free.
- `Share` exports the plan as text, and imports plans from others.

Plans are saved per character. `/abp preview` and `/abp minimap` toggle the overlay and the minimap button.

## Data

`Data.lua` is generated from the game's DB2 tables (via wago.tools) for the installed build. After a patch, run `python3 gen_data.py` in this folder to regenerate it.
