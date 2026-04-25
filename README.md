# w3dimporter v3.1

A MAXScript importer for Westwood 3D (`.w3d`) files in 3ds Max / gMax.

Originally scripted by **coolfile**, edited and augmented by **NDC**, further edited by **tria**.

## Usage

1. Run `w3dimporter-3.1.ms` in 3ds Max (Scripting → Run Script).
2. The "W3D Importer" dialog opens. Click **Import a file** and pick a `.w3d`.
3. Optional toggles:
   - **Split by dependencies** — break a skinned mesh into rigid sub-meshes, one per bone.
   - **Auto-Bind** — automatically apply skinning (max skin or w3d skin).
   - **Debug output** — print per-mesh diagnostics (textures, shader values, alpha/additive verdicts) to the MAXScript Listener.
   - **Batch processing** — import every `.w3d` in a folder.

## Changelog (v3.1 vs v2.0)

### Multi-texture meshes

Meshes that reference more than one texture now produce a `MultiSubObjectMaterial`
with one Standard sub-material per texture. Per-face material IDs are assigned from
the W3D `txIds` array (W3D_CHUNK_TEXTURE_IDS), so each face renders with the right
texture instead of all faces collapsing onto texture[0].

### Alpha textures

When the mesh's shader signals alpha usage — i.e. `alphaTest != 0`, or `srcBlend` /
`destBlend` references `SRC_ALPHA` / `ONE_MINUS_SRC_ALPHA` — the importer:

- Sets the diffuse bitmap's `alphaSource = 2` (None / Opaque) so the diffuse channel
  ignores its own alpha.
- Wires a second instance of the same bitmap into the Opacity slot with
  `monoOutput = 1` (Alpha), so only the opacity map drives transparency.

The detection rule mirrors `ShaderClass::Uses_Alpha()` from the engine's `shader.h`.

### Additive textures

When the mesh's shader matches the W3D `SC_ADDITIVE` preset
(`srcBlend = ONE (1)` and `destBlend = ONE (1)`), the importer:

- Wires the texture into the Opacity slot.
- Wires the texture into the Self-Illumination slot.
- Sets `useSelfIllumColor = true` so the self-illumination is driven by the map.

### Debug output toggle

New checkbox under "Auto-Bind" in the import dialog. When enabled, every imported
mesh prints to the Listener:

- `vertMatls.count`, `textures.count`, and each texture filename
- `txIds` and `vmIds` arrays from the material pass
- Per-shader `srcBlend`, `destBlend`, `alphaTest`, `depthMask`, plus an `alpha=` and
  `additive=` verdict for that shader
- Final mesh-level `meshUsesAlpha` and `meshIsAdditive` rollups

Useful for diagnosing why a particular asset isn't getting alpha or additive wiring.

**NOTE:** Imported model uses standard materials.
Tested on 3dsmax 2023.

## License

Original script © coolfile. Modifications released under the same terms.
