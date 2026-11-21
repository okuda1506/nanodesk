"""Build the A1320 review master in Blender. All design coordinates are in mm."""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
REF = json.loads((ROOT / 'assets/references/ipod_nano_5g_dimensions.json').read_text())
SPEC = REF['measured_or_official']
W, H, D = (SPEC[k] for k in ('width_mm', 'height_mm', 'depth_mm'))
HW, HH = W/2, H/2
# Photo estimates (z is measured from the middle). See docs/MODEL_REVIEW.md.
WHEEL_Z = 19.05 - HH
SCREEN_Z = HH - 28.4
CAM_X = 13.4
LENS_Z = 11.9 - HH
MIC_Z = 18.6 - HH
T = 2 * math.pi
MM = 0.001
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.length_unit = 'MILLIMETERS'
scene.world = bpy.data.worlds.new('Studio world')
model = bpy.data.collections.new('A1320 | Device')
scene.collection.children.link(model)
studio = bpy.data.collections.new('Studio | Review only')
scene.collection.children.link(studio)

def collection(name):
    col = bpy.data.collections.new(name)
    model.children.link(col)
    return col

housing = collection('01 | Enclosure')
display = collection('02 | Display assembly')
controls = collection('03 | Controls and legends')
optics = collection('04 | Optics and microphone')
ends = collection('05 | End fittings')

def finish(name, color, metal, rough, coat=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get('Principled BSDF')
    for prop, value in [('Base Color',(*color,1)), ('Metallic',metal), ('Roughness',rough), ('Coat Weight',coat), ('Coat Roughness',0.12)]:
        bs.inputs[prop].default_value = value
    return mat

silver = finish('Silver | polished anodized aluminum', (.73,.75,.77), .94,.176,.12)
edge = finish('Bright diamond-cut aluminum', (.84,.86,.87), .96,.145)
rim = finish('Satin stainless steel', (.56,.58,.60), .91,.19)
gasket = finish('Joint | dark elastomer', (.014,.016,.018), .0,.53)
black = finish('Mask under cover glass', (.004,.005,.006), .12,.105,.48)
lcd = finish('Screen | inactive polarizer', (.009,.015,.017), .13,.185,.32)
wheel = finish('Graphite | microtextured wheel', (.028,.031,.034), .04,.43)
ink = finish('Wheel legend | warm white', (.80,.81,.80), .04,.37)
cap = finish('Light gray molded end insert', (.55,.56,.55), .06,.34)
gold = finish('Connector | contact plating', (.55,.30,.085), .82,.25)
optic = finish('Camera | coated optical glass', (.019,.027,.041), .30,.11,.55)
iris = finish('Camera | iris', (.003,.005,.007), .10,.23)
amber = finish('Hold | orange indicator', (.90,.135,.022), .05,.39)

def mesh(name, points, faces, material, col, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([tuple(v*MM for v in p) for p in points], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    col.objects.link(obj)
    data.materials.append(material)
    if smooth:
        for f in data.polygons: f.use_smooth = True
    return obj

def group(name, col, parent=None):
    obj = bpy.data.objects.new(name,None)
    col.objects.link(obj)
    obj.empty_display_size = .003
    obj.parent = parent
    return obj

body = group('Body', housing)
def child(obj, parent=body):
    obj.parent = parent
    return obj

def ellipse(rx, ry, n=96, exponent=2.26):
    def term(v): return math.copysign(abs(v)**(2/exponent), v)
    return [(rx*term(math.cos(T*i/n)), ry*term(math.sin(T*i/n))) for i in range(n)]

def shell_loop(z, rx, front, rear):
    return [(x, y*(rear if y>0 else front), z) for x,y in ellipse(rx,1,192)]

def loft(name, loops, mat, col, *, closed=False, caps=False, smooth=True):
    n = len(loops[0])
    pts = [p for loop in loops for p in loop]
    faces = []
    for j in range(len(loops) if closed else len(loops)-1):
        nxt = (j+1)%len(loops)
        for i in range(n):
            k = (i+1)%n
            faces.append((j*n+i,j*n+k,nxt*n+k,nxt*n+i))
    if caps:
        faces += [tuple(reversed(range(n))),tuple(range(len(pts)-n,len(pts)))]
    obj = mesh(name, pts, faces, mat, col, smooth)
    if caps:
        for p in list(obj.data.polygons)[-2:]: p.use_smooth=False
    return obj

# The one continuous extrusion rolls from front to rear without a side seam.
def depth(x, rear=False):
    d = D/2 if rear else D/2-.10
    return d * max(0, 1-abs(x/HW)**2.26)**(1/2.26)

def make_housing():
    outside = [(-HH+.07,.17,.09),(-HH+.10,.09,.04),(-HH+.20,.028,.014),(-HH+.45,0,0),
               (HH-.45,0,0),(HH-.20,.028,.014),(HH-.10,.09,.04),(HH-.07,.17,.09)]
    loops = [shell_loop(z,HW-dx,3.0-dy,3.1-dy) for z,dx,dy in outside]
    # Inner return leaves the end plates and connector cavities physically open.
    loops += [shell_loop(HH,HW-.32,2.82,2.92),shell_loop(HH-.09,HW-.43,2.67,2.77),
              shell_loop(-HH+.09,HW-.43,2.67,2.77),shell_loop(-HH,HW-.32,2.82,2.92)]
    shell = child(loft('AluminumExtrusion',loops,silver,housing,closed=True))
    shell.data.materials.append(edge)
    for face in shell.data.polygons:
        if face.index//192 in (7,8,10,11): face.material_index=1
    for name, pred in [('FrontHousing',lambda y:y<=0),('RearHousing',lambda y:y>=0)]:
        g=shell.vertex_groups.new(name=name)
        g.add([v.index for v in shell.data.vertices if pred(v.co.y)],1,'REPLACE')
    return shell

def roundrect(w,h,r, steps=12):
    corners = [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),(-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]
    return [(cx+r*math.cos(math.radians(start+90*j/steps)), cy+r*math.sin(math.radians(start+90*j/steps)))
            for cx,cy,start in corners for j in range(steps+1)]

def circle(r,n=96):
    return [(r*math.cos(T*i/n),r*math.sin(T*i/n)) for i in range(n)]

def skin_point(x,z,offset,rear):
    return (x,depth(x,rear)+offset if rear else -depth(x)-offset,z)

def medallion(name,cx,cz,profile,mat,col,*,rear=False,parent=body,fill=True):
    # Radial surface with adjustable shoulders, concentric normals and rim.
    loops = [[skin_point(cx+x,cz+z,o,rear) for x,z in contour] for contour,o in profile]
    obj = loft(name,loops,mat,col)
    if fill:
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        c=bm.verts.new(Vector(skin_point(cx,cz,profile[-1][1],rear))*MM)
        n=len(loops[-1]); start=(len(loops)-1)*n
        bm.verts.index_update()
        bm.verts.ensure_lookup_table()
        for i in range(n):
            f=bm.faces.new((bm.verts[start+i],bm.verts[start+(i+1)%n],c))
            f.smooth=True
        bm.to_mesh(obj.data)
        bm.free()
    if rear: obj.data.flip_normals()
    return child(obj,parent)

def screen_patch(name,w,h,r,offset,mat):
    # Aligned columns follow the curved glass. UV (0,0) is front lower left.
    nx, nz = 96, 24
    pts=[]; faces=[]
    for i in range(nx+1):
        x=(i/nx-.5)*w
        dx=max(0,abs(x)-(w/2-r))
        hh=h/2-r+math.sqrt(max(0,r*r-dx*dx))
        for j in range(nz+1):
            z=(2*j/nz-1)*hh
            pts.append(skin_point(x,SCREEN_Z+z,offset,False))
            if i and j:
                a=(i-1)*(nz+1)+j-1
                faces.append((a,a+nz+1,a+nz+2,a+1))
    o=child(mesh(name,pts,faces,mat,display,True))
    uv=o.data.uv_layers.new(name='ScreenUV')
    for loop in o.data.loops:
        x,_,z=pts[loop.vertex_index]
        uv.data[loop.index].uv=(x/w+.5,(z-SCREEN_Z)/h+.5)
    return o

def screen():
    screen_patch('DisplaySeal',34.8,52.1,1.25,.024,gasket)
    screen_patch('ScreenBezel',34.55,51.85,1.15,.069,black)
    ratio=240/376
    sh=25.4*SPEC['display_diagonal_in']/math.sqrt(1+ratio*ratio)
    return screen_patch('ScreenSurface',sh*ratio,sh,.14,.10,lcd)

def wheel_assembly():
    # A physically separate center and continuous ring; the four sectors share
    # boundary coordinates and shading with the annulus, for directional hits.
    p=REF['engineering_drawing_values_pending_visual_crosscheck']
    R=p['click_wheel_outer_diameter_mm']/2
    r=p['center_button_diameter_mm']/2
    medallion('WheelSeat',0,WHEEL_Z,[(circle(R+.14),.017),(circle(R+.1),.032),(circle(R-.2),.031)],gasket,controls,fill=False)
    chassis=group('WheelRing',controls,body)
    for index,name in enumerate(('NextButton','MenuButton','PreviousButton','PlayPauseButton')):
        # x-z polar angles are measured from right, counterclockwise.
        radii=[(R,.031),(R-.07,.063),(R-.17,.075),(r+.18,.075),(r+.09,.053),(r+.07,.025)]
        pts=[]; faces=[]
        for radius,off in radii:
            for j in range(41):
                ang=T*(index/4-.125+j/160)
                pts.append(skin_point(radius*math.cos(ang),WHEEL_Z+radius*math.sin(ang),off,False))
        for k in range(len(radii)-1):
            for j in range(40):
                a=k*41+j
                faces.append((a,a+1,a+42,a+41))
        child(mesh(name,pts,faces,wheel,controls,True),chassis)
    medallion('CenterButtonJoint',0,WHEEL_Z,[(circle(r+.12),.028),(circle(r-.06),.029)],gasket,controls,fill=False)
    # A shallow dished metal key; subdivisions preserve the crown of the case.
    medallion('CenterButton',0,WHEEL_Z,[(circle(r),.032),(circle(r-.10),.081),
              (circle(r-.23),.075),(circle(r*.73),.051),(circle(r*.38),.039),(circle(r*.13),.038)],silver,controls)
    glyphs={
        'M':[[(0,0),(0,1),(.36,.36),(.72,1),(.72,0)]],
        'E':[[(.64,0),(0,0),(0,1),(.64,1)],[(0,.51),(.52,.51)]],
        'N':[[(0,0),(0,1),(.67,0),(.67,1)]],
        'U':[[(0,1),(0,.25),(.08,.07),(.23,0),(.45,0),(.59,.07),(.66,.25),(.66,1)]]}
    # Original vector strokes. No external font or image textures.
    scale=1.35
    points=[]; faces=[]
    def symbol(poly):
        start=len(points)
        points.extend(skin_point(x,WHEEL_Z+z,.092,False) for x,z in poly)
        area=sum(a*d-b*c for (a,b),(c,d) in zip(poly,poly[1:]+poly[:1]))
        inds=tuple(range(start,len(points)))
        faces.append(inds if area>0 else inds[::-1])
    for n,letter in enumerate('MENU'):
        for line in glyphs[letter]:
            for (x,z),(xx,zz) in zip(line,line[1:]):
                a=Vector(((n*.99+x-1.83)*scale,10.7+(z-.5)*scale))
                b=Vector(((n*.99+xx-1.83)*scale,10.7+(zz-.5)*scale))
                direction=(b-a).normalized(); normal=Vector((-direction.y,direction.x))*.112
                a-=direction*.08; b+=direction*.08
                symbol([tuple(a+normal),tuple(b+normal),tuple(b-normal),tuple(a-normal)])
    for sign in (-1,1):
        for k in (-.56,.54):
            symbol([(sign*(10.15+k+u),z) for u,z in [(-.55,-.69),(.49,0),(-.55,.69)]])
        symbol([(sign*(11.53+u),z) for u,z in [(-.16,-.70),(.16,-.70),(.16,.70),(-.16,.70)]])
    symbol([(-1.64,-11.18),(-.44,-10.49),(-1.64,-9.8)])
    for x in (.16,.92):symbol([(x,-11.15),(x+.32,-11.15),(x+.32,-9.84),(x,-9.84)])
    child(mesh('WheelLegends',points,faces,ink,controls),chassis)

def camera_assembly():
    cz=(LENS_Z+MIC_Z)/2
    def plate(name,w,h,off,mat):
        # Stretched capsule follows rear crown. Dense horizontal sampling
        # avoids a flat tangent-plane patch crossing the curved extrusion.
        template=roundrect(w,h,w/2-.01)
        prof=[(template,off-.024), ([(x*.985,z*.995) for x,z in template],off)]
        for s in (.8,.6,.4,.2):
            prof.append(([(x*s,z*s) for x,z in template],off))
        return medallion(name,CAM_X,cz,prof,mat,optics,rear=True)
    plate('CameraSeat',4.94,11.82,.055,gasket)
    plate('RearCamera',4.72,11.58,.105,edge)
    def disk(name,z,rs,mat):
        return medallion(name,CAM_X,z,[(circle(r,72),o) for r,o in rs],mat,optics,rear=True)
    disk('LensRetainer',LENS_Z,[(1.68,.124),(1.60,.153),(1.50,.147)],rim)
    disk('LensGlass',LENS_Z,[(1.54,.153),(1.40,.184),(.99,.194),(.45,.196)],optic)
    disk('LensPupil',LENS_Z,[(.42,.199),(.34,.207),(.17,.21)],iris)
    disk('MicChamfer',MIC_Z,[(.46,.130),(.36,.155),(.27,.143)],rim)
    disk('Microphone',MIC_Z,[(.275,.151),(.220,.156)],iris)

def end_prism(name,outline,z1,z2,mat):
    return loft(name,[[(x,y,z) for x,y in outline] for z in (z1,z2)],mat,ends,caps=True,smooth=False)
def shifted(outline,dx,dy=0):
    return [(x+dx,y+dy) for x,y in outline]
def perforate(obj,outline):
    z = obj.data.vertices[0].co.z/MM
    tool=end_prism('Temporary aperture',outline,z-3,z+3,gasket)
    mod=obj.modifiers.new('Open machined aperture','BOOLEAN')
    mod.operation='DIFFERENCE'; mod.object=tool
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(tool,do_unlink=True)

def end_parts():
    outline=ellipse(HW-.33,2.84,192)
    bottom=child(end_prism('LowerEndPlate',outline,-HH+.08,-HH+.48,cap))
    top=child(end_prism('UpperEndPlate',outline,HH-.58,HH-.24,cap))
    dock_x=3.95; jack_x=-12.
    dock=shifted(roundrect(21.55,2.96,.54),dock_x)
    jack=shifted(circle(1.79),jack_x)
    slot=shifted(roundrect(8.8,2.08,1.0),-8.15)
    perforate(bottom,dock); perforate(bottom,jack); perforate(top,slot)
    def sleeve(name,sections,mat):
        loops=[[(x,y,z) for x,y in outline] for outline,z in sections]
        lining = loft(name,loops,mat,ends)
        lining.data.flip_normals()
        return child(lining)
    sleeve('DockConnector',[(dock,-HH+.10),(shifted(roundrect(21.30,2.72,.46),dock_x),-HH+.22),
           (shifted(roundrect(21.12,2.55,.45),dock_x),-HH+2.52)],rim)
    child(end_prism('DockCavityBack',dock,-HH+2.50,-HH+2.70,gasket))
    blade=shifted(roundrect(19.4,.66,.19),dock_x,.07)
    child(end_prism('DockContactCarrier',blade,-HH+.75,-HH+2.56,gasket))
    for i in range(30):
        pin=shifted(roundrect(.26,.11,.036,3),dock_x+(i-14.5)*.61,-.265)
        child(end_prism(f'DockContact_{i+1:02}',pin,-HH+.80,-HH+1.74,gold))
    sleeve('HeadphoneJack',[(jack,-HH+.075),(shifted(circle(1.71),jack_x),-HH+.19),
           (shifted(circle(1.66),jack_x),-HH+3.32)],rim)
    sleeve('JackInnerLiner',[(shifted(circle(1.66),jack_x),-HH+.47),
           (shifted(circle(1.56),jack_x),-HH+.52),(shifted(circle(1.56),jack_x),-HH+3.36)],gasket)
    child(end_prism('JackCavityBack',jack,-HH+3.34,-HH+3.49,iris))
    child(end_prism('HoldSwitchWell',slot,HH-.86,HH-.64,gasket))
    child(end_prism('HoldIndicator',shifted(roundrect(2.4,1.68,.72),-11.03),HH-.64,HH-.55,amber))
    slider=shifted(roundrect(6.82,1.79,.78),-7.44)
    sec=[(slider,HH-.62),(slider,HH-.14),(shifted(roundrect(6.66,1.63,.72),-7.44),HH-.04)]
    loops=[[(x,y,z) for x,y in cont] for cont,z in sec]
    child(loft('HoldSwitch',loops,cap,ends,caps=True))

make_housing()
screen()
wheel_assembly()
camera_assembly()
end_parts()
bpy.context.view_layer.update()

def validate():
    vertices=[o.matrix_world@v.co for o in model.all_objects if o.type=='MESH' for v in o.data.vertices]
    dims=[(max(v[i] for v in vertices)-min(v[i] for v in vertices))/MM for i in range(3)]
    assert max(abs(a-b) for a,b in zip(dims,(W,D,H)))<.01, dims
    for o in model.all_objects:
        if o.type=='MESH':
            assert not o.data.validate(verbose=True), o.name
    print('MODEL_BOUNDS_MM', [round(x,4) for x in dims])
validate()

def aim(obj, position, target):
    obj.location = Vector(position)*MM
    obj.rotation_euler = (Vector(target)*MM-obj.location).to_track_quat('-Z','Y').to_euler()

def reflection_studio(tree, background):
    # An original procedural equirectangular studio. Long luminous panels and
    # dark flags give the shallow hull readable gradients through rotation.
    import numpy as np
    width, height = 768, 384
    latitude = (np.arange(height)[:, None] + .5) * 180/height - 90
    longitude = (np.arange(width)[None, :] + .5) * 360/width - 180
    rgb = np.zeros((height, width, 3), dtype=np.float32) + (.075,.088,.105)
    panels = [
        (-72, 23, 20, 46, (1.28,1.28,1.26)),
        (-135, 4, 9, 61, (2.9,3.0,3.15)),
        (-16, 5, 14, 64, (.95,1.04,1.13)),
        (47, 16, 18, 52, (1.85,1.89,1.92)),
        (124, -11, 21, 56, (1.25,1.20,1.12)),
        (170, 15, 6, 49, (2.8,2.85,2.9)),
        (0, 77, 175, 16, (1.65,1.60,1.50)),
        (0, -75, 160, 13, (.72,.74,.78)),
    ]
    for az, el, sx, sy, color in panels:
        tilt = .26 if az in (-72, 47, 124) else -.09
        delta = (longitude - az - tilt*latitude + 180) % 360 - 180
        lobe = np.exp(-.5*((delta/sx)**4 + ((latitude-el)/sy)**4))
        rgb += lobe[:, :, None] * color
    rgba = np.ones((height, width, 4),dtype=np.float32)
    rgba[:,:,:3] = rgb
    img = bpy.data.images.new('Procedural studio | original',width,height,float_buffer=True)
    img.colorspace_settings.name='Non-Color'
    img.pixels.foreach_set(rgba.ravel()); img.pack()
    env = tree.nodes.new('ShaderNodeTexEnvironment')
    env.image = img
    tree.links.new(env.outputs[0],background.inputs[0])
    background.inputs[1].default_value=.83

def set_studio():
    world=scene.world
    world.use_nodes=True
    tree=world.node_tree
    bg=tree.nodes.get('Background')
    bg.inputs[0].default_value=(.34,.36,.40,1); bg.inputs[1].default_value=.44
    # Neutral studio background, with a slightly cooler edge than the metal.
    back=tree.nodes.new('ShaderNodeBackground')
    back.inputs[0].default_value=(.037,.047,.063,1)
    mix=tree.nodes.new('ShaderNodeMixShader'); ray=tree.nodes.new('ShaderNodeLightPath')
    tree.links.new(ray.outputs['Is Camera Ray'],mix.inputs[0])
    tree.links.new(bg.outputs[0],mix.inputs[1]); tree.links.new(back.outputs[0],mix.inputs[2])
    tree.links.new(mix.outputs[0],tree.nodes.get('World Output').inputs['Surface'])
    reflection_studio(tree,bg)
    cam=bpy.data.cameras.new('Review lens'); cam.clip_start=.001; cam.clip_end=2
    obj=bpy.data.objects.new('ReviewCamera',cam); studio.objects.link(obj); scene.camera=obj
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'; scene.cycles.samples=256
    scene.cycles.adaptive_threshold=.015
    scene.cycles.use_denoising=False
    scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='AgX'
    scene.render.film_transparent=False
    scene.render.resolution_percentage=100
    scene.render.threads_mode='FIXED'; scene.render.threads=4

# position, look-at, longest frame dimension in mm, canvas, perspective lens
VIEWS={
    'front': ((0,-210,0),(0,0,0),103,(560,1100),None),
    'back': ((0,210,0),(0,0,0),103,(560,1100),None),
    'left': ((-210,0,0),(0,0,0),103,(350,1100),None),
    'right': ((210,0,0),(0,0,0),103,(350,1100),None),
    'top': ((0,0,210),(0,0,0),45,(1000,300),None),
    'bottom': ((0,0,-210),(0,0,0),45,(1000,300),None),
    'front_45': ((-135,-135,52),(0,0,0),104,(640,1100),67),
    'back_45': ((132,132,-46),(0,0,-1),104,(640,1100),66),
    'camera_detail': ((42,57,-11),(13,1.5,-30.1),22,(880,720),None),
    'dock_detail': ((-17,-35,-116),(0,0,-44),47,(1050,430),None),
}

def view(name):
    pos,target,scale,res,lens=VIEWS[name]
    cam=scene.camera; aim(cam,pos,target)
    if name in ('top','bottom'):
        # Positive x always reads right, even when looking straight down/up.
        cam.rotation_euler=(0,0,0) if name=='top' else (math.pi,0,0)
    cam.data.type='PERSP' if lens else 'ORTHO'
    if lens: cam.data.lens=lens
    cam.data.ortho_scale=scale*MM
    scene.render.resolution_x,scene.render.resolution_y=res

def frame_workspace():
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            space.clip_start=.0001; space.clip_end=2
            space.region_3d.view_distance=.15
            space.region_3d.view_rotation=scene.camera.rotation_euler.to_quaternion()
            space.region_3d.view_perspective='ORTHO'
            space.overlay.show_overlays=False
            space.shading.color_type='MATERIAL'
    for o in studio.objects:
        o.hide_set(True)

set_studio()
view('front_45')
frame_workspace()
bpy.context.view_layer.objects.active=body
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
if '--' in sys.argv:
    args=sys.argv[sys.argv.index('--')+1:]
else:
    args=[]
def write_mesh_exchange(path):
    # Ship only device geometry. Coordinates and smooth corner normals are
    # already evaluated here; USD conversion needs no Blender or GPU plugins.
    packed=[]
    for o in sorted(model.all_objects,key=lambda o:o.name):
        rec={'name':o.name,'parent':o.parent.name if o.parent else None}
        if o.type=='MESH':
            m=o.data
            rec.update(points=[list(v.co) for v in m.vertices],
                       counts=[len(f.vertices) for f in m.polygons],
                       indices=[v.vertex_index for v in m.loops],
                       normals=[list(n.vector) for n in m.corner_normals],
                       materials=[mat.name for mat in m.materials],
                       slots=[p.material_index for p in m.polygons])
            if m.uv_layers.active:
                rec['uv']=[list(p.uv) for p in m.uv_layers.active.data]
        packed.append(rec)
    materials={}
    for m in bpy.data.materials:
        if m.use_nodes and (bs:=m.node_tree.nodes.get('Principled BSDF')):
            materials[m.name]=[list(bs.inputs['Base Color'].default_value)[:3],
                               bs.inputs['Metallic'].default_value,bs.inputs['Roughness'].default_value,
                               bs.inputs['Coat Weight'].default_value,bs.inputs['Coat Roughness'].default_value]
    Path(path).write_text(json.dumps({'objects':packed,'materials':materials}))
if '--exchange' in args:
    write_mesh_exchange(args[args.index('--exchange')+1])
if '--preview' in args:
    output=Path('/tmp/nanodesk-preview')
    names=args[args.index('--preview')+1:]
    quality=43
    scene.cycles.samples=32
else:
    output=ROOT/'assets/renders'
    names=VIEWS
    quality=100
    (ROOT/'assets/source').mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'assets/source/ipod_nano_5g.blend'),compress=True)
output.mkdir(parents=True,exist_ok=True)
for name in names:
    view(name); scene.render.resolution_percentage=quality
    scene.render.filepath=str(output/(name+'.png'))
    bpy.ops.render.render(write_still=True)
