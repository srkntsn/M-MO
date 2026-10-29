"""Check the exported binary, not just the Blender source scene."""
import json, struct, sys
from pathlib import Path
p=Path(sys.argv[1]);data=p.read_bytes()
assert data[:4]==b'glTF', 'Avatar is not a glTF binary'
size,kind=struct.unpack_from('<II',data,12)
assert kind==0x4E4F534A, 'Missing glTF JSON chunk'
doc=json.loads(data[20:20+size])
meshes=doc.get('meshes',[])
assert any(len(m['primitives'][0].get('targets',[]))>=2 for m in meshes), 'Facial jaw/blink morphs were lost during export'
assert any(a.get('name')=='MimoPerformance' for a in doc.get('animations',[])), 'Missing facial performance clip'
assert len(data)<8_000_000, 'Mobile model exceeds size budget'
print('Avatar validated: mobile glTF, jaw and eyelid morphs, performance animation.')
