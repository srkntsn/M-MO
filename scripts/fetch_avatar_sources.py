"""Fetch pinned CC0 assets and verify every byte before Blender imports them."""
import concurrent.futures, hashlib, json, urllib.request
from pathlib import Path
manifest=json.loads(Path('scripts/avatar_sources.json').read_text())
root=Path('assets/source/vitruvian');root.mkdir(parents=True,exist_ok=True)
def fetch(item):
    path=root/Path(item['path']).name
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']:return
    url=f"https://raw.githubusercontent.com/{manifest['repo']}/{manifest['commit']}/{item['path']}"
    data=urllib.request.urlopen(url,timeout=120).read()
    assert len(data)==item['size'] and hashlib.sha256(data).hexdigest()==item['sha256'], 'Avatar source checksum differs'
    path.write_bytes(data)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(fetch,manifest['files']))
print('Pinned CC0 avatar sources verified.')
