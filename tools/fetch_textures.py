"""Download the CC0 Poly Haven textures MarchHold uses (1k JPG: albedo, GL normal, AO/rough/metal).

Run from the repo root:  python tools/fetch_textures.py
All textures are CC0 (https://polyhaven.com/license).
"""
import json
import os
import sys
import urllib.request

SETS = [
    # terrain
    "leafy_grass", "forrest_ground_01", "brown_mud_leaves_01", "rock_face", "farm_soil",
    # buildings
    "weathered_planks", "wood_trunk_wall", "rough_wood", "thatch_roof_angled",
    "castle_wall_slates", "white_rough_plaster",
    # nature
    "pine_bark", "bark_brown_02", "rock_boulder_dry",
]
MAPS = {"Diffuse": "diff", "nor_gl": "nor", "arm": "arm"}
UA = {"User-Agent": "asset-fetch/1.0"}
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def main():
    for name in SETS:
        files = json.loads(get("https://api.polyhaven.com/files/" + name))
        os.makedirs(ROOT, exist_ok=True)
        for key, short in MAPS.items():
            dest = os.path.join(ROOT, f"{name}_{short}.jpg")
            if os.path.exists(dest):
                continue
            url = files[key]["1k"]["jpg"]["url"]
            data = get(url)
            with open(dest, "wb") as f:
                f.write(data)
            print(f"{name}_{short}.jpg  {len(data) // 1024} KB")
    print("done")


if __name__ == "__main__":
    sys.exit(main())
