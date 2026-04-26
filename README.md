# w3dimporter

A MAXScript importer for Westwood 3D (`.w3d`) files in 3ds Max / gMax.

Originally scripted by **coolfile**, edited and augmented by **NDC**, further edited by **tria**.

Tested on 3ds Max 2023.

## Usage

1. Run `w3dimporter.ms` in 3ds Max (Scripting → Run Script).
2. The "W3D Importer" dialog opens. Click **Import a file** and pick a `.w3d`.
3. Optional toggles:
   - **Split by dependencies** — break a skinned mesh into rigid sub-meshes, one per bone.
   - **Auto-Bind** — automatically apply skinning (max skin or w3d skin).
   - **Use W3D materials** — when the W3D Tools `W3DMaterial` plugin is installed, build native W3D materials instead of Standard materials. Falls back to Standard if the plugin is missing.
   - **Debug output** — print per-mesh diagnostics to the MAXScript Listener.
   - **Ignore errors** — skip invalid pivot IDs in bit-channel animation tracks instead of erroring out.
   - **Batch processing** — import every `.w3d` in a folder.

## Changelog (v5 vs v3.1)

### W3D material support
New **Use W3D materials** checkbox. When the W3D Tools `W3DMaterial` plugin is installed, the importer builds W3DMaterials instead of Standard materials, with the following wired in from the W3D file:

- **Vertex material colors** — ambient, diffuse, specular, emissive
- **Vertex material scalars** — opacity, translucency, shininess
- **Stage 0 / Stage 1 mapping types** — decoded from `vmInfo.attrs` bits 8–15 and 16–23 (UV, Environment, ClassicEnvironment, Screen, LinearOffset, Silhouette, Scale, Grid, Rotate, Sine, Step, ZigZag, WSClassicEnv, WSEnvironment, GridClassicEnv, GridEnvironment, Random, Edge, BumpEnv, GridWSClassicEnv, GridWSEnv)
- **Stage 0 / Stage 1 mapping args** — copied from `VERTEX_MAPPER_ARGS0` / `VERTEX_MAPPER_ARGS1` chunks
- **Stage 0 texture** — assigned with `stage0texenabled = on`, `stage0display = on` (visible in viewport)
- **Defaults for fields not stored in W3D** — `stage0/1mappinguvchannel = 1`, `speculartodiffuse = off`

### Per-shader blend mode mapping
Each W3D shader's `srcBlend` / `destBlend` / `alphaTest` is mapped to the matching W3DMaterial blend mode:

| W3D shader | W3DMaterial blendmode |
| --- | --- |
| `srcBlend=ONE`, `destBlend=ZERO` | `Opaque (0)` |
| `srcBlend=ONE`, `destBlend=ONE` | `Add (1)` |
| `srcBlend=ZERO`, `destBlend=SRC_COLOR` | `Multiply (2)` |
| `srcBlend=ONE`, `destBlend=SRC_COLOR` | `MultiplyAndAdd (3)` |
| `srcBlend=ONE`, `destBlend=ONE_MINUS_SRC_COLOR` | `Screen (4)` |
| `srcBlend=SRC_ALPHA`, `destBlend=ONE_MINUS_SRC_ALPHA` | `AlphaBlend (5)` |
| any with `alphaTest != 0` | `AlphaTest (6)` or `AlphaTestAndBlend (7)` |
| anything else | `Custom (8)` |

`Add`, `AlphaBlend`, and `AlphaTestAndBlend` also explicitly write `blendmodesrc`, `blendmodedest`, and force `customblendwritezbuffer = off` so the material renders correctly without manual fix-up.

### Per-sub-material blend mode picking
For multi-texture meshes that build a multi-material, each sub-material now gets its own blend mode picked from the shader its faces actually reference (`pickBlendModeForSub`), instead of the whole mesh inheriting a single mesh-level mode. Fixes the bug where an opaque sub-material would inherit its parent's `Add` mode (or vice versa).

Handles three matlPass encodings:
- Single-shader meshes (`shaderIds.count == 1` and `shaders.count == 1`) — every sub uses the one shader.
- Short-form multi-shader meshes (`shaderIds.count == 1` but `shaders.count > 1`) — sub `N` maps to `shaders[N]`.
- Per-face shader meshes (`shaderIds.count > 1`) — walks the faces, collects shaders for each sub's `txIds`, and promotes toward the strongest (Add wins).

### AlphaTest detection ordering
`alphaTest != 0` is now checked **before** the `srcBlend=ONE, destBlend=ZERO` opaque pattern. The W3D `SC_ATEST_2D` preset uses the same blend factors as opaque and only differs by the `alphaTest` flag, so the previous order classified alpha-test meshes as opaque. Fixed in all four classification sites.

### Ignore errors checkbox
New checkbox (unchecked by default) in the import dialog. When enabled, the bit-channel animation loop skips entries whose `pivotID` is `0` or out of range, instead of erroring with `array index must be positive number, got: 0`. Use this when an asset's visibility track references `ROOTTRANSFORM` (pivotID 0) and you want the rest of the import to succeed.

### Expanded debug output
The **Debug output** checkbox now also prints, per mesh:
- Each shader's literal blend-mode label (Opaque / Add / Multiply / AlphaBlend / AlphaTest / etc.) alongside the raw values
- Each vertex material's colors, opacity, translucency, shininess
- Each vertex material's `attrs` bitfield with decoded `stage0mapping` / `stage1mapping` (integer + name)
- Each vertex material's `stage0mappingargs` / `stage1mappingargs` strings
- Per-sub-material blend mode picks for multi-material meshes (texture name + integer + label)
- The final W3DMaterial blendmode the mesh would receive

### Other small fixes
- Stage 0 textures show in the viewport (`stage0display = on`).
- The "alpha" / "additive" mesh classification now uses the engine's actual `Uses_Alpha()` rule (`destBlend ∈ {SRC_ALPHA, ONE_MINUS_SRC_ALPHA}` or `srcBlend ∈ {SRC_ALPHA, ONE_MINUS_SRC_ALPHA}`), matching `shader.h`.

### Known limitation: no multi-pass W3DMaterial output

The W3DMaterial plugin supports up to 4 passes per material, with each pass holding its own texture, blend mode, and shader settings. The W3D file format encodes this as multiple shader entries per mesh — e.g. an "Opaque base + Additive glow" mesh ships two shaders and two textures meant to render in two passes on a single material.

**The importer cannot produce multi-pass W3DMaterials.** This is a hard limitation imposed by how the W3DMaterial plugin exposes itself to MAXScript, not a missing feature in the importer:

- `getNumParamBlocks` and `getNumRefs` both return `0` on a `W3DMaterial` instance — the per-pass param blocks are not reachable through MAXScript's standard plugin reflection.
- `showProperties` on the material lists every per-pass property (`blendmode`, `stage0texturemap`, etc.) **four times** — once per pass — but with identical names. Dotted access (`m.blendmode = X`) and `setProperty` only ever hit the **first** occurrence (pass 1).
- There is no `m.passone` / `m.passtwo` / pass-indexed accessor exposed to script.

This was confirmed empirically by walking the material's exposed surface during import (see the `[probe]` lines in the debug log if you want to reproduce). Without a per-pass write API, the importer cannot set pass 2/3/4's texture or blend mode from script.

**What happens instead:** when a mesh has 2+ textures and 2+ distinct shaders, the importer falls back to building a 3ds Max **multi-material** with one W3DMaterial sub per texture, each correctly configured with its own blend mode (via `pickBlendModeForSub`). Per-face material IDs are assigned from `txIds` so each face uses the right sub. Visually this looks correct in 3ds Max, but it is **not a round-trip-safe representation** of the original W3D mesh — re-exporting through the W3D Tools exporter will write multiple separate single-pass materials, not the original multi-pass one.

If you need to preserve multi-pass W3DMaterials, you have to author/edit them by hand in 3ds Max after import.

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

## License

Original script © coolfile. Modifications released under the same terms.
