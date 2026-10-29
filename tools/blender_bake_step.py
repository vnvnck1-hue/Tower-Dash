"""Blender example for the 80.lv "structural texturing" workflow on one Tower Dash stair module.

  blender -b --factory-startup --python tools/blender_bake_step.py -- --out screenshots/trim

Builds ONE stair step (tread 1.35 x 3.2, slab 2.2 deep) the way the article builds its five-step
stair sculpt: a hi-poly version (bevelled, noise-displaced, corner chips cut out) and a plain
low-poly box, then bakes hi -> low:
  bake_normal.png   tangent normal map
  bake_ao.png       ambient occlusion
  bake_edge.png     edge/cavity mask (Cycles pointiness) -> the article's "mesh decal edge" mask
and renders a 3-panel comparison (hipoly / lowpoly+bakes / edge mask) plus the mesh-decal demo
(the baked edge strip floating 1.5 cm off a plain box). Blender 4.x / 5.x API.
"""
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = Path(argv[argv.index("--out") + 1]) if "--out" in argv else Path("screenshots/trim")
out = out if out.is_absolute() else Path.cwd() / out   # Blender resolves bare relative paths oddly without a .blend
out = (Path(bpy.path.abspath("//")) / out) if not out.is_absolute() else out
out.mkdir(parents=True, exist_ok=True)
RES = 512
LIT = (0.337, 0.412, 0.604, 1)       # #56699a stair lit
SHADOW = (0.078, 0.110, 0.200, 1)    # #141c33
HI = (0.596, 0.714, 0.976, 1)        # #98b6f9 snow / highlight
INK = (0.0, 0.0, 0.0, 1)

scene = bpy.context.scene
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.cycles.device = "CPU"
scene.render.resolution_x, scene.render.resolution_y = 1600, 700
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
world = bpy.data.worlds.new("W") if scene.world is None else scene.world
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.19, 0.20, 0.23, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

TREAD_W, DEPTH, STEP_H, SLAB = 1.35, 3.2, 0.375, 2.2


def step_block(name, x=0.0):
    """Low-poly step: a box, tread on top at z=0, slab hanging down to -SLAB."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * TREAD_W, v.co.y * DEPTH, (v.co.z - 0.5) * SLAB))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    ob.location = (x, 0, 0)
    return ob


def make_hipoly(low, name):
    hi = low.copy()
    hi.data = low.data.copy()
    hi.name = name
    scene.collection.objects.link(hi)
    # modifier order matters for a clean bake: bevel the clean box, densify it to a grid, THEN cut
    # chips and displace (booleans / displacement on an n-gon fan leave spoke creases in the bake)
    bev = hi.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.07
    bev.segments = 3
    sub = hi.modifiers.new("Sub", "SUBSURF")
    sub.subdivision_type = "SIMPLE"
    sub.levels = sub.render_levels = 4
    # corner chips: boolean-cut small icospheres at the tread corners / lip (article: sculpted chips)
    import random
    random.seed(4)
    cutters = []
    for i in range(7):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=random.uniform(0.05, 0.12))
        c = bpy.context.object
        ex = random.choice((-1, 1)) * TREAD_W * 0.5
        ey = random.uniform(-DEPTH * 0.5, DEPTH * 0.5) if random.random() < 0.6 else DEPTH * 0.5 * random.choice((-1, 1))
        c.location = (hi.location.x + ex, ey, random.uniform(-0.15, 0.02))
        c.hide_render = True
        c.hide_viewport = True
        cutters.append(c)
        b = hi.modifiers.new("Chip%d" % i, "BOOLEAN")
        b.operation = "DIFFERENCE"
        b.object = c
    tex = bpy.data.textures.new("Rock", "CLOUDS")
    tex.noise_scale = 0.6
    tex.noise_depth = 2
    disp = hi.modifiers.new("Disp", "DISPLACE")
    disp.texture = tex
    disp.strength = 0.012
    disp.mid_level = 0.5
    return hi, cutters


def emission_mat(name, color=None, node_builder=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], outn.inputs["Surface"])
    if color is not None:
        em.inputs["Color"].default_value = color
    if node_builder:
        node_builder(nt, em)
    return m


def pointiness_builder(nt, em):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.50
    ramp.color_ramp.elements[1].position = 0.58
    nt.links.new(geo.outputs["Pointiness"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])


def uv_unwrap(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(low, hi, kind, img_name, hi_mat=None):
    img = bpy.data.images.new(img_name, RES, RES, alpha=False)
    img.colorspace_settings.name = "Non-Color" if kind != "EMIT" else "sRGB"
    mat = low.data.materials[0]
    nt = mat.node_tree
    texn = nt.nodes.new("ShaderNodeTexImage")
    texn.image = img
    nt.nodes.active = texn
    if hi_mat is not None:
        hi.data.materials.clear()
        hi.data.materials.append(hi_mat)
    bpy.ops.object.select_all(action="DESELECT")
    hi.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.12
    scene.render.bake.max_ray_distance = 0.3
    scene.render.bake.margin = 8
    if kind == "NORMAL":
        scene.render.bake.normal_space = "TANGENT"
    bpy.ops.object.bake(type=kind)
    img.filepath_raw = str(out / (img_name + ".png"))
    img.file_format = "PNG"
    img.save()
    nt.nodes.remove(texn)
    print("baked", img.filepath_raw)
    return img


# ---------------------------------------------------------------- build + bake
low = step_block("StepLow")
low_mat = bpy.data.materials.new("LowBake")
low_mat.use_nodes = True
low.data.materials.append(low_mat)
uv_unwrap(low)
hi, cutters = make_hipoly(low, "StepHi")
hi_grey = bpy.data.materials.new("HiGrey")
hi_grey.use_nodes = True
hi_grey.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.57, 0.62, 1)
hi.data.materials.append(hi_grey)

img_n = bake(low, hi, "NORMAL", "bake_normal")
img_ao = bake(low, hi, "AO", "bake_ao")

# Edge mask derived from the baked tangent normal: wherever the bevel/chips tilt the normal away
# from +Z the mask lights up. Robust on a flat-faced module (pointiness is noisy there).
import numpy as np
px = np.array(img_n.pixels[:], dtype=np.float32).reshape(RES, RES, 4)
nz = px[:, :, 2] * 2.0 - 1.0
tilt = np.clip((1.0 - nz) * 6.0, 0.0, 1.0)
tilt = np.where(np.abs(px[:, :, 0] - 0.5) + np.abs(px[:, :, 1] - 0.5) < 0.02, 0.0, tilt)   # untouched = no edge
img_edge = bpy.data.images.new("bake_edge", RES, RES, alpha=False)
img_edge.colorspace_settings.name = "Non-Color"
edge_px = np.repeat(tilt[:, :, None], 4, axis=2)
edge_px[:, :, 3] = 1.0
img_edge.pixels[:] = edge_px.ravel().tolist()
img_edge.filepath_raw = str(out / "bake_edge.png")
img_edge.file_format = "PNG"
img_edge.save()
print("edge mask", img_edge.filepath_raw)
# Decal strip texture (the article's "bake the cube edge onto a flat strip"): a slice across one
# island border of the edge mask, mirrored so the edge sits in the middle, stretched 5x.
band = tilt[20:240, 0:6]                                   # ring of the leftmost island (x 1..3)
across = np.concatenate([band[:, ::-1], band], axis=1)
across = np.repeat(across, 10, axis=1)                     # 220 rows (along) x 120 cols (across)
img_strip = bpy.data.images.new("bake_edge_strip", across.shape[1], across.shape[0], alpha=False)
img_strip.colorspace_settings.name = "Non-Color"
sp = np.repeat(across[:, :, None], 4, axis=2)
sp[:, :, 3] = 1.0
img_strip.pixels[:] = sp.ravel().tolist()
img_strip.filepath_raw = str(out / "bake_edge_strip.png")
img_strip.file_format = "PNG"
img_strip.save()
SUN_DIR = Vector((0.55, -0.45, 0.70)).normalized()


# ---------------------------------------------------------------- stylized low-poly material
def stylized(nt, em):
    """Baked normal -> 2-band toon (lit / shadow) + edge mask -> highlight. Like toon_trim.gdshader."""
    nm = nt.nodes.new("ShaderNodeTexImage"); nm.image = img_n; nm.image.colorspace_settings.name = "Non-Color"
    ed = nt.nodes.new("ShaderNodeTexImage"); ed.image = img_edge
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = 1.0
    nt.links.new(nm.outputs["Color"], nmap.inputs["Color"])
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = SUN_DIR
    nt.links.new(nmap.outputs["Normal"], dot.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = SHADOW
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[1].color = LIT
    ramp.color_ramp.elements[1].position = 0.22
    nt.links.new(dot.outputs["Value"], ramp.inputs["Fac"])
    mix_hi = nt.nodes.new("ShaderNodeMixRGB")
    mix_hi.inputs["Color2"].default_value = HI
    nt.links.new(ed.outputs["Color"], mix_hi.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix_hi.inputs["Color1"])
    nt.links.new(mix_hi.outputs["Color"], em.inputs["Color"])


low.data.materials.clear()
low.data.materials.append(emission_mat("LowStylized", node_builder=stylized))
low.location.x = 2.4
hi.location.x = -2.4

# mesh-decal demo: plain box + floating edge strip textured with the baked edge mask
box = step_block("DecalBox", x=6.9)
box.data.materials.append(emission_mat("Flat", LIT))
strip_me = bpy.data.meshes.new("EdgeStrip")
bm = bmesh.new()
uv_lay = bm.loops.layers.uv.new("UVMap")
w = 0.3
for sx in (-1, 1):
    # two planar quads per edge (top flap + side flap) so the texture does not shear across the fold.
    # u = across the fold (edge highlight sits at u 0.5), v = along the edge
    ys = (-DEPTH * 0.5, DEPTH * 0.5)
    inner = [bm.verts.new(Vector((sx * (TREAD_W * 0.5 - w), y, 0.015))) for y in ys]
    fold_t = [bm.verts.new(Vector((sx * (TREAD_W * 0.5 + 0.015), y, 0.015))) for y in ys]
    fold_s = [bm.verts.new(Vector((sx * (TREAD_W * 0.5 + 0.015), y, 0.0))) for y in ys]
    low_v = [bm.verts.new(Vector((sx * (TREAD_W * 0.5 + 0.015), y, -w))) for y in ys]
    for a, b, ua, ub in ((inner, fold_t, 0.0, 0.5), (fold_s, low_v, 0.5, 1.0)):
        f = bm.faces.new([a[0], a[1], b[1], b[0]])
        for loop, uv in zip(f.loops, ((ua, 0), (ua, 1), (ub, 1), (ub, 0))):
            loop[uv_lay].uv = uv
bm.normal_update()
bm.to_mesh(strip_me)
bm.free()
strip = bpy.data.objects.new("EdgeStrip", strip_me)
scene.collection.objects.link(strip)
strip.location = box.location


def strip_mat(nt, em):
    ed = nt.nodes.new("ShaderNodeTexImage"); ed.image = img_strip
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.inputs["Color1"].default_value = LIT
    mix.inputs["Color2"].default_value = HI
    nt.links.new(ed.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(mix.outputs["Color"], em.inputs["Color"])


strip.data.materials.append(emission_mat("Strip", node_builder=strip_mat))

# ---------------------------------------------------------------- render
def label(body, pos, size=0.22):
    d = bpy.data.curves.new(body, "FONT")
    d.body = body
    d.size = size
    d.align_x = "CENTER"
    o = bpy.data.objects.new(body, d)
    scene.collection.objects.link(o)
    o.location = pos
    o.rotation_euler = (1.25, 0, 0)
    d.materials.append(emission_mat("Lbl" + body, (0.92, 0.92, 0.95, 1)))


label("HI-POLY  bevel + noise + chips", (-2.4, -1.9, -2.75), 0.2)
label("LOW-POLY 12 tris + baked normal/edge, 2-band toon", (2.4, -1.9, -2.75), 0.2)
label("MESH DECAL  edge strip 1.5cm off a flat box", (6.9, -1.9, -2.75), 0.2)
bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
sun = bpy.context.object
sun.data.energy = 3.0
sun.rotation_euler = SUN_DIR.to_track_quat("Z", "Y").to_euler()
bpy.ops.object.camera_add(location=(2.25, -12.5, 4.6))
cam = bpy.context.object
look = Vector((2.25, 0.0, -1.1)) - cam.location
cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
cam.data.lens = 32
scene.camera = cam
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(out / "blender_bake_panel.png")
bpy.ops.render.render(write_still=True)
print("BLENDER_PANEL_RENDERED", scene.render.filepath)
bpy.ops.wm.save_as_mainfile(filepath=str(out / "step_bake.blend"))
