import json, re, subprocess, sys, zipfile
from pathlib import Path

here = Path(__file__).parent
version = re.search(r"^## Version:\s*(\S+)", (here / "QuestQuarry.toc").read_text(encoding="utf-8"), re.M).group(1)
tag = f"v{version}"
out = here / "dist"
out.mkdir(exist_ok=True)
zip_path = out / f"QuestQuarry-{version}-forever.zip"
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for name in ("QuestQuarry.toc", "QuestQuarry.lua", "Bindings.xml", "README.md"):
        z.write(here / name, f"QuestQuarry/{name}")
meta = out / "release.json"
meta.write_text(json.dumps({"releases": [{"name": "QuestQuarry", "version": tag, "filename": zip_path.name, "nolib": False,
                                          "metadata": [{"flavor": "forever", "interface": 16001}]}]}, indent=1))
notes = sys.argv[1] if len(sys.argv) > 1 else f"QuestQuarry {version}"
if subprocess.run(["gh", "release", "view", tag], capture_output=True).returncode == 0:
    subprocess.check_call(["gh", "release", "upload", tag, str(zip_path), str(meta), "--clobber"])
else:
    subprocess.check_call(["gh", "release", "create", tag, str(zip_path), str(meta), "--title", f"QuestQuarry {version}", "--notes", notes])
print(tag, zip_path.name)
