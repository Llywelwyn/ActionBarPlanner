import argparse
import csv
import os
import re
import sys
import urllib.request

TABLES = ["SkillLineAbility", "SkillLine", "SpellLevels", "SpellMisc", "SpellName", "ChrClasses", "ChrRaces", "TraitDefinition"]
ATTR0_PASSIVE = 0x40
ATTR0_HIDDEN = 0x80
SKILL_CATEGORIES = {"7", "9"}
EXCLUDED_LINE_NAMES = {"Engraving", "Beast Training"}
DENY_NAMES = {
    "Chilled",
    "Frostbite",
    "Impact",
    "Master of Elements",
    "Magic Absorption",
    "Fire Vulnerability",
    "Clearcasting",
    "Flurry",
    "Unbridled Wrath",
    "Charge Rage Bonus Effect",
    "Lightwell Renew",
    "Study",
}
ACQUIRE_RUNE = "3"
ALLOW_LEVELS = {1296017: 6}
CLASS_MASK_OVERRIDES = {5784: 256, 23161: 256}
PRE_SOD_BUILD = "1.14.4.51829"
SOD_BUILD = "1.15.9.70003"


def detect_build():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", ".build.info")
    try:
        for line in open(path):
            fields = line.rstrip("\n").split("|")
            if fields and fields[-1] == "wow_classic_beta":
                for f in fields:
                    if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", f):
                        return f
    except OSError:
        pass
    return None


def load(table, build, cache):
    path = os.path.join(cache, f"{table}-{build}.csv")
    if not os.path.exists(path):
        url = f"https://wago.tools/db2/{table}/csv?build={build}"
        print(f"fetching {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
        with open(path, "wb") as f:
            f.write(body)
    return list(csv.DictReader(open(path, encoding="utf-8")))


def build_data(build, cache):
    t = {name: load(name, build, cache) for name in TABLES}

    class_tokens = {int(r["ID"]): r["Filename"].upper() for r in t["ChrClasses"]}
    playable_races = {int(r["ID"]) for r in t["ChrRaces"]}
    names = {int(r["ID"]): r["Name_lang"] for r in t["SpellName"]}
    class_lines = {
        r["ID"]
        for r in t["SkillLine"]
        if r["CategoryID"] in SKILL_CATEGORIES and r["DisplayName_lang"] not in EXCLUDED_LINE_NAMES
    }

    attr0 = {}
    for r in t["SpellMisc"]:
        if r["DifficultyID"] == "0":
            attr0[int(r["SpellID"])] = int(r["Attributes_0"])

    base_levels = {}
    spell_levels = {}
    for r in t["SpellLevels"]:
        if r["DifficultyID"] == "0":
            base_levels[int(r["SpellID"])] = int(r["BaseLevel"])
            spell_levels[int(r["SpellID"])] = int(r["SpellLevel"])
    base_levels.update(ALLOW_LEVELS)

    pre_sod = {int(r["ID"]) for r in load("SpellName", PRE_SOD_BUILD, cache)}
    sod = {int(r["ID"]) for r in load("SpellName", SOD_BUILD, cache)} - pre_sod

    talent_ids = {int(r["SpellID"]) for r in t["TraitDefinition"] if r["SpellID"] not in ("", "0")}

    rows = [r for r in t["SkillLineAbility"] if r["SkillLine"] in class_lines]
    line_masks = {}
    for r in rows:
        line_masks[r["SkillLine"]] = line_masks.get(r["SkillLine"], 0) | int(r["ClassMask"])

    data = {token: {} for token in class_tokens.values()}
    skipped = {"passive": 0, "unnamed": 0, "no-level": 0, "denied": 0, "no-class": 0, "rune": 0, "sod": 0}
    for r in rows:
        spell_id = int(r["Spell"])
        talent = spell_id in talent_ids
        class_mask = int(r["ClassMask"]) or CLASS_MASK_OVERRIDES.get(spell_id, 0)
        explicit_class = class_mask != 0
        if r["AcquireMethod"] == ACQUIRE_RUNE and not talent:
            skipped["rune"] += 1
            continue
        if spell_id in sod and not talent and (base_levels.get(spell_id) or 0) < 1:
            skipped["sod"] += 1
            continue
        if class_mask == 0:
            line_mask = line_masks[r["SkillLine"]]
            if line_mask and line_mask & (line_mask - 1) == 0:
                class_mask = line_mask
            else:
                skipped["no-class"] += 1
                continue
        name = names.get(spell_id)
        if not name:
            skipped["unnamed"] += 1
            continue
        if name in DENY_NAMES:
            skipped["denied"] += 1
            continue
        if attr0.get(spell_id, 0) & (ATTR0_PASSIVE | ATTR0_HIDDEN):
            skipped["passive"] += 1
            continue
        level = base_levels.get(spell_id) or 0
        if level < 1 and explicit_class:
            level = spell_levels.get(spell_id) or 0
        if level < 1:
            skipped["no-level"] += 1
            continue
        race_mask = int(r["RaceMasks_0"])
        races = None
        if race_mask:
            races = sorted(rid for rid in playable_races if race_mask & (1 << (rid - 1)))
            if not races:
                continue
        for class_id, token in class_tokens.items():
            if class_mask & (1 << (class_id - 1)):
                cur = data[token].get(spell_id)
                if cur is None or level < cur["level"]:
                    data[token][spell_id] = {
                        "id": spell_id,
                        "level": level,
                        "races": races,
                        "talent": talent,
                    }

    print("skipped:", skipped)
    return {token: sorted(spells.values(), key=lambda s: (s["level"], s["id"])) for token, spells in data.items() if spells}


def write_lua(data, build, out):
    lines = ["local _, ns = ...", "", f'ns.DATA_BUILD = "{build}"', "", "ns.SPELLS = {"]
    for token in sorted(data):
        lines.append(f"\t{token} = {{")
        for s in data[token]:
            parts = [f"id = {s['id']}", f"level = {s['level']}"]
            if s["talent"]:
                parts.append("talent = true")
            if s["races"]:
                parts.append("races = {" + ", ".join(map(str, s["races"])) + "}")
            lines.append("\t\t{" + ", ".join(parts) + "},")
        lines.append("\t},")
    lines.append("}")
    open(out, "w").write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", default=None)
    parser.add_argument("--cache", default=None)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    build = args.build or detect_build()
    if not build:
        sys.exit("could not detect build; pass --build X.Y.Z.NNNNN")
    cache = args.cache or os.path.join(here, "db2cache")
    os.makedirs(cache, exist_ok=True)
    out = args.out or os.path.join(here, "Data.lua")

    data = build_data(build, cache)
    write_lua(data, build, out)
    for token in sorted(data):
        print(f"{token}: {len(data[token])} spells")
    print(f"wrote {out} (build {build})")


if __name__ == "__main__":
    main()
