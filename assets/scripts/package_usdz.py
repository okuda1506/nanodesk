"""Package Blender's evaluated meshes as a self-contained, meter-scale USDZ.

Usage: python package_usdz.py /tmp/nano-meshes.json assets/runtime/NanoModel.usdz
Requires the OpenUSD Python package (usd-core, TOST-1.0).
"""
import argparse
import json
import tempfile
from pathlib import Path
from zipfile import ZipFile

from pxr import Gf, Sdf, Tf, Usd, UsdGeom, UsdShade, UsdUtils, Vt


def yup(v):
    return (v[0], v[2], -v[1])


def material(stage, name, values):
    color, metallic, roughness, clearcoat, coat_roughness = values
    path = '/Body/Looks/' + Tf.MakeValidIdentifier(name)
    mat = UsdShade.Material.Define(stage, path)
    shader = UsdShade.Shader.Define(stage, path+'/Surface')
    shader.CreateIdAttr('UsdPreviewSurface')
    shader.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*color))
    for label, value in [('metallic', metallic), ('roughness', roughness),
                         ('clearcoat', clearcoat), ('clearcoatRoughness', coat_roughness)]:
        shader.CreateInput(label, Sdf.ValueTypeNames.Float).Set(value)
    shader.CreateOutput('surface', Sdf.ValueTypeNames.Token)
    mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), 'surface')
    return mat


def export(data, destination, temp):
    layer = temp/'NanoModel.usdc'
    stage = Usd.Stage.CreateNew(str(layer))
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    root = UsdGeom.Xform.Define(stage, '/Body')
    stage.SetDefaultPrim(root.GetPrim())
    UsdGeom.Scope.Define(stage, '/Body/Looks')
    materials = {name: material(stage, name, values) for name, values in data['materials'].items()}
    objects = {obj['name']: obj for obj in data['objects']}

    def path(obj):
        prefix = path(objects[obj['parent']]) if obj['parent'] else ''
        return prefix + '/' + obj['name']

    for obj in objects.values():
        p = path(obj)
        if 'points' not in obj:
            UsdGeom.Xform.Define(stage, p)
            continue
        geo = UsdGeom.Mesh.Define(stage, p)
        geo.CreateSubdivisionSchemeAttr('none')
        pts = Vt.Vec3fArray([yup(v) for v in obj['points']])
        geo.CreatePointsAttr(pts)
        geo.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts))
        geo.CreateFaceVertexCountsAttr(obj['counts'])
        geo.CreateFaceVertexIndicesAttr(obj['indices'])
        geo.CreateNormalsAttr(Vt.Vec3fArray([yup(v) for v in obj['normals']]))
        geo.SetNormalsInterpolation(UsdGeom.Tokens.faceVarying)
        geo.CreateDoubleSidedAttr(False)
        if 'uv' in obj:
            tex = UsdGeom.PrimvarsAPI(geo).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, 'faceVarying')
            tex.Set(Vt.Vec2fArray(obj['uv']))
        binding = UsdShade.MaterialBindingAPI.Apply(geo.GetPrim())
        binding.Bind(materials[obj['materials'][0]])
        if len(obj['materials']) > 1:
            for i, name in enumerate(obj['materials']):
                members = [j for j, slot in enumerate(obj['slots']) if slot == i]
                subset = binding.CreateMaterialBindSubset('Finish'+str(i), members)
                UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(materials[name])
        if obj['name'] == 'AluminumExtrusion':
            # Preserve the continuous shell and give both halves named face sets.
            for label, side in [('FrontHousing', 1), ('RearHousing', -1)]:
                selected = []
                start = 0
                for index, count in enumerate(obj['counts']):
                    ids = obj['indices'][start:start+count]
                    if side * sum(pts[i][2] for i in ids) >= 0:
                        selected.append(index)
                    start += count
                UsdGeom.Subset.CreateGeomSubset(geo, label, 'face', selected)
    stage.GetRootLayer().Save()
    dest = str(destination.resolve())
    if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)), dest):
        raise RuntimeError('USDZ packaging failed')
    with ZipFile(dest) as archive:
        assert archive.namelist() == ['NanoModel.usdc'] and archive.testzip() is None
    check = Usd.Stage.Open(dest)
    assert check.GetDefaultPrim().GetName() == 'Body'
    assert UsdGeom.GetStageUpAxis(check) == 'Y' and UsdGeom.GetStageMetersPerUnit(check) == 1
    for obj in objects.values():
        prim = check.GetPrimAtPath(path(obj))
        assert prim, obj['name']
        if 'points' in obj:
            geom = UsdGeom.Mesh(prim)
            assert len(geom.GetPointsAttr().Get()) == len(obj['points'])
            assert UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
    uv = UsdGeom.PrimvarsAPI(check.GetPrimAtPath('/Body/ScreenSurface')).GetPrimvar('st')
    assert uv and uv.GetInterpolation() == 'faceVarying'
    cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ['default'])
    size = cache.ComputeWorldBound(check.GetDefaultPrim()).ComputeAlignedRange().GetSize()*1000
    assert max(abs(a-b) for a,b in zip(size,(38.7,90.7,6.2))) < .01, size
    print('USDZ verified:', len(objects), 'named device objects;', tuple(round(v,4) for v in size), 'mm (X,Y,Z)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exchange', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        export(json.loads(args.exchange.read_text()), args.output, Path(directory))
