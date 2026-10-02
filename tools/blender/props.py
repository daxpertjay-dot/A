"""Builds the lobby props (trees, bushes, rocks, flowers, lamps) in Blender
and exports them for Roblox Studio's 3D Importer.

    python3.11 -m pip install bpy        # Blender as a Python module (once)
    python3.11 tools/blender/props.py    # → assets/models/*.fbx (+ previews)

Every prop is a few meshes, one per colour, named after the colour key the
game paints them with (Config.Lobby.PropColors: Trunk, Leaves, Rock, …),
plus "Outline": a slightly bigger black shell with its faces turned inside
out (the "inverted hull" toon outline). Roblox only draws the side of a
face that points at the camera, so the shell only shows around the edges,
hides behind things like any other geometry, and never doubles up where
props touch.

Coordinates here are Roblox studs, Y up; the feet of each prop are at the
origin. assets/models/LobbyProps.fbx holds every prop (one group each:
Tree, Tree_2, PineTree, …); the per-prop files are there too.
"""

import math
import os
import random
import sys

import bpy  # first: bmesh and mathutils come with it
import bmesh
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")
PREVIEW = os.environ.get("PROPS_PREVIEW")  # a .png path renders a preview line-up

# Preview colours only; the game paints the meshes from Config.Lobby.PropColors.
COLORS = {
    "Trunk": (124, 84, 52),
    "Leaves": (76, 170, 60),
    "LeavesLight": (118, 204, 82),
    "Pine": (40, 120, 70),
    "PineLight": (60, 150, 84),
    "Rock": (146, 146, 160),
    "RockDark": (110, 110, 124),
    "Stem": (70, 150, 60),
    "PetalRed": (240, 70, 80),
    "PetalYellow": (255, 210, 60),
    "PetalPink": (250, 130, 200),
    "PetalBlue": (90, 150, 255),
    "FlowerCenter": (255, 236, 120),
    "Metal": (52, 52, 64),
    "Bulb": (255, 240, 170),
    "Outline": (0, 0, 0),
}


def rbx(x, y, z):
    """Roblox (x, y up, z) → Blender (x, -z, y up)."""
    return Vector((x, -z, y))


class Prop:
    def __init__(self, name, outline=0.15):
        self.name = name
        self.outline = outline
        self.boxes = []  # (colour key, centre, size, yaw/pitch/roll degrees)

    def box(self, color, centre, size, rot=(0, 0, 0)):
        self.boxes.append((color, centre, size, rot))
        return self

    def _matrix(self, centre, size, rot, grow=0.0):
        rx, ry, rz = (math.radians(a) for a in rot)
        # Roblox rotation about X / Y (up) / Z, mapped into Blender axes.
        r = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
        s = Matrix.Diagonal((size[0] + 2 * grow, size[2] + 2 * grow, size[1] + 2 * grow, 1))
        return Matrix.Translation(rbx(*centre)) @ r @ s

    def build(self, collection):
        root = bpy.data.objects.new(self.name, None)
        collection.objects.link(root)
        groups = {}
        for color, centre, size, rot in self.boxes:
            groups.setdefault(color, []).append((centre, size, rot))
        for color, boxes in list(groups.items()) + [("Outline", None)]:
            bm = bmesh.new()
            if color == "Outline":
                for _, centre, size, rot in self.boxes:
                    made = bmesh.ops.create_cube(bm, size=1.0, matrix=self._matrix(centre, size, rot, self.outline))
                    bmesh.ops.reverse_faces(bm, faces=list({f for v in made["verts"] for f in v.link_faces}))
            else:
                for centre, size, rot in boxes:
                    bmesh.ops.create_cube(bm, size=1.0, matrix=self._matrix(centre, size, rot))
            mesh = bpy.data.meshes.new(f"{self.name}_{color}")
            bm.to_mesh(mesh)
            bm.free()
            obj = bpy.data.objects.new(color, mesh)
            obj.data.materials.append(material(color))
            obj.parent = root
            collection.objects.link(obj)
        return root


_materials = {}


def material(color):
    if color in _materials:
        return _materials[color]
    mat = bpy.data.materials.new(color)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    r, g, b = (c / 255 for c in COLORS[color])
    lin = tuple(c ** 2.2 for c in (r, g, b))
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Roughness"].default_value = 0.8
    if color == "Bulb":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 3
    if color == "Outline":
        # Cycles has no backface culling: like Roblox, draw only the faces
        # pointing at the camera. The shell's faces point inward, so only its
        # far side shows, around the prop's edges.
        out = nodes["Material Output"]
        geo = nodes.new("ShaderNodeNewGeometry")
        transparent = nodes.new("ShaderNodeBsdfTransparent")
        black = nodes.new("ShaderNodeEmission")
        black.inputs["Color"].default_value = (0, 0, 0, 1)
        # …and only to the camera: lit from inside the shell, the prop would
        # otherwise sit in its shadow.
        path = nodes.new("ShaderNodeLightPath")
        not_camera = nodes.new("ShaderNodeMath")
        not_camera.operation = "SUBTRACT"
        not_camera.inputs[0].default_value = 1
        links.new(path.outputs["Is Camera Ray"], not_camera.inputs[1])
        hide = nodes.new("ShaderNodeMath")
        hide.operation = "MAXIMUM"
        links.new(geo.outputs["Backfacing"], hide.inputs[0])
        links.new(not_camera.outputs["Value"], hide.inputs[1])
        mix = nodes.new("ShaderNodeMixShader")
        links.new(hide.outputs["Value"], mix.inputs["Fac"])
        links.new(black.outputs["Emission"], mix.inputs[1])
        links.new(transparent.outputs["BSDF"], mix.inputs[2])
        links.new(mix.outputs["Shader"], out.inputs["Surface"])
    _materials[color] = mat
    return mat


# ───────────────────────────── props ─────────────────────────────


def tree(name, seed):
    rnd = random.Random(seed)
    p = Prop(name, 0.2)
    h = 11 + rnd.uniform(-1, 1)
    p.box("Trunk", (0, h / 2, 0), (2.6, h, 2.6))
    p.box("Trunk", (0, 0.6, 0), (3.6, 1.2, 3.6))  # root flare
    p.box("Trunk", (2.2, h * 0.7, 0), (3.4, 1.4, 1.4))  # branch
    p.box("Trunk", (-1.8, h * 0.8, 0.6), (2.6, 1.2, 1.2), (0, 30, 0))
    canopy = [
        ((0, h + 2.5, 0), (11, 6, 11), "Leaves"),
        ((3.8, h + 0.8, 2.5), (6.5, 4.5, 6.5), "LeavesLight"),
        ((-3.8, h + 1.6, -2.6), (6.5, 4.5, 6.5), "LeavesLight"),
        ((0.8, h + 6.2, -0.8), (7, 4, 7), "Leaves"),
        ((4.6, h - 0.2, -3.6), (4, 3, 4), "Leaves"),
        ((-3, h + 5, 3), (4.5, 3.5, 4.5), "LeavesLight"),
    ]
    for centre, size, color in canopy:
        jitter = (rnd.uniform(-0.5, 0.5), 0, rnd.uniform(-0.5, 0.5))
        p.box(color, tuple(c + j for c, j in zip(centre, jitter)), size, (0, rnd.uniform(-12, 12), 0))
    return p


def pine(name, seed):
    rnd = random.Random(seed)
    p = Prop(name, 0.18)
    p.box("Trunk", (0, 2.5, 0), (2, 5, 2))
    y = 4.5
    for i, width in enumerate((10, 8.2, 6.4, 4.6, 2.8)):
        p.box("Pine" if i % 2 == 0 else "PineLight", (0, y + 1.6, 0), (width, 3.2, width), (0, rnd.uniform(-10, 10) + i * 9, 0))
        y += 3
    p.box("PineLight", (0, y + 1.1, 0), (1.2, 2.2, 1.2))
    return p


def bush(name, seed):
    rnd = random.Random(seed)
    p = Prop(name, 0.12)
    p.box("Leaves", (0, 1.8, 0), (3.8, 3.6, 3.8), (0, rnd.uniform(0, 40), 0))
    for i, (x, z, s) in enumerate(((2.5, 1.2, 2.8), (-2.2, -0.9, 2.6), (0.7, -2.3, 2.2), (-1.0, 2.2, 2.0))):
        p.box("LeavesLight" if i % 2 == 0 else "Leaves", (x, s / 2, z), (s, s, s), (0, rnd.uniform(0, 45), 0))
    p.box("LeavesLight", (0.3, 3.9, 0.2), (2, 1.2, 2), (0, 20, 0))
    return p


def rock(name, seed):
    rnd = random.Random(seed)
    p = Prop(name, 0.12)
    p.box("Rock", (0, 1.3, 0), (4.4, 2.6, 3.4), (rnd.uniform(-6, 6), rnd.uniform(0, 90), rnd.uniform(-6, 6)))
    p.box("RockDark", (2.6, 0.8, 0.9), (2.2, 1.6, 2.2), (0, rnd.uniform(0, 90), 0))
    p.box("Rock", (-2.2, 0.55, -1), (1.6, 1.1, 1.6), (0, rnd.uniform(0, 90), 0))
    return p


def flowers(name, seed):
    rnd = random.Random(seed)
    p = Prop(name, 0.06)
    petals = ["PetalRed", "PetalYellow", "PetalPink", "PetalBlue"]
    for i in range(6):
        x, z = rnd.uniform(-2.6, 2.6), rnd.uniform(-2.6, 2.6)
        h = rnd.uniform(1.1, 1.8)
        color = petals[i % len(petals)]
        p.box("Stem", (x, h / 2, z), (0.3, h, 0.3))
        p.box("Stem", (x + 0.35, h * 0.4, z), (0.6, 0.15, 0.3), (0, 0, 20))  # leaf
        for dx, dz in ((0.45, 0), (-0.45, 0), (0, 0.45), (0, -0.45)):
            p.box(color, (x + dx, h + 0.15, z + dz), (0.5, 0.3, 0.5))
        p.box("FlowerCenter", (x, h + 0.2, z), (0.4, 0.4, 0.4))
    return p


def lamp(name):
    p = Prop(name, 0.1)
    p.box("Metal", (0, 0.4, 0), (2, 0.8, 2))
    p.box("Metal", (0, 6.5, 0), (0.8, 12, 0.8))
    p.box("Metal", (0, 12.6, 0), (2.8, 0.4, 2.8))
    p.box("Bulb", (0, 13.6, 0), (2, 1.8, 2))
    p.box("Metal", (0, 14.7, 0), (3, 0.4, 3))
    p.box("Metal", (0, 15.2, 0), (1.2, 0.6, 1.2))
    return p


PROPS = [
    tree("Tree", 1),
    tree("Tree_2", 2),
    pine("PineTree", 3),
    pine("PineTree_2", 4),
    bush("Bush", 5),
    bush("Bush_2", 6),
    rock("Rock", 7),
    rock("Rock_2", 8),
    flowers("Flowers", 9),
    lamp("Lamp"),
]


# ───────────────────────────── export ─────────────────────────────


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def export(path, objs):
    select_only(objs)
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"EMPTY", "MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_space_transform=True,
    )


def preview(path, roots):
    scene = bpy.context.scene
    # Trees along the back, the small things in front.
    back = [r for r in roots if "Tree" in r.name]
    front = [r for r in roots if "Tree" not in r.name]
    for i, root in enumerate(back):
        root.location = (-27 + i * 18, 14, 0)
    for i, root in enumerate(front):
        root.location = (-30 + i * 10, -4, 0)
    ground = bpy.data.objects.new("Ground", bpy.data.meshes.new("Ground"))
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=300)
    bm.to_mesh(ground.data)
    bm.free()
    COLORS["Ground"] = (96, 170, 80)
    ground.data.materials.append(material("Ground"))
    scene.collection.objects.link(ground)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 50
    cam.location = (0, -88, 34)
    cam.rotation_euler = (math.radians(68), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(40), math.radians(20), math.radians(30))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.68, 1.0, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    collection = bpy.context.scene.collection
    roots = [p.build(collection) for p in PROPS]
    for root in roots:
        export(os.path.join(OUT, root.name + ".fbx"), [root, *root.children])
    export(os.path.join(OUT, "LobbyProps.fbx"), [o for r in roots for o in (r, *r.children)])
    print(f"exported {len(roots)} props to {OUT}")
    if PREVIEW:
        preview(PREVIEW, roots)


if __name__ == "__main__":
    main()
    sys.exit(0)
