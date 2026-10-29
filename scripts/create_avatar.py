"""Original MIMO character built from a CC0 MakeHuman anatomical head.
Blender export and Cycles render use the SAME model, materials and morphs.
blender -b -t 2 -P scripts/create_avatar.py -- --output avatar-build
"""
import bpy, math, sys, random
from pathlib import Path
from mathutils import Vector
random.seed(27)
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
out=Path(args[args.index('--output')+1] if '--output' in args else 'avatar-build').resolve();out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def mat(name,color,rough=.42,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=m.node_tree.nodes.get('Principled BSDF')
 b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
 return m
skin=mat('Warm natural skin',(.52,.30,.20),.48)
b=skin.node_tree.nodes.get('Principled BSDF');socket=b.inputs.get('Subsurface Weight') or b.inputs.get('Subsurface')
if socket:socket.default_value=.075
vc=skin.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='Color';skin.node_tree.links.new(vc.outputs['Color'],b.inputs['Base Color'])
hairmat=mat('Short soft chestnut hair',(.008,.005,.003),.86)
browmat=mat('Brows',(.035,.018,.011),.6)
white=mat('Warm sclera',(.78,.79,.73),.26)
iris=mat('Hazel iris',(.10,.18,.12),.32)
pupil=mat('Pupils',(.002,.003,.002),.18)
catch=mat('Eye catchlights',(.95,.98,1),.1)
oral=mat('Mouth cavity',(.028,.009,.009),.7)
teeth=mat('Teeth',(.77,.72,.60),.4)
shirt=mat('Deep navy neckline',(.015,.031,.052),.67)

def smooth(o):
 for p in o.data.polygons:p.use_smooth=True
 return o

def sphere(name,loc,scale,material,segments=40,rings=24):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc)
 o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(material);return smooth(o)

def curve(name,points,radius,material):
 data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D';data.bevel_depth=radius;data.bevel_resolution=2
 s=data.splines.new('BEZIER');s.bezier_points.add(len(points)-1)
 for p,co in zip(s.bezier_points,points):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);data.materials.append(material)
 bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False);return smooth(o)

# Preserve real facial topology: nostrils, lips, eyelids, ears and jaw are one
# anatomical mesh rather than a stack of spheres. Broaden cheek/jaw proportions.
verts=[];faces=[]
for line in (Path(__file__).resolve().parents[1]/'assets/source/human-head.obj').read_text().splitlines():
 if line.startswith('v '):verts.append(tuple(map(float,line.split()[1:])))
 elif line.startswith('f '):faces.append([int(x)-1 for x in line.split()[1:]])
def transform(v):
 x,h,depth=v
 width=1.16+.055*math.exp(-((h-6.6)/.65)**2)
 return (x*width,-(depth-.5),h-7.25)
mesh=bpy.data.meshes.new('Anatomical face topology');mesh.from_pydata([transform(v) for v in verts],[],faces);mesh.update()
head=bpy.data.objects.new('MIMO human face',mesh);bpy.context.collection.objects.link(head);head.data.materials.append(skin);smooth(head)
colors=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='POINT')
for i,(x,h,d) in enumerate(verts):
 cheek=math.exp(-((abs(x)-.42)/.25)**2-((h-6.91)/.28)**2)*max(0,min(1,(d-.8)*2))
 lip=math.exp(-((h-6.61)/.066)**4)*math.exp(-(x/.235)**6)*max(0,min(1,(d-1.35)*8))
 base=(.56+.025*cheek,.335-.055*cheek,.24-.035*cheek);rose=(.38,.12,.105)
 colors.data[i].color=(*(base[j]*(1-.7*lip)+rose[j]*.7*lip for j in range(3)),1)
# Two independent morph keys share a clip: mouth uses first half second;
# idle blinking uses the final two frames. This avoids restarting animations.
bpy.context.view_layer.objects.active=head
sub=head.modifiers.new('Refined facial topology','SUBSURF');sub.levels=1
bpy.ops.object.modifier_apply(modifier=sub.name)
head.shape_key_add(name='Basis');jaw=head.shape_key_add(name='Jaw open');blink=head.shape_key_add(name='Blink')
sculpt_verts=[(v.co.x/1.18,v.co.z+7.25,.5-v.co.y) for v in head.data.vertices]
for i,(x,h,d) in enumerate(sculpt_verts):
 front=max(0,min(1,(d-.7)/.6));w=max(0,min(1,(6.63-h)/.06))*front
 if h<6.63 and abs(x)<.72:jaw.data[i].co.z-=.19*w
 for side in [-1,1]:
  dx=(x-side*.30775)/.255;dz=(h-7.28415)/.15
  if abs(dx)<1.15 and abs(dz)<1.5 and d>1.12:
   weight=math.exp(-(dx/.95)**4)*max(0,1-abs(dz)/1.6)
   blink.data[i].co.z+=(7.28415-h)*weight*.98
   blink.data[i].co.y-=.025*weight
# Subdivision was applied before adding morphs: exported lips/eyelids remain articulated.
# glTF exports the subdivided base and morphs, keeping the mobile mesh compact.

for side,name in [(-1,'R'),(1,'L')]:
 ex=side*.30775*1.16;ez=7.28415-7.25;ey=-(1.24535-.5)
 sphere('Eyeball '+name,(ex,ey,ez),(.175,.175,.175),white)
 sphere('Iris '+name,(ex,ey-.170,ez),(.072,.014,.074),iris,48,24)
 sphere('Pupil '+name,(ex,ey-.183,ez),(.029,.007,.030),pupil,32,20)
 sphere('Catchlight '+name,(ex-.020,ey-.190,ez+.026),(.009,.005,.010),catch,20,12)
 # Fine iris fibers and eyebrow hairs add definition without photo textures.
 curve('Soft brow '+name,[(ex-.18,-.968,.30),(ex,-1.0,.355),(ex+.18,-.968,.32)],.013,browmat)
 for j in range(48):
  a=j*math.tau/48;r=.044+random.random()*.012
  c=iris
  curve('Iris ray '+name+str(j),[(ex+r*math.cos(a),ey-.185,ez+r*math.sin(a)),(ex+.067*math.cos(a),ey-.177,ez+.069*math.sin(a))],.0009,c)
 for j in range(0):
  q=j/33;xx=ex+(.39*q-.195);zz=.29+.07*math.sin(math.pi*q)
  yy=-.99+.07*abs(q-.5)
  curve('Brow '+name+str(j),[(xx,yy,zz),(xx+side*.014,yy-.008,zz+.027)],.0035,browmat)
# A continuous hair cap, fitted to the anatomical skull. No helmet/seams/LEDs.
scalp=[]
for f in faces:
 c=[sum(verts[i][j] for i in f)/len(f) for j in range(3)];x,h,d=c
 hairline=7.83-.22*min(1,abs(x)/.7)
 if h>hairline:scalp.append(f)
ids=sorted({i for f in scalp for i in f});index={old:i for i,old in enumerate(ids)};points=[]
for i in ids:
 x,y,z=transform(verts[i]);top=max(0,(z-.35)/1.0)
 x*=1.006;y=(y+.35)*1.008-.35;z+=.012+.018*top
 # Trim the sampled hair boundary to a continuous hairline.
 cutoff=7.83-.22*min(1,abs(verts[i][0])/.7)
 if verts[i][2]>.45 and verts[i][1]<cutoff:z=max(z,cutoff-7.25)
 points.append((x,y,z))
hm=bpy.data.meshes.new('Hair cap');hm.from_pydata(points,[],[[index[i] for i in f] for f in scalp]);hm.update()
ho=bpy.data.objects.new('Soft swept hair',hm);bpy.context.collection.objects.link(ho);ho.data.materials.append(hairmat);smooth(ho)
hsub=ho.modifiers.new('Hair smoothing','SUBSURF');hsub.levels=1
bpy.context.view_layer.objects.active=ho;bpy.ops.object.modifier_apply(modifier=hsub.name)
texture=bpy.data.textures.new('Fine cropped hair texture',type='CLOUDS');texture.noise_scale=.018;texture.noise_depth=1
displace=ho.modifiers.new('Soft cropped hair detail','DISPLACE');displace.texture=texture;displace.strength=.006;displace.mid_level=.5
bpy.ops.object.modifier_apply(modifier=displace.name)
mouth=sphere('Mouth interior',(0,-.85,-.64),(.235,.03,.022),oral)
mouth.shape_key_add(name='Basis');mk=mouth.shape_key_add(name='Jaw open')
for p in mk.data:p.co.z=p.co.z*4-.045
# Rounded individual teeth on two curved arches, plus a sculpted tongue.
for lower in [False,True]:
 for j in range(10):
  angle=(j-4.5)*.14;xx=.32*math.sin(angle);yy=(-.94 if lower else -1.00)+.22*(math.sin(angle)/math.sin(.7))**2
  zz=-.715 if lower else -.67
  bpy.ops.mesh.primitive_cube_add(size=1,location=(xx,yy,zz))
  tooth=bpy.context.object;tooth.name=('Lower' if lower else 'Upper')+' tooth '+str(j)
  tooth.scale=(.043,.045,.049 if not lower else .038);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
  tooth.data.materials.append(teeth);bevel=tooth.modifiers.new('Rounded enamel','BEVEL');bevel.width=.009;bevel.segments=3
  bpy.context.view_layer.objects.active=tooth;bpy.ops.object.modifier_apply(modifier=bevel.name);smooth(tooth)
  if lower:
   tooth.shape_key_add(name='Basis');key=tooth.shape_key_add(name='Jaw open')
   for v in key.data:v.co.z-=.05
 tongue=sphere('Tongue',(0,-.91,-.735),(.15,.07,.03),mat('Tongue rose',(.34,.105,.105),.48)) if lower else None
 if tongue:
  tongue.shape_key_add(name='Basis');key=tongue.shape_key_add(name='Jaw open')
  for v in key.data:v.co.z-=.03

sphere('Navy neckline',(0,-.30,-1.40),(.90,.75,.35),shirt)

groups={}
for o in list(bpy.context.scene.objects):
 if o.type=='MESH' and not o.data.shape_keys and len(o.data.materials)==1:
  groups.setdefault(o.data.materials[0].name,[]).append(o)
for objects in groups.values():
 if len(objects)<2:continue
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
avatar=[o for o in bpy.context.scene.objects if o.type=='MESH']
scene=bpy.context.scene;scene.frame_start=1;scene.frame_end=28;scene.render.fps=24
for o in avatar:
 if not o.data.shape_keys:continue
 keys=o.data.shape_keys
 for name,values in [('Jaw open',[(1,0),(13,1),(25,0),(26,0),(28,0)]),('Blink',[(1,0),(25,0),(26,1),(28,0)])]:
  key=keys.key_blocks.get(name)
  if key:
   for frame,value in values:key.value=value;key.keyframe_insert(data_path='value',frame=frame)
 if keys.animation_data:
  action=keys.animation_data.action;track=keys.animation_data.nla_tracks.new();track.name='MimoPerformance';track.strips.new('MimoPerformance',1,action);keys.animation_data.action=None
scene.frame_set(1)
for o in scene.objects:o.select_set(o in avatar)
bpy.ops.export_scene.gltf(filepath=str(out/'mimo-head.glb'),export_format='GLB',use_selection=True,export_morph=True,export_animations=True,export_apply=False)
if '--export-only' in args:print('MIMO_AVATAR_EXPORTED',str(out));sys.exit(0)
scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=True
scene.render.resolution_x=800;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.025,.033,.05,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35

def area(name,loc,energy,color,size):
 data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.color=color;data.shape='DISK';data.size=size
 o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,-.4,0))-o.location).to_track_quat('-Z','Y').to_euler()
area('Large soft key',(-3,-4,4),520,(1,.86,.74),4)
area('Soft fill',(3,-3,1),260,(.75,.86,1),3)
area('Hair rim',(1,2,3),650,(.65,.82,1),3)
bpy.ops.object.camera_add(location=(.10,-7.0,.1));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.35,-.12))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=3.6;scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(out/'mimo-head.blend'))
scene.render.filepath=str(out/'mimo-portrait.png');bpy.ops.render.render(write_still=True)
scene.frame_set(13);scene.render.filepath=str(out/'mimo-speaking.png');bpy.ops.render.render(write_still=True)
print('MIMO_AVATAR_READY',str(out))
