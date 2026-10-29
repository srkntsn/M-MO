"""Blender source for MIMO's articulated ceramic android head.

Run: blender -b -t 2 -P scripts/create_avatar.py -- --output avatar-build
Exports the editable scene, mobile glTF, and a rendered portrait.
"""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
out = Path(args[args.index('--output') + 1] if '--output' in args else 'avatar-build').resolve()
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metallic=0, roughness=.35, emission=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission:
        socket = bsdf.inputs.get('Emission Color') or bsdf.inputs.get('Emission')
        socket.default_value = (*color, 1)
        strength = bsdf.inputs.get('Emission Strength')
        if strength: strength.default_value = emission
    return m

ceramic = material('Warm pearl ceramic', (.68,.73,.75), .23, .28)
dark = material('Graphite titanium', (.018,.028,.043), .7, .32)
iris = material('Turquoise glass', (.025,.38,.43), .42, .22)
white = material('Porcelain sclera', (.81,.86,.84), .04, .23)
pupil = material('Pupil', (.003,.007,.01), .1, .12)
lipmat = material('Soft copper lips', (.30,.13,.12), .28, .39)
lightmat = material('Teal status light', (.05,.65,.72), .1, .2, 2)
mouthmat = material('Mouth interior', (.008,.006,.009), 0, .8)

def sphere(name, loc, scale, mat, segments=48, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    for p in o.data.polygons: p.use_smooth = True
    return o

def curve(name, points, thickness, mat):
    data = bpy.data.curves.new(name, 'CURVE'); data.dimensions = '3D'
    data.bevel_depth = thickness; data.bevel_resolution = 3
    s = data.splines.new('BEZIER'); s.bezier_points.add(len(points)-1)
    for p, co in zip(s.bezier_points, points):
        p.co = co; p.handle_left_type = 'AUTO'; p.handle_right_type = 'AUTO'
    o = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(o)
    data.materials.append(mat)
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); o.select_set(False)
    for p in o.data.polygons: p.use_smooth = True
    return o

# A continuous sculpted head, with a tapered jaw, cheekbones, eye sockets and
# nasal bridge rather than a circular robot visor.
head = sphere('Head', (0,0,0), (1, .80, 1.46), ceramic, 96, 64)
for v in head.data.vertices:
    x,y,z = v.co
    if z < -.35: x *= 1 - .25 * min(1,(-z-.35)/1.05)
    if y < 0:
        front = min(1, -y / .35)
        nose = .27*math.exp(-((x/.13)**2+((z+.06)/.23)**2))
        bridge = .10*math.exp(-((x/.095)**2+((z-.22)/.38)**2))
        cheek = .075*sum(math.exp(-(((x-s*.48)/.29)**2+((z+.14)/.32)**2)) for s in [-1,1])
        socket = .105*sum(math.exp(-(((x-s*.34)/.23)**2+((z-.30)/.19)**2)) for s in [-1,1])
        y += front * (socket - nose - bridge - cheek)
    v.co = (x,y,z)
head.shape_key_add(name='Basis')
jaw = head.shape_key_add(name='jawOpen')
for p in jaw.data:
    weight = max(0, min(1,(-p.co.z-.32)/.7))
    p.co.z -= .075*weight

for side, suffix in [(-1,'L'),(1,'R')]:
    sphere('Ear'+suffix,(side*.94,.005,-.03),(.16,.18,.35),ceramic)
    sphere('EarInset'+suffix,(side*1.035,-.105,-.035),(.035,.075,.19),dark)
    curve('TempleSeam'+suffix,[(side*.79,-.36,.97),(side*.89,-.47,.59),(side*.90,-.42,.05),(side*.78,-.42,-.54)],.012,dark)
    curve('TempleLight'+suffix,[(side*.903,-.45,.30),(side*.912,-.435,.05)],.014,lightmat)
    # Eye objects share a parent so the runtime can close lids as a group.
    group = bpy.data.objects.new('Eye'+suffix,None); bpy.context.collection.objects.link(group)
    group.location = (side*.34,-.73,.30)
    for name, loc, scale, mat in [
        ('Sclera',(0,-.04,0),(.235,.13,.13),white),
        ('Iris',(0,-.164,0),(.086,.017,.088),iris),
        ('Pupil',(0,-.181,0),(.039,.008,.044),pupil),
        ('Catchlight',(-.023,-.19,.032),(.013,.007,.016),white),
    ]:
        o = sphere(name+suffix,loc,scale,mat,32,20); o.parent=group
    for top in [True,False]:
        pts=[]
        for i in range(13):
            a=math.pi*i/12
            pts.append((side*.34+.245*math.cos(a),-.855+.035*abs(math.cos(a)),.30+(1 if top else -1)*.132*math.sin(a)))
        curve(('UpperLid' if top else 'LowerLid')+suffix,pts,.024,ceramic)
    curve('Brow'+suffix,[(side*.34-.23,-.80,.57),(side*.34,-.85,.635),(side*.34+.22,-.79,.59)],.027,dark)
    sphere('Nostril'+suffix,(side*.075,-1.015,-.165),(.032,.014,.018),dark,24,12)

# Separate upper and lower lips, driven by a morph target; dark mouth opens
# with the same weight. This is animation-ready geometry, not a painted line.
for upper in [True,False]:
    pts=[]
    for i in range(25):
        x=-.265+.53*i/24
        arch=math.sqrt(max(0,1-(x/.265)**2))
        z=-.48 + (1 if upper else -1)*(.018+.028*arch)
        if upper: z += .018*math.exp(-((abs(x)-.075)/.05)**2)
        pts.append((x,-.828-.018*arch,z))
    o=curve('UpperLip' if upper else 'LowerLip',pts,.026 if upper else .033,lipmat)
    o.shape_key_add(name='Basis'); shape=o.shape_key_add(name='jawOpen')
    for p in shape.data:
        influence=max(0,1-(p.co.x/.29)**2)
        p.co.z += (.035 if upper else -.135)*influence
mouth=sphere('MouthInterior',(0,-.815,-.495),(.253,.015,.025),mouthmat)
mouth.shape_key_add(name='Basis'); shape=mouth.shape_key_add(name='jawOpen')
for p in shape.data: p.co.z=p.co.z*4.6-.045
sphere('ChinAccent',(0,-.57,-1.16),(.29,.038,.045),dark)
sphere('Neck',(0,.12,-1.52),(.36,.34,.53),dark)
sphere('Collar',(0,.12,-1.82),(.66,.48,.16),ceramic)
sphere('ForeheadLight',(0,-.60,1.00),(.027,.018,.027),lightmat,24,16)

# Export only the head; lighting and camera remain in the editable .blend.
avatar=[o for o in bpy.context.scene.objects if o.type in {'MESH','EMPTY'}]
for o in bpy.context.scene.objects: o.select_set(o in avatar)
bpy.ops.export_scene.gltf(filepath=str(out/'mimo-head.glb'),export_format='GLB',use_selection=True,export_morph=True,export_animations=False)

scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=48
scene.cycles.use_denoising=True
scene.render.resolution_x=720; scene.render.resolution_y=1080; scene.render.resolution_percentage=100
scene.world.color=(.045,.065,.085)
scene.render.image_settings.file_format='PNG'
def area(name,loc,energy,color,size):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.color=color; data.shape='DISK'; data.size=size
    obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj); obj.location=loc
    obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
area('Soft key',(-3,-4,4),650,(.82,.93,1),4)
area('Warm fill',(3,-2,1),300,(1,.77,.60),3)
area('Teal rim',(2,2,3),900,(.25,.85,1),3)
bpy.ops.object.camera_add(location=(.22,-6.5,.25))
camera=bpy.context.object; camera.rotation_euler=(Vector((0,-.1,-.10))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'; camera.data.ortho_scale=4.5; scene.camera=camera
scene.render.film_transparent=False
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.013,.025,.043,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
bpy.ops.wm.save_as_mainfile(filepath=str(out/'mimo-head.blend'))
scene.render.filepath=str(out/'mimo-portrait.png')
bpy.ops.render.render(write_still=True)
for o in avatar:
    if o.type=='MESH' and o.data.shape_keys:
        key=o.data.shape_keys.key_blocks.get('jawOpen')
        if key: key.value=.7
scene.render.filepath=str(out/'mimo-speaking.png')
bpy.ops.render.render(write_still=True)
print('MIMO_AVATAR_READY',str(out))
