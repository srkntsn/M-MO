"""MIMO mobile digital human: CC0 Vitruvian topology, PBR maps and FACS.
Assets are pinned and checksum-verified by fetch_avatar_sources.py first.
The Cycles previews use the same exported glTF materials and facial geometry.
"""
import bpy,sys,math,bmesh,random
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
out=Path(args[args.index('--output')+1] if '--output' in args else 'avatar-build').resolve();out.mkdir(parents=True,exist_ok=True)
root=Path(__file__).resolve().parents[1]/'assets/source/vitruvian'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(root/'vitruvian_head.glb'))
# Replace Godot-specific placeholder materials with portable glTF PBR materials.
def image(name,noncolor=False,size=1024):
 im=bpy.data.images.load(str(root/name),check_existing=True)
 if noncolor:im.colorspace_settings.name='Non-Color'
 if max(im.size)>size:im.scale(size,size)
 # Save optimized files even when the input already has the requested size:
 # otherwise Blender's glTF exporter reuses the original large PNG byte stream.
 cache=out/'textures';cache.mkdir(exist_ok=True)
 lossless=noncolor or 'opacity' in name or 'hair' in name
 im.file_format='PNG' if lossless else 'JPEG'
 im.filepath_raw=str(cache/(Path(name).stem+('.png' if lossless else '.jpg')))
 im.save();im.reload()
 return im
def material(name,color,rough=.5):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();p=n.new('ShaderNodeBsdfPrincipled');o=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(p.outputs['BSDF'],o.inputs['Surface']);p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough
 return m,p

def tex(m,p,file,target,noncolor=False,size=1024):
 n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=image(file,noncolor,size);m.node_tree.links.new(n.outputs['Color'],p.inputs[target]);return n
skin,p=material('MIMO PBR skin',(.4,.25,.19),.6)
tex(skin,p,'vit_face_bc.png','Base Color',size=1536)
tex(skin,p,'vit_face_rough.png','Roughness',True,512)
n=skin.node_tree.nodes.new('ShaderNodeTexImage');n.image=image('vit_face_n.png',True,1024);normal=skin.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.35;skin.node_tree.links.new(n.outputs['Color'],normal.inputs['Color']);skin.node_tree.links.new(normal.outputs['Normal'],p.inputs['Normal'])
p.inputs['Subsurface Weight'].default_value=.06
mouth,p=material('MIMO anatomical mouth',(.3,.08,.08),.48);tex(mouth,p,'vit_mouth.png','Base Color')
sclera,p=material('MIMO sclera',(.7,.71,.68),.3);tex(sclera,p,'vit_sclera.png','Base Color')
iris,p=material('MIMO iris',(.12,.18,.1),.52);p.inputs['Specular IOR Level'].default_value=.05;it=tex(iris,p,'vit_iris.png','Base Color');mix=iris.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(.4,.4,.4,1);iris.node_tree.links.new(it.outputs['Color'],mix.inputs[1]);iris.node_tree.links.new(mix.outputs['Color'],p.inputs['Base Color'])
pupil,p=material('MIMO pupil',(.001,.001,.001),.22)
wet,p=material('MIMO wet eye rim',(.3,.12,.1),.24)
# An opaque cornea would hide the iris on mobile. Use the anatomical iris/sclera
# with their own highlights instead of a fragile transparent outer shell.
for o in list(bpy.context.scene.objects):
 if o.type!='MESH':continue
 if 'Eyeshadow' in o.name:bpy.data.objects.remove(o,do_unlink=True);continue
 mats=list(o.data.materials)
 for i,m in enumerate(mats):
  name=m.name
  replacement=skin if name.startswith('VitSkin') else mouth if name.startswith('VitMouth') else sclera if name.startswith('VitSclera') else iris if name.startswith('VitIris') else pupil if name.startswith('VitEyeBack') else wet
  o.data.materials[i]=replacement
  if name.startswith('VitCornea'):
   bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index==i],context='FACES');bm.to_mesh(o.data);bm.free()
 # Bring the textured iris just ahead of the sclera surface. The source
 # uses a Godot-specific eye shader that is not present in the glTF runtime.
 if 'eyeball' in o.name:
  iris_vertices={v for f in o.data.polygons if f.material_index==1 for v in f.vertices}
  for idx in iris_vertices:o.data.vertices[idx].co.y-=.0055
 # UV is UDIM in the source. glTF repeat wraps each face/mouth tile correctly.
 for poly in o.data.polygons:poly.use_smooth=True
head=bpy.data.objects['cm_vitruvian'];head.name='MIMO articulated human head'
keys=head.data.shape_keys
# Keep independent jaw, lip seal, blink and warm smile; drop unused shapes to
# reduce GPU memory and animation channels on mid-range Android phones.
keep={'Basis','Mouth_Large_Opened','Eyes_Closed_Max','Smile_Lips_Closed','p_b_m_21'}
for k in list(keys.key_blocks):
 if k.name not in keep:head.shape_key_remove(k)
for k in keys.key_blocks:k.value=0
# Source neutral expression has a slightly parted mouth. Close it gently.
keys.key_blocks['Smile_Lips_Closed'].value=.2
# A geometric short groom avoids alpha-card sorting artifacts in mobile WebViews.
# Fine curved strands sit over a scalp fitted to the anatomical mesh.
random.seed(71)
hm,p=material('MIMO soft dark hair',(.009,.005,.003),.86)
p.inputs['Specular IOR Level'].default_value=0
bm=bmesh.new();bm.from_mesh(head.data)
remove=[]
for f in bm.faces:
 c=f.calc_center_median();cut=1.72 if c.y<.02 else 1.685
 if c.z<cut:remove.append(f)
bmesh.ops.delete(bm,geom=remove,context='FACES');scalpmesh=bpy.data.meshes.new('Fitted scalp');bm.to_mesh(scalpmesh);bm.free()
scalp=bpy.data.objects.new('MIMO cropped hair base',scalpmesh);scene_collection=bpy.context.collection;scene_collection.objects.link(scalp);scalpmesh.materials.append(hm)
for v in scalpmesh.vertices:v.co+=v.normal*.0012
for poly in scalpmesh.polygons:poly.use_smooth=True
bpy.ops.object.select_all(action='DESELECT');scalp.select_set(True);bpy.context.view_layer.objects.active=scalp
sub=scalp.modifiers.new('Soft hairline','SUBSURF');sub.levels=2;bpy.ops.object.modifier_apply(modifier=sub.name)
surface=BVHTree.FromPolygons([v.co for v in head.data.vertices],[list(f.vertices) for f in head.data.polygons])
roots=[v.co.copy() for v in scalpmesh.vertices]
strands=bpy.data.curves.new('Fine swept strands','CURVE');strands.dimensions='3D';strands.bevel_depth=.00032;strands.bevel_resolution=1;strands.resolution_u=3
for i in range(1400):
 root=random.choice(roots);length=random.uniform(.012,.028)
 tangent=Vector((-.25*length,length,0))
 spline=strands.splines.new('BEZIER');spline.bezier_points.add(4)
 for j,pt in enumerate(spline.bezier_points):
  t=j/4;point,normal,_,_=surface.find_nearest(root+tangent*t)
  pt.co=point+normal*(.0015+.0018*math.sin(t*math.pi))
  pt.radius=1-.8*t;pt.handle_left_type='AUTO';pt.handle_right_type='AUTO'
groom=bpy.data.objects.new('MIMO individual swept hairs',strands);scene_collection.objects.link(groom);strands.materials.append(hm)
bpy.ops.object.select_all(action='DESELECT');groom.select_set(True);bpy.context.view_layer.objects.active=groom;bpy.ops.object.convert(target='MESH')
# Fine anatomical eyebrow hairs rather than painted bars.
for side in [-1,1]:
 data=bpy.data.curves.new('Natural brow','CURVE');data.dimensions='3D';data.bevel_depth=.00019;data.bevel_resolution=1;data.resolution_u=2
 for i in range(65):
  q=i/64;x=side*(.013+.042*q);z=1.650+.005*math.sin(q*math.pi)
  sp=data.splines.new('BEZIER');sp.bezier_points.add(1)
  for pt,co in zip(sp.bezier_points,[(x,-.08,z),(x+side*.0015,-.08,z+.003)]):
   point,normal,_,_=surface.find_nearest(Vector(co));pt.co=point+normal*.0006;pt.handle_left_type='AUTO';pt.handle_right_type='AUTO'
 obj=bpy.data.objects.new('MIMO eyebrow',data);scene_collection.objects.link(obj);data.materials.append(hm);bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj;bpy.ops.object.convert(target='MESH')
# The head-only silhouette ends under the jaw; frame it without a floating
# shoulder blob or a second fake neck.
scene=bpy.context.scene;scene.frame_start=1;scene.frame_end=28;scene.render.fps=24
for o in scene.objects:
 if o.type!='MESH':continue
 o.animation_data_clear()
 if o.data.shape_keys:o.data.shape_keys.animation_data_clear()
 if o.data.shape_keys:
  keydata=o.data.shape_keys
  for name,values in [('Mouth_Large_Opened',[(1,0),(13,.65),(25,0),(26,0),(28,0)]),('Eyes_Closed_Max',[(1,0),(25,0),(26,1),(28,0)]),('Smile_Lips_Closed',[(1,.2),(28,.2)])]:
   k=keydata.key_blocks.get(name)
   if k:
    for f,value in values:k.value=value;k.keyframe_insert(data_path='value',frame=f)
  if keydata.animation_data:
   action=keydata.animation_data.action;track=keydata.animation_data.nla_tracks.new();track.name='MimoPerformance';track.strips.new('MimoPerformance',1,action);keydata.animation_data.action=None
scene.frame_set(1)
# Center the face, broaden modestly; source dimensions are in real-world metres.
for o in list(scene.objects):
 if o.type=='MESH':
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
  o.scale.x*=1.06;o.location.z-=1.62
  bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Remove unused duplicate UV sets from source exports; only the active map is used.
for o in scene.objects:
 if o.type=='MESH':
  while len(o.data.uv_layers)>1:o.data.uv_layers.remove(o.data.uv_layers[-1])
# Images are embedded, so the avatar works offline and has no third-party URL.
for im in bpy.data.images:
 if im.source=='FILE':im.pack()
for o in scene.objects:o.select_set(o.type=='MESH')
bpy.ops.export_scene.gltf(filepath=str(out/'mimo-head.glb'),export_format='GLB',use_selection=True,export_morph=True,export_morph_normal=False,export_animations=True,export_apply=False,export_image_format='AUTO')
if '--export-only' in args:sys.exit(0)
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=640;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.world.use_nodes=True;bg=scene.world.node_tree.nodes['Background'];bg.inputs[0].default_value=(.025,.033,.05,1);bg.inputs[1].default_value=.28

def area(name,loc,power,color,size):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=color;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,.02))-o.location).to_track_quat('-Z','Y').to_euler()
area('Portrait softbox',(-.3,-.4,.4),6,(1,.88,.78),.4)
area('Soft blue fill',(.3,-.3,.1),3,(.80,.89,1),.4)
area('Hair edge',(.2,.2,.3),8,(.75,.86,1),.3)
bpy.ops.object.camera_add(location=(.004,-.65,.025));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-.01,.045))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=.31;scene.camera=cam
scene.view_settings.view_transform='AgX';bpy.ops.wm.save_as_mainfile(filepath=str(out/'mimo-head.blend'))
scene.render.filepath=str(out/'mimo-portrait.png');bpy.ops.render.render(write_still=True)
scene.frame_set(13);scene.render.filepath=str(out/'mimo-speaking.png');bpy.ops.render.render(write_still=True)
print('MIMO_DIGITAL_HUMAN_READY')
