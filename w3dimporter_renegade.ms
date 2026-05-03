-- w3d importer --
-- version 3.1 --
-- scripted by coolfile --
-- msn: coolfile_cn@hotmail.com --
-- edited and augmented by NDC --
-- edited by tria --
-- credits: Seagle & Sloth --

-- Debug: when not set to false, the importer prints one line per mesh
-- listing the textures it loaded. Set `w3dDebugMaterials = false` in the
-- listener to silence.
global w3dDebugMaterials = true

-- Reload helper: a runtime error inside cfW3DImporter can leave the rollout's
-- event-handler thread stuck, making every button in the dialog unresponsive.
-- The dialog itself can't recover from this (its own handlers are dead), so
-- recovery has to come from outside. Type `w3di.reload()` into the MAXScript
-- Listener after a crash and it'll tear the dialog down and rebuild it from a
-- clean state. (`w3di` is a struct used as a namespace so we can write
-- `w3di.reload`. `w3d` itself is reserved by 3dsmax.)
struct W3DImporterNamespace ( fn reload =
(
	try ( destroyDialog rltMain ) catch ()
	createDialog rltMain
))
global w3di = W3DImporterNamespace()

-- reference table for adaptive delta motion channels --
deltaTable = #()

struct HierarchyHeader
(
	version,
	hierName,
	pivotCount,
	centrePos
)

struct HierarchyPivot
(
	pivotName,
	parentID,
	pos,
	eulerAngles,
	rotation
)

struct Hierarchy
(
	header,
	pivots
)

struct AnimationHeader
(
	version,
	animName,
	skelName,
	frameCount,
	frameRate
)

struct CompressedAnimationHeader
(
	version,
	animName,
	skelName,
	frameCount,
	frameRate,
	flavour
)

struct AnimationChannel
(
	firstFrame,
	lastFrame,
	vectorLen,
	flags,
	pivotID,
	pad,
	values
)

struct AnimationTimeCodedKey
(
	keyTime,
	keyValue
)

struct AnimationTimeCodedChannel
(
	type,
	timeCodesCount,
	pivotID,
	vectorLen,
	flags,
	values
)

struct AnimationAdaptiveDeltaChannel
(
	type,
	framesCount,
	pivotID,
	vectorLen,
	flags,
	initDelta,
	increment,
	values
)

struct adInterval
(
	coef,
	startInterval,
	endInterval
)

struct AnimationBitChannel
(
	firstFrame,
	lastFrame,
	flags,
	pivotID,
	defaultVal,
	values
)

struct Animation
(
	header,
	channels,
	bitChannels
)

struct W3dMeshHeader
(
	version, attrs, meshName, containerName, 
	faceCount, vertCount, matlCount, damageStageCount, 
	sortLevel, prelitVersion, futureCount, vertChannelCount, faceChannelCount, 
	minCorner, maxCorner, sphCentre, sphRadius
)

struct W3dMeshFace
(
	vertIds,
	attrs,
	normal,
	distance
)

struct W3dMeshMaterialSetInfo
(
	passCount,
	vertMatlCount,
	shaderCount,
	textureCount
)
struct W3dMeshShader
(
	depthCompare, depthMask, colorMask, destBlend, fogFunc, priGradient, secGradient, srcBlend, texturing, 
	detailColorFunc, detailAlphaFunc, shaderPreset, alphaTest, postDetailColorFunc, postDetailAlphaFunc, pad
)

struct W3dMeshVertMaterialInfo
(
	attrs,
	ambient,
	diffuse,
	specular,
	emissive,
	shininess,
	opacity,
	translucency
)

struct W3dMeshVertMaterial
(
	vmName,
	vmInfo,
	vmArgs0,
	vmArgs1
)

struct W3dMeshTextureInfo
(
	attrs,
	animType,
	frameCount,
	frameRate
)

struct W3dMeshTexture
(
	txFileName,
	txInfo
)

struct W3dMeshTextureCoord
(
	u, v
)

struct W3dMeshTextureStage
(
	txIds,
	txCoords
)

struct W3dMeshMaterialPass
(
	vmIds,
	shaderIds,
	textureStage,	-- legacy: first stage (== textureStages[1] when present); kept for back-compat readers
	textureStages	-- array of W3dMeshTextureStage, one per W3D_CHUNK_TEXTURE_STAGE in this pass
)

struct W3dMeshVertInfs
(
	boneIds1,
	boneIds2,
	boneWgts1,
	boneWgts2
)

struct W3dMesh
(
	header,
	verts,
	normals,
	vertInfs,
	faces,
	shadeIds,
	matlheader,
	shaders,
	vertMatls,
	textures,
	matlPass,
	matlPasses
)

struct HLodHeader
(
	version,
	lodCount,
	hlodName,
	hierarchyName
)

struct HLodObjectArrayHeader
(
	modelCount,
	maxScreenSize
)

struct HLodObject
(
	pivotIndex,
	lodName
)

struct HLodObjectArray
(
	header,
	lodObjects
)

struct HLod
(
	header,
	lodArray
)

struct AABox
(
	version,
	attrs,
	boxName,
	boxColor,
	centre,
	extent
)

struct Dependency
(
	locBone,
	Vertices
)

struct DependencyStack
(
	locMesh,
	Dependencies
)

fn GetChunkSize chunkSize =
( result = bit.and chunkSize 0x7FFFFFFF )

fn ReadLongArray fstream arrayEnd=
(
	longArray = #()
	while (ftell fstream < arrayEnd) do
	( append longArray (ReadLong fstream #unsigned) )
	return longArray
)

fn ReadShortArray fstream arrayEnd=
(
	shortArray = #()
	while (ftell fstream < arrayEnd) do
	(
		shortArray[shortArray.count+1] = ReadShort fstream #unsigned
	)
	return shortArray
)

fn ReadFixedString fstream =
(
	strend = (ftell fstream) + 16
	instr = ReadString fstream 
	fseek fstream strend #seek_set
	result = instr
)

fn ReadLongFixedString fstream =
(
	strend = (ftell fstream) + 32
	instr = ReadString fstream 
	fseek fstream strend #seek_set
	result = instr
)

fn ReadColor fstream =
(
	r = ReadByte fstream #unsigned
	g = ReadByte fstream #unsigned
	b = ReadByte fstream #unsigned
	a = ReadByte fstream #unsigned
	result = Color r g b a
	--the following code will miss one byte sometime. but why?
	--result = Color (ReadByte fstream #unsigned) (ReadByte fstream #unsigned) (ReadByte fstream #unsigned) (ReadByte fstream #unsigned)
)

fn ReadHierarchyHeader fstream =
(
	version = ReadLong fstream #unsigned
	hierName = ReadFixedString fstream
	pivotCount = ReadLong fstream #unsigned
	centrePos = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	result = HierarchyHeader version hierName pivotCount centrePos
	--return result
)

fn ReadHierarchyPivots fstream pivotsEnd =
(
	pivots = #()
	while (ftell fstream < pivotsEnd) do
	(
		pivotName = ReadFixedString fstream
		parentID = ReadLong fstream #unsigned	-- 0xffffffff = root pivot; no parent
		--if parentID != 0xffffffff do parentID += 1
		pos = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- translation to pivot point
		eulerAngles = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- orientation of the pivot point
		rotation = Quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- orientation of the pivot point
		pivots[(pivots.count + 1)] = HierarchyPivot pivotName parentID pos eulerAngles rotation
	)
	result = pivots
	--return result
)

fn ReadHierarchy fstream chunkEnd =
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		------ debug start ------
		--print ("Type: 0x" + (bit.intAsHex chunkType))
		--chunkSize = ReadLong fstream
		--print ("Size: 0x" + (bit.intAsHex chunkSize))
		--chunkSize = GetChunkSize(chunkSize)
		--print (bit.intAsHex chunkSize)
		------ debug end ------
		case chunkType of
		(
			0x00000101:	--W3D_CHUNK_HIERARCHY_HEADER
			(
				header = ReadHierarchyHeader fstream
			)
			0x00000102:	--W3D_CHUNK_PIVOTS
			(
				subChunkEnd = (ftell fstream) + chunkSize
				pivots = ReadHierarchyPivots fstream subChunkEnd
			)
			0x00000103:	--W3D_CHUNK_PIVOT_FIXUPS	-- only needed by the exporter...
			(
				--fixups[(fixups.count + 1)] = ReadHierarchyFixUps fstream
				--cracked format: there are 64 bytes in 12 dwords in 3 channels in each fixup.
				--channel X : ScaleX, Unknown, Unknown, Unknown (Long/DWord)
				--channel Y : ScaleY, Unknown, Unknown, Unknown (Long/DWord)
				--channel Z : ScaleZ, Unknown, Unknown, Unknown (Long/DWord)
				fseek fstream chunkSize #seek_cur
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
		------ debug start ------
		--print ("Pos: 0x" + (bit.intAsHex (ftell fstream)))
		--print ("End: 0x" + (bit.intAsHex chunkEnd))
		------ debug end ------
	)
	result = Hierarchy header pivots
	--return result
)

fn ReadAnimationHeader fstream =
(
	version = ReadLong fstream #unsigned
	animName = ReadFixedString fstream
	skelName = ReadFixedString fstream
	frameCount = ReadLong fstream #unsigned
	frameRate = ReadLong fstream #unsigned
	result = AnimationHeader version animName skelName frameCount frameRate
	--return result
)

fn ReadCompressedAnimationHeader fstream =
(
	version = ReadLong fstream #unsigned
	animName = ReadFixedString fstream
	skelName = ReadFixedString fstream
	frameCount = ReadLong fstream #unsigned
	frameRate = ReadShort fstream #unsigned
	flavour = ReadShort fstream #unsigned
	result = CompressedAnimationHeader version animName skelName frameCount frameRate flavour
	--return result
)

fn ReadAnimationChannel fstream chunkEnd =
(
	firstFrame = ReadShort fstream #unsigned
	lastFrame = ReadShort fstream #unsigned
	vectorLen = ReadShort fstream #unsigned
	flags = ReadShort fstream #unsigned
	pivotID = ReadShort fstream #unsigned
	--if pivotID != 0xffffffff then pivotID += 1 -- v1.00, cancelled at v1.04
	pad = ReadShort fstream #unsigned
	values = #()
	i = 1
	while (ftell fstream < chunkEnd) do
	(
		case flags of
		(
			0x0006: --ANIM_CHANNEL_Q
				values[i] = quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
			default: --ANIM_CHANNEL_X/Y/Z
				values[i] = ReadFloat fstream
		)
		i += 1
	)
	result = AnimationChannel firstFrame lastFrame vectorLen flags pivotID pad values
	--return result
)

fn ReadAnimationTimeCodedChannel fstream chunkEnd =
(
	timeCodesCount = ReadLong fstream #unsigned
	pivotID = ReadShort fstream #unsigned
	vectorLen = ReadByte fstream #unsigned
	flags = ReadByte fstream #unsigned
	values = #()
	i = 1
	while (ftell fstream < chunkEnd) do
	(
		tCode = ReadLong fstream #unsigned
		case flags of
		(
			0x0006: --ANIM_CHANNEL_TIMECODED_Q
				tValue = quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
			default: --ANIM_CHANNEL_TIMECODED_X/Y/Z
				tValue = ReadFloat fstream
		)
		values[i] = AnimationTimeCodedKey tCode tValue
		i += 1
	)
	result = AnimationTimeCodedChannel 1 timeCodesCount pivotID vectorLen flags values
	--return result
)

fn procDeltaBlockData fstream nBits scale initVal =
(
	procData = #()
	v0 = initVal
	
	for i=1 to 2*nBits do
	(
		currByte = readByte fstream #unsigned
		
		if (nBits == 4) then
		(
			-- Splitting the byte into halves
			lVal = bit.and currByte 0x0F
			uVal = bit.shift currByte -4
			
			-- Restoring halves' signs (bit flipping)
			if (lVal >= 8) do lVal -= 16
			if (uVal >= 8) do uVal -= 16
			
			append procData (v0 + scale*lVal)
			v0 += scale*lVal
			append procData (v0 + scale*uVal)
			v0 += scale*uVal
		)
		else
		(
			currByte += 128
			if (currByte >= 128) do currByte -= 256
			append procData (v0 + scale*currByte)
			v0 += scale*currByte
		)
	)
	
	return procData
)

fn ReadAnimationCompressedMotionChannel fstream chunkEnd =
(
	fseek fstream 1 #seek_cur -- skipping a zero byte
	chnType = readByte fstream #unsigned
	keyFrameChn = (chnType == 0)
	vectorLen = readByte fstream #unsigned
	
	flags = readByte fstream #unsigned
	values = #()
	
	nTimeCodes = readShort fstream #unsigned
	pivotID = readShort fstream #unsigned
	
	-- Simple time key channel
	if (keyFrameChn) then
	(	
		for i=1 to nTimeCodes do
		(
			tCode = readShort fstream #unsigned
			values[i] = AnimationTimeCodedKey tCode 0
		)
		
		if ((mod nTimeCodes 2) != 0) do --skipping padding
		( fseek fstream 2 #seek_cur )
		
		for i=1 to nTimeCodes do
		(
			case flags of
			(
				0x0006: --ANIM_CHANNEL_TIMECODED_Q
					values[i].keyValue = quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
				default: --ANIM_CHANNEL_TIMECODED_X/Y/Z
					values[i].keyValue = readFloat fstream
			)
		)
		
		result = AnimationTimeCodedChannel 1 nTimeCodes pivotID vectorLen flags values
		return result
	)
	
	-- Adaptive delta channel
	scale = readFloat fstream
	nBits = 4*chnType
	nBlocks = bit.shift (nTimeCodes+15) -4 -- In how many sections are data encoded? +15 is to make sure we start from 1
	
	scaleFactor = float 1
	if (nBits == 8) do
	( scaleFactor /= 16 )
	
	decData = #()
	values = #()
	deltaTableIx = 0
	
	case flags of
	(
		0x0006: --ANIM_MOTION_CHANNEL_DELTA_Q
		(
			decData[1] = #(readFloat fstream)
			decData[2] = #(readFloat fstream)
			decData[3] = #(readFloat fstream)
			decData[4] = #(readFloat fstream)
			
			for i=1 to nBlocks do
			(
				for j=1 to 4 do
				(
					deltaTableIx = readByte fstream #unsigned
					deltaScale = scale * scaleFactor * deltaTable[deltaTableIx+1]
					if (deltaTableIx <= 15) do deltaScale /= 100
					
					join decData[j] (procDeltaBlockData fstream nBits deltaScale decData[j][decData[j].count])
				)
			)
			
			decData[1].count = nTimeCodes
			decData[2].count = nTimeCodes
			decData[3].count = nTimeCodes
			decData[4].count = nTimeCodes
			
			for t=1 to decData[1].count do
			( values[t] = AnimationTimeCodedKey (t-1) (quat decData[1][t] decData[2][t] decData[3][t] decData[4][t]) )
		)
		default: --ANIM_MOTION_CHANNEL_DELTA_X/Y/Z
		(
			decData[1] = ReadFloat fstream
			
			for i=1 to nBlocks do
			(
				deltaTableIx = readByte fstream #unsigned
				deltaScale = scale * scaleFactor * deltaTable[deltaTableIx+1]
				if (deltaTableIx <= 15) do deltaScale /= 100
				
				join decData (procDeltaBlockData fstream nBits deltaScale decData[decData.count])
			)
			
			decData.count = nTimeCodes
			
			for t=1 to decData.count do
			( values[t] = AnimationTimeCodedKey (t-1) (decData[t]) )
		)
	)
	
	result = AnimationTimeCodedChannel 1 nTimeCodes pivotID vectorLen flags values
	return result
)

fn ReadAnimationBitChannel fstream chunkEnd =
(
	firstFrame = ReadShort fstream #unsigned
	lastFrame = ReadShort fstream #unsigned
	flags = ReadShort fstream #unsigned
	pivotID = ReadShort fstream #unsigned
	--if pivotID != 0xffffffff then pivotID += 1 -- v.100 cancelled at v.104
	defaultVal = ReadByte fstream #unsigned
	values = #()
	i = 1
	while (ftell fstream < chunkEnd) do
	(
		values[i] = ReadByte fstream #unsigned
		i += 1
	)
	result = AnimationBitChannel firstFrame lastFrame flags pivotID defaultVal values
)

--fn ReadAnimationTimeCodedBitChannel fstream chunkEnd =
--(
--	timeCodesCount = ReadLong fstream #unsigned
--	pivotID = ReadShort fstream #unsigned
--	flags = ReadByte fstream #unsigned
--	defaultVal = ReadByte fstream #unsigned
--	values = #()
--	i = 1
--	while (ftell fstream < chunkEnd) do
--	(
--		values[i] = ReadByte fstream #unsigned
--		i += 1
--	)
--	result = AnimationBitChannel firstFrame lastFrame flags pivotID defaultVal values
--	--return result
--)

fn ReadAnimation fstream chunkEnd =
(
	channels = #()
	bitchannels = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000201:	--W3D_CHUNK_ANIMATION_HEADER
			(
				header = ReadAnimationHeader fstream
			)
			0x00000202:	--W3D_CHUNK_ANIMATION_CHANNEL	-- channel of vectors
			(
				subChunkEnd = (ftell fstream) + chunkSize
				channels[(channels.count + 1)] = ReadAnimationChannel fstream subChunkEnd --frameCount
			)
			0x00000203:	--W3D_CHUNK_BIT_CHANNEL	-- channel of boolean values (e.g. visibility)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				bitchannels[(bitchannels.count + 1)] = ReadAnimationBitChannel fstream subChunkEnd
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
		------ debug start ------
		--print ("type: " + bit.intAsHex chunkType)
		--print ("pos: " + bit.intAsHex (ftell fstream))
		--print ("end: " + bit.intAsHex chunkEnd)
		------ debug end ------
	)
	result = Animation header channels bitchannels
	--return result
)

fn ReadCompressedAnimation fstream chunkEnd =
(
	channels = #()
	bitchannels = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000281:	--W3D_CHUNK_COMPRESSED_ANIMATION_HEADER
			(
				header = ReadCompressedAnimationHeader fstream
			)
			0x00000282:	--W3D_CHUNK_COMPRESSED_ANIMATION_CHANNEL	-- channel of vectors
			(
				subChunkEnd = (ftell fstream) + chunkSize
				if header != undefined then
					animMode = header.flavour
				else
					animMode = -1
				case animMode of
				(
					0x0: --ANIM_FLAVOUR_TIMECODED
					(
						channels[(channels.count + 1)] = ReadAnimationTimeCodedChannel fstream subChunkEnd --frameCount
					)
					0x1: --ANIM_FLAVOUR_ADAPTIVE_DELTA
					(
						--channels[(channels.count + 1)] = ReadAnimationAdaptiveDeltaChannel fstream subChunkEnd
					)
					--0x2: --ANIM_FLAVOUR_VALID
				)
			)
			--0x00000283:	--W3D_CHUNK_COMPRESSED_BIT_CHANNEL	-- channel of boolean values (e.g. visibility)
			--(
			--	subChunkEnd = (ftell fstream) + chunkSize
			--	bitchannels[(bitchannels.count + 1)] = ReadCompressedAnimationBitChannel fstream subChunkEnd
			--)
			0x00000284:	--W3D_CHUNK_COMPRESSED_ADAPTIVE_DELTA_MOTION_ANIMATION_CHANNEL
			(
				subChunkEnd = (ftell fstream) + chunkSize
				if header != undefined then
					animMode = header.flavour
				else
					animMode = -1
				case animMode of
				(
					0x0: --ANIM_FLAVOUR_TIMECODED
					( channels[(channels.count + 1)] = ReadAnimationCompressedMotionChannel fstream subChunkEnd )
					
				)
			)
			default:
			( fseek fstream chunkSize #seek_cur )
		)
	)
	result = Animation header channels bitchannels
	--return result
)

-- Decode a raw W3D_MESH_HEADER3.Attributes (or W3DBOX.Attributes) word into a list
-- of human-readable W3D Tools property names. Used by the "Import extended W3D
-- Info" debug log so the user can see exactly which bits the .w3d encoded and
-- which properties wwSetFlags / wwSetSorting will toggle on the imported nodes.
-- Constants mirror src\scripts\w3d.h.
fn cfDecodeW3DAttrs a =
(
	local parts = #()
	local gt = bit.and a 0x00FF0000	-- W3D_MESH_FLAG_GEOMETRY_TYPE_MASK
	case gt of
	(
		0x00000000:	append parts "GeomType=Normal"
		0x00010000:	append parts "GeomType=CamParal"
		0x00020000:	append parts "GeomType=Skin"
		0x00040000:	append parts "GeomType=AABox"
		0x00050000:	append parts "GeomType=OBBox"
		0x00060000:	append parts "GeomType=CamOrient"
		0x00070000:	append parts "GeomType=CamZOrient"
		default:	append parts ("GeomType=0x" + (bit.intAsHex gt))
	)
	if (bit.and a 0x00001000) != 0 do append parts "Hide"
	if (bit.and a 0x00002000) != 0 do append parts "TwoSided"
	if (bit.and a 0x00008000) != 0 do append parts "CastShadow"
	if (bit.and a 0x10000000) != 0 do append parts "Shatter"
	if (bit.and a 0x20000000) != 0 do append parts "Tangents"
	if (bit.and a 0x40000000) != 0 do append parts "Prelit"
	if (bit.and a 0x80000000) != 0 do append parts "AlwaysDynLight"
	-- Collision bits (W3D_MESH_FLAG_COLLISION_TYPE_MASK = 0x00000FF0).
	if (bit.and a 0x00000010) != 0 do append parts "Coll:Physical"
	if (bit.and a 0x00000020) != 0 do append parts "Coll:Projectile"
	if (bit.and a 0x00000040) != 0 do append parts "Coll:Vis"
	if (bit.and a 0x00000080) != 0 do append parts "Coll:Camera"
	if (bit.and a 0x00000100) != 0 do append parts "Coll:Vehicle"
	-- W3DBOX-only attribute bits.
	if (bit.and a 0x00000001) != 0 do append parts "Box:Aligned"
	if (bit.and a 0x00000002) != 0 do append parts "Box:Oriented"
	return parts
)

fn ReadMeshHeader fstream =
(
	version = ReadLong fstream #unsigned
	attrs = ReadLong fstream #unsigned
	meshName = ReadFixedString fstream
	containerName = ReadFixedString fstream
	-- Counts, these can be regarded as an inventory of what is to come in the file.
	faceCount = ReadLong fstream #unsigned	--number of triangles
	vertCount = ReadLong fstream #unsigned	--number of unique vertices
	matlCount = ReadLong fstream #unsigned	--number of unique materials
	damageStageCount = ReadLong fstream #unsigned	--number of damage offset chunks
	sortLevel = ReadLong fstream #unsigned	--static sorting level of this mesh
	prelitVersion = ReadLong fstream #unsigned	--mesh generated by this version of Lightmap Tool
	futureCount = ReadLong fstream #unsigned	--future counts
	vertChannelCount = ReadLong fstream #unsigned	--bits for presence of types of per-vertex info
	faceChannelCount = ReadLong fstream #unsigned	--bits for presence of types of per-face info
	-- Bounding volumes
	minCorner = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	--Min corner of the bounding box
	maxCorner = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	--Max corner of the bounding box
	sphCentre = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	--Centre of bounding sphere
	sphRadius = ReadFloat fstream	--Bounding sphere radius
	result = W3dMeshHeader version attrs meshName containerName faceCount vertCount matlCount damageStageCount sortLevel prelitVersion futureCount vertChannelCount faceChannelCount minCorner maxCorner sphCentre sphRadius
)

fn ReadMeshVertArray fstream chunkEnd =
(
	verts = #()
	while (ftell fstream < chunkEnd) do
	(
		verts[verts.count+1] = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	)
	return verts
)

fn ReadMeshFace fstream =
(
	--vertIds = #()
	--vertIds[1] = ReadLong fstream #unsigned	-- vertex,vnormal,texcoord,color indices
	--vertIds[2] = ReadLong fstream #unsigned
	--vertIds[3] = ReadLong fstream #unsigned
	vertIds = Point3 (ReadLong fstream #unsigned) (ReadLong fstream #unsigned) (ReadLong fstream #unsigned)
	attrs = ReadLong fstream #unsigned	-- attributes bits
	normal = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- plane normal
	distance = ReadFloat fstream	-- plane distance
	result = W3dMeshFace vertIds attrs normal distance
)

fn ReadMeshFaceArray fstream chunkEnd =
(
	faces = #()
	while (ftell fstream < chunkEnd) do
	( append faces (ReadMeshFace fstream) )
	return faces
)

--replaced by ReadLongArray since v1.02
--fn ReadMeshVertShadeIds fstream chunkEnd =
--(
--	shadeIds = #()
--	while (ftell fstream < chunkEnd) do
--	(
--		shadeIds[shadeIds.count+1] = ReadLong fstream #unsigned
--	)
--	return shadeIds
--)

fn ReadMeshVertInfs fstream chunkEnd =
(
	boneIds1 = #()
	boneIds2 = #()
	boneWgts1 = #()
	boneWgts2 = #()
	while (ftell fstream < chunkEnd) do
	(
		append boneIds1 (ReadShort fstream #unsigned)
		append boneIds2 (ReadShort fstream #unsigned)
		append boneWgts1 (ReadShort fstream #unsigned)
		append boneWgts2 (ReadShort fstream #unsigned)
		
		--if (boneIds2[boneIds2.count] > 0) do break()
		--fseek fstream 6 #seek_cur --skip pad 6 bytes
	)
	return W3dMeshVertInfs boneIds1 boneIds2 boneWgts1 boneWgts2
)

fn ReadMeshMaterialSetInfo fstream chunkEnd =
(
	passCount = ReadLong fstream #unsigned	--how many material passes this render object uses
	vertMatlCount = ReadLong fstream #unsigned	--how many vertex materials are used
	shaderCount = ReadLong fstream #unsigned	--how many shaders are used
	textureCount = ReadLong fstream #unsigned	--how many textures are used
	result = W3dMeshMaterialSetInfo passCount vertMatlCount shaderCount textureCount
)

fn ReadMeshShader fstream =
(
	depthCompare = ReadByte fstream #unsigned
	depthMask = ReadByte fstream #unsigned
	colorMask = ReadByte fstream #unsigned	--now obsolete and ignored
	destBlend = ReadByte fstream #unsigned
	fogFunc = ReadByte fstream #unsigned	--now obsolete and ignored
	priGradient = ReadByte fstream #unsigned
	secGradient = ReadByte fstream #unsigned
	srcBlend = ReadByte fstream #unsigned
	texturing = ReadByte fstream #unsigned
	detailColorFunc = ReadByte fstream #unsigned
	detailAlphaFunc = ReadByte fstream #unsigned
	shaderPreset = ReadByte fstream #unsigned	--now obsolete and ignored
	alphaTest = ReadByte fstream #unsigned
	postDetailColorFunc = ReadByte fstream #unsigned
	postDetailAlphaFunc = ReadByte fstream #unsigned
	pad = ReadByte fstream #unsigned
	result = W3dMeshShader depthCompare depthMask colorMask destBlend fogFunc priGradient secGradient srcBlend texturing detailColorFunc detailAlphaFunc shaderPreset alphaTest postDetailColorFunc postDetailAlphaFunc pad
)

fn ReadMeshShaderArray fstream chunkEnd =
(
	shaders = #()
	while (ftell fstream < chunkEnd) do
	(
		shaders[shaders.count+1] = ReadMeshShader fstream
	)
	return shaders
)

fn ReadMeshVertMaterialInfo fstream =
(
	attrs = ReadLong fstream #unsigned	-- bitfield for the flags defined above
	ambient = ReadColor fstream
	diffuse = ReadColor fstream
	specular = ReadColor fstream
	emissive = ReadColor fstream
	shininess = ReadFloat fstream	-- how tight the specular highlight will be, 1 - 1000 (default = 1)
	opacity = ReadFloat fstream	-- how opaque the material is, 0.0 = invisible, 1.0 = fully opaque (default = 1)
	translucency = ReadFloat fstream	-- how much light passes through the material. (default = 0)
	result = W3dMeshVertMaterialInfo attrs ambient diffuse specular emissive shininess opacity translucency
)

fn ReadMeshVertMaterial fstream chunkEnd =
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x0000002C:	--W3D_CHUNK_VERTEX_MATERIAL_NAME	--vertex material name (NULL-terminated string)
			(
				vmName = ReadString fstream
			)
			0x0000002D:	--W3D_CHUNK_VERTEX_MATERIAL_INFO	--W3dVertexMaterialStruct
			(
				vmInfo = ReadMeshVertMaterialInfo fstream
			)
			0x0000002E:	--W3D_CHUNK_VERTEX_MAPPER_ARGS0	--Null-terminated string
			(
				vmArgs0 = ReadString fstream
			)
			0x0000002F:	--W3D_CHUNK_VERTEX_MAPPER_ARGS1	--Null-terminated string
			(
				vmArgs1 = ReadString fstream
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	result = W3dMeshVertMaterial vmName vmInfo vmArgs0 vmArgs1
)

fn ReadMeshVertMaterialArray fstream chunkEnd =
(
	matls = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x0000002B:	--W3D_CHUNK_VERTEX_MATERIAL
			(
				subChunkEnd = (ftell fstream) + chunkSize
				matls[matls.count+1] = ReadMeshVertMaterial fstream subChunkEnd
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	return matls
)

fn ReadMeshTextureInfo fstream=
(
	attrs = ReadShort fstream #unsigned
	animType = ReadShort fstream #unsigned
	frameCount = ReadLong fstream #unsigned
	frameRate = ReadFloat fstream
	result = W3dMeshTextureInfo attrs animType frameCount frameRate
)

fn ReadMeshTexture fstream chunkEnd=
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000032:	--W3D_CHUNK_TEXTURE_NAME	// texture filename (NULL-terminated string)
			(
				txFileName = ReadString fstream
			)
			0x00000033:	--W3D_CHUNK_TEXTURE_INFO	// optional W3dTextureInfoStruct
			(
				txInfo = ReadMeshTextureInfo fstream
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshTexture txFileName txInfo
)

fn ReadMeshTextureArray fstream chunkEnd=
(
	textures = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000031:	--W3D_CHUNK_TEXTURE	// wraps a texture definition
			(
				subChunkEnd = (ftell fstream) + chunkSize
				textures[(textures.count + 1)] = ReadMeshTexture fstream subChunkEnd
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	return textures
)

fn ReadMeshTextureCoordArray fstream chunkEnd=
(
	txCoords = #()
	while (ftell fstream < chunkEnd) do
	(
		--u = ReadFloat fstream
		--v = ReadFloat fstream
		--txCoords[txCoords.count+1] = W3dMeshTextureCoord u v
		append txCoords (Point2 (ReadFloat fstream) (ReadFloat fstream))
	)
	return txCoords
)

fn ReadMeshTextureStage fstream chunkEnd=
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000049:	--W3D_CHUNK_TEXTURE_IDS	// single or per-tri array of uint32 texture indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txIds = ReadLongArray fstream subChunkEnd
			)
			0x0000004A:	--W3D_CHUNK_STAGE_TEXCOORDS	// per-vertex texture coordinates (array of W3dTexCoordStruct's)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txCoords = ReadMeshTextureCoordArray fstream subChunkEnd
			)
			--0x0000004B:	--W3D_CHUNK_PER_FACE_TEXCOORD_IDS	// indices to W3D_CHUNK_STAGE_TEXCOORDS, (array of Vector3i)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshTextureStage txIds txCoords
)

fn ReadMeshMaterialPass fstream chunkEnd=
(
	-- A MATERIAL_PASS may contain multiple TEXTURE_STAGE sub-chunks (stage 0, stage 1, ...).
	-- Collect them all; expose stages[1] as the legacy `textureStage` field for back-compat.
	local txStages = #()
	local txStage = undefined
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		tempMatl = ftell fstream
		case chunkType of
		(
			0x00000039:	--W3D_CHUNK_VERTEX_MATERIAL_IDS	// single or per-vertex array of uint32 vertex material indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				vmIds = ReadLongArray fstream subChunkEnd
			)
			0x0000003F:	--W3D_CHUNK_VERTEX_MATERIAL_IDS (NEW)	// single or per-vertex array of uint32 vertex material indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				vmIds = ReadLongArray fstream subChunkEnd
				shaderIds = #()
				join shaderIds vmIds
			)
			0x0000003A:	--W3D_CHUNK_SHADER_IDS	// single or per-tri array of uint32 shader indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				shaderIds = ReadLongArray fstream subChunkEnd
			)
			--0x0000003B:	--W3D_CHUNK_DCG	// per-vertex diffuse color values (array of W3dRGBAStruct's)
			--0x0000003C:	--W3D_CHUNK_DIG	// per-vertex diffuse illumination values (array of W3dRGBStruct's)
			--0x0000003E:	--W3D_CHUNK_SCG	// per-vertex specular color values (array of W3dRGBStruct's)
			0x00000048:	--W3D_CHUNK_TEXTURE_STAGE	// wrapper around a texture stage.
			(
				subChunkEnd = (ftell fstream) + chunkSize
				local _stg = ReadMeshTextureStage fstream subChunkEnd
				append txStages _stg
				if txStage == undefined do txStage = _stg
			)
			0x0000004A:	--W3D_CHUNK_TEXTURE_STAGE (NEW)	// wrapper around a texture stage.
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txIds =#()
				join txIds vmIds
				local _stg = W3dMeshTextureStage txIds (ReadMeshTextureCoordArray fstream subChunkEnd)
				append txStages _stg
				if txStage == undefined do txStage = _stg
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshMaterialPass vmIds shaderIds txStage txStages
)

fn ReadMesh fstream chunkEnd =
(
	--bitchannels = #()
	matlPasses = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		subChunkEnd = (ftell fstream) + chunkSize
		case chunkType of
		(
			0x00000002:	--W3D_CHUNK_VERTICES	--array of vertices (array of W3dVectorStruct's)
			(
				verts = ReadMeshVertArray fstream subChunkEnd
			)
			0x00000003:	--W3D_CHUNK_VERTEX_NORMALS	--array of normals (array of W3dVectorStruct's)
			(
				normals = ReadMeshVertArray fstream subChunkEnd
			)
			--0x0000000C:	--W3D_CHUNK_MESH_USER_TEXT	// Text from the MAX comment field (Null terminated string)
			0x0000000E:	--W3D_CHUNK_VERTEX_INFLUENCES	--Mesh Deformation vertex connections (array of W3dVertInfStruct's)
			(
				vertInfs = ReadMeshVertInfs fstream subChunkEnd
			)
			0x0000001F:	--W3D_CHUNK_MESH_HEADER3	--mesh header contains general info about the mesh.
			(
				header = ReadMeshHeader fstream
			)
			0x00000020:	--W3D_CHUNK_TRIANGLES	--new improved triangles chunk (array of W3dTriangleStruct's)
			(
				faces = ReadMeshFaceArray fstream subChunkEnd
			)
			0x00000022:	--W3D_CHUNK_VERTEX_SHADE_INDICES	--shade indexes for each vertex (array of uint32's)
			(
				shadeIds = ReadLongArray fstream subChunkEnd
			)
			-- W3D_CHUNK_PRELIT_VERTEX (0x24) is a transparent wrapper around the same
			-- material chunks (MATERIAL_INFO/SHADERS/VERTEX_MATERIALS/TEXTURES/MATERIAL_PASS)
			-- a non-prelit mesh has at top level. Descend by simply NOT advancing past the
			-- wrapper -- the next loop iteration reads the inner chunks. Matches 1.16b.
			-- Other prelit variants (UNLIT/MULTI_PASS/MULTI_TEXTURE) are skipped intentionally.
			0x00000024: ()  -- W3D_CHUNK_PRELIT_VERTEX: descend (no-op; do not advance)
			--0x00000023:	--W3D_CHUNK_PRELIT_UNLIT
			--0x00000025:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_PASS
			--0x00000026:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_TEXTURE
			0x00000028:	--W3D_CHUNK_MATERIAL_INFO	--materials information, pass count, etc (contains W3dMaterialInfoStruct)
			(
				matlheader = ReadMeshMaterialSetInfo fstream subChunkEnd
			)
			0x00000029:	--W3D_CHUNK_SHADERS	--shaders (array of W3dShaderStruct's)
			(
				shaders = ReadMeshShaderArray fstream subChunkEnd
			)
			0x0000002A:	--W3D_CHUNK_VERTEX_MATERIALS	--wraps the vertex materials
			(
				vertMatls = ReadMeshVertMaterialArray fstream subChunkEnd
			)
			0x00000030:	--W3D_CHUNK_TEXTURES	--wraps all of the texture info
			(
				textures = ReadMeshTextureArray fstream subChunkEnd
			)
			0x00000038:	--W3D_CHUNK_MATERIAL_PASS	--wraps the information for a single material pass
			(
				matlPass = ReadMeshMaterialPass fstream subChunkEnd
				append matlPasses matlPass
			)
			--0x00000058:	--W3D_CHUNK_DEFORM	// mesh deform or 'damage' information.
			--0x00000080:	--W3D_CHUNK_PS2_SHADERS	// Shader info specific to the Playstation 2.
			--0x00000090:	--W3D_CHUNK_AABTREE	// Axis-Aligned Box Tree for hierarchical polygon culling
			--0x00000026:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_TEXTURE	// optional lightmapped multi-texture material chunk wrapper
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
		------ debug start ------
		--print ("type: " + bit.intAsHex chunkType)
		--print ("pos: " + bit.intAsHex (ftell fstream))
		--print ("end: " + bit.intAsHex chunkEnd)
		------ debug end ------
	)
	result = W3dMesh header verts normals vertInfs faces shadeIds matlheader shaders vertMatls textures matlPass matlPasses
	--return result
)

fn ReadHLodHeader fstream =
(
	version = ReadLong fstream #unsigned
	lodCount = ReadLong fstream #unsigned
	hlodName = ReadFixedString fstream
	hierarchyName = ReadFixedString fstream	-- name of the hierarchy tree to use (\0 if none)
	result = HLodHeader version lodCount hlodName hierarchyName
)

fn ReadHLodObjectArrayHeader fstream =
(
	modelCount = ReadLong fstream #unsigned
	maxScreenSize = ReadLong fstream #unsigned	-- if model is bigger than this, switch to higher lod.
	result = HLodObjectArrayHeader modelCount maxScreenSize
)

fn ReadHLodObject fstream chunkEnd =
(
	pivotIndex = ReadLong fstream #unsigned
	lodName = ReadString fstream
	fseek fstream chunkEnd #seek_set -- skip object full name 32 bytes 
	result = HLodObject pivotIndex lodName
)

fn ReadHLodObjectArray fstream chunkEnd=
(
	lodObjs = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		subChunkEnd = (ftell fstream) + chunkSize
		case chunkType of
		(
			0x00000703:	--W3D_CHUNK_HLOD_SUB_OBJECT_ARRAY_HEADER	// info on the objects in this level of detail array
			(
				header = ReadHLodObjectArrayHeader fstream
			)
			0x00000704:	--W3D_CHUNK_HLOD_SUB_OBJECT	// an object in this level of detail array
			(
				lodObjs[lodObjs.count+1] = ReadHLodObject fstream subChunkEnd
			)
			
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	result = HLodObjectArray header lodObjs
)

fn ReadHLod fstream chunkEnd =
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		subChunkEnd = (ftell fstream) + chunkSize
		case chunkType of
		(
			0x00000701:	--W3D_CHUNK_HLOD_HEADER	// general information such as name and version
			(
				header = ReadHLodHeader fstream
			)
			0x00000702:	--W3D_CHUNK_HLOD_LOD_ARRAY	// wrapper around the array of objects for each level of detail
			(
				lodArray = ReadHLodObjectArray fstream subChunkEnd 
			)
			--0x00000705:	--W3D_CHUNK_HLOD_AGGREGATE_ARRAY	// array of aggregates, contains W3D_CHUNK_SUB_OBJECT_ARRAY_HEADER and W3D_CHUNK_SUB_OBJECT_ARRAY
			--0x00000706:	--W3D_CHUNK_HLOD_PROXY_ARRAY	// array of proxies, used for application-defined purposes, provides a name and a bone.
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	result = HLod header lodArray
)

fn ReadAABox fstream chunkEnd =
(
	version = ReadLong fstream #unsigned
	attrs = ReadLong fstream #unsigned
	boxName = ReadLongFixedString fstream
	boxColor = ReadColor fstream
	centre = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	extent = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	result = AABox version attrs boxName boxColor centre extent
)

rollout rltDepStackController "Dependencies" width:200 height:120
(
	dropDownList ddlMeshes "Meshes:" pos:[17,17] width:160 height:40
	dropDownList ddlBones "Bones:" pos:[17,65] width:160 height:40
	button btnSelectAllBones "Pick All Bones" pos:[33,120] width:127 height:36
	
	on ddlMeshes selected sel do
	(
		boneNames = #()
		for i=1 to (depStacks[ddlMeshes.selection]).Dependencies.count do
		( append boneNames (depStacks[ddlMeshes.selection]).Dependencies[i].locBone.name )
		ddlBones.items = boneNames
		select((depStacks[ddlMeshes.selection]).locMesh)
		subobjectLevel = 1
	)
	
	on ddlBones selected sel do
	(
		if wwBinding do
		( modPanel.setCurrentObject (depStacks[ddlMeshes.selection]).locMesh.modifiers[#WWSkin_Binding] )
		if not wwBinding do
		( select((depStacks[ddlMeshes.selection]).locMesh) )
		subobjectLevel = 1
		
		(depStacks[ddlMeshes.selection]).locMesh.selectedVerts = (depStacks[ddlMeshes.selection]).Dependencies[ddlBones.selection].Vertices
	)
	
	on btnSelectAllBones pressed do
	(
		clearSelection()
		for m=1 to depStacks.count do
		(
			for p=1 to ((depStacks[m]).Dependencies).count do
			( selectMore(((depStacks[m]).Dependencies[p]).locBone) )
		)
	)
)

--interface
--utility w3dimport "Coolfile W3D Importer"
function cfW3DImporter w3dfilename splitMeshes autoBindType batch debugOutput useW3DMatl ignoreErrors fixNormals tga2dds fixVertices noMultiMat tga2ddsRev useWWSkin externalSkelFile importExtendedW3D pivotType =
(
	-- Bump this when editing the script so you can confirm Max is running the expected copy.
	-- Bump alongside any non-trivial logic change so the debug log makes the loaded version obvious.
	local importerVersion = "v17"
	if debugOutput do
	(
		format "=================================================\n"
		format " w3dimporter % loaded from script\n" importerVersion
		format " CABAL: initializing %\n" (bit.intAsHex (random 0 0x7FFFFFFF))
		format "=================================================\n"
	)

	-- for the interface in future version
	userSeparateMaterial = false

	global anim = undefined
	global cmpAnim = undefined
	-- Last skeleton w3d that was successfully loaded by cfW3DImporter (whether
	-- auto-derived from the HLOD/anim header or picked via Use External Skeleton).
	-- Lets follow-up operations (e.g. Batch Anims to XAF) reuse the same rig
	-- without re-prompting the user for a file they already chose.
	global lastUsedSkeletonFile = undefined
	global hier = undefined
	global meshes = #()
	global hlodSet = undefined
	global pickbox = undefined
	
	global gmPivots = #()
	global gmMeshes = #()
	
	global depStacks = #()
	global wwBinding = true
	
	global maxBinding = false
	global wwBinding = false
	
	-- Binding type (if any)
	-- When ckbUseWWSkin (Advanced tab) is checked, override the radio-button
	-- choice and force the 2023 WWSkin path, which constructs the WSM via the
	-- C++ class registered in max2w3d.dle (class name "WWSkin"). The legacy
	-- `wwSkinSpaceWarp` constructor never resolves on a 2023 toolchain build,
	-- so the historical fallback would always have hit Max's native Skin.
	if useWWSkin then
	(
		-- WSM Object classes get a `SpaceWarp` suffix in MAXScript: our C++
		-- InternalName "WWSkin" is exposed as the constructor `WWSkinSpaceWarp`.
		try ( wwSkin = WWSkinSpaceWarp pos:[0,0,-15] isSelected:off )
		catch
		(
			wwSkin = undefined
			messageBox "Use 2023WWSkin is checked but creating a WWSkin Space Warp failed.\nMake sure max2w3d.dle (Phase 1+ of the WWSkin port) is installed and registered." title:"WWSkin unavailable" beep:true
		)
		if wwSkin != undefined then
		(
			wwBinding = true
			maxBinding = false
		)
		else
		(
			-- Fall back to native Skin so the import doesn't silently produce an unrigged mesh.
			wwBinding = false
			maxBinding = true
		)
	)
	else if (autoBindType > 0) do
	(
		maxBinding = (autoBindType == 1)
		if (autoBindType == 2) do
		(
			wwBinding = true
			try ( wwSkin = wwSkinSpaceWarp pos:[0,0,-15] isSelected:off )
			catch
			(
				wwBinding = false
				if (queryBox "Unable to create WWSkin!\nW3d binding cannot be done!\n\nWould you like to use 3dsMax's skin modifier instead?" title:"Error!" beep:true) then
				( maxBinding = true )
				else (maxBinding = false)
			)
		)
	)
	
	fn GetHLodObject searchName =
	(
		for i = 1 to hlodSet.lodArray.lodObjects.count do
		( if searchName == hlodSet.lodArray.lodObjects[i].lodName do return hlodSet.lodArray.lodObjects[i] )
		result = undefined
	)
	
	if not batch do
	( w3dfilename = getOpenFileName caption:"W3D Import Dialogue" types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|" )
	
	if w3dfilename != undefined then
	(
		fstream = fopen w3dfilename "rb"  ---binary 
		fseek fstream 0 #seek_end
		filesize = ftell fstream
		fseek fstream 0 #seek_set
		
		while (ftell fstream < filesize) do -- or (CounterAux < 100)) do
		(
			chunkType = ReadLong fstream #unsigned
			------ debug start ------
			--chunkSize = ReadLong fstream
			--print (bit.intAsHex chunkSize)
			--chunkSize = GetChunkSize(chunkSize)
			--print (bit.intAsHex chunkSize)
			------ debug end ------
			chunkSize = GetChunkSize(ReadLong fstream #unsigned)
			chunkEnd = (ftell fstream) + chunkSize
			
			------ debug start ------
			--chunkSize = ReadLong fstream
			--chunkSize = GetChunkSize(chunkSize)
			--print (bit.intAsHex chunkSize)
			------ debug end ------
			
			case chunkType of
			(
				0x00000000:	--W3D_CHUNK_MESH	-- mesh definition
				( meshes[meshes.count+1] = ReadMesh fstream chunkEnd )
				
				0x00000100:	--W3D_CHUNK_HIERARCHY	-- hierarchy tree definition
				( hier = ReadHierarchy fstream chunkEnd )
				
				0x00000200:	--W3D_CHUNK_ANIMATION	-- hierarchy animation data
				( anim = ReadAnimation fstream chunkEnd )
				
				0x00000280:	--W3D_CHUNK_COMPRESSED_ANIMATION	// compressed hierarchy animation data
				( cmpAnim = ReadCompressedAnimation fstream chunkEnd )
				
				--0x000002C0:	--W3D_CHUNK_MORPH_ANIMATION	// hierarchy morphing animation data (morphs between poses, for facial animation)
				--0x00000300:	--W3D_CHUNK_HMODEL	// blueprint for a hierarchy model
				--0x00000400:	--W3D_CHUNK_LODMODEL	// blueprint for an LOD model
				--0x00000420:	--W3D_CHUNK_COLLECTION	// collection of render object names
				--0x00000440:	--W3D_CHUNK_POINTS	// array of W3dVectorStruct's.  May appear in meshes, hmodels, lodmodels, or collections.
				--0x00000460:	--W3D_CHUNK_LIGHT	// description of a light
				--0x00000500:	--W3D_CHUNK_EMITTER	// description of a particle emitter
				--0x00000600:	--W3D_CHUNK_AGGREGATE	// description of an aggregate object
				
				0x00000700:	--W3D_CHUNK_HLOD	// description of an HLod object (see HLodClass)
				( hlodSet = ReadHLod fstream chunkEnd )
				
				0x00000740:	--W3D_CHUNK_BOX	// defines an collision box render object (W3dBoxStruct)
				( pickbox = ReadAABox fstream chunkEnd )
				
				--0x00000741:	--W3D_CHUNK_SPHERE
				--0x00000742:	--W3D_CHUNK_RING
				--0x00000750:	--W3D_CHUNK_NULL_OBJECT	// defines a NULL object (W3dNullObjectStruct)
				--0x00000800:	--W3D_CHUNK_LIGHTSCAPE	// wrapper for lights created with Lightscape.
				--0x00000900:	--W3D_CHUNK_DAZZLE	// wrapper for a glare object.  Creates halos and flare lines seen around a bright light source
				--0x00000A00:	--W3D_CHUNK_SOUNDROBJ	// description of a sound render object
				
				default:
				( fseek fstream chunkSize #seek_cur )
			)
			------ debug start ------
			--print (bit.intAsHex filesize)
			--print (bit.intAsHex (ftell fstream))
			------ debug end ------
		)
		fclose fstream

		-- HLOD header carries the name of the rig the meshes were authored
		-- against. We only treat it as "needs an external skeleton" when:
		--   * the HTree name differs from the HLOD's own Name (a name that
		--     matches the HLOD name means the rig lives inside this same w3d,
		--     no external file required), AND
		--   * the HTree name ends in "_SKL" (W3D convention for a standalone
		--     skeleton file -- e.g. "S_GDIINF_SKL").
		-- Anything else (e.g. terrain props pointing at themselves, or files
		-- with a non-_SKL hier reference) skips the popup.
		local hlodHTreeName = undefined
		if hlodSet != undefined and hlodSet.header != undefined do
		(
			local hn = hlodSet.header.hierarchyName
			local hlodN = hlodSet.header.hlodName
			if hn != undefined and (hn as string) != "" do
			(
				local hnStr   = hn as string
				local hlodStr = if hlodN == undefined then "" else (hlodN as string)
				local sameAsHlod = (stricmp hnStr hlodStr) == 0
				local endsWithSkl = false
				if hnStr.count >= 4 do
					endsWithSkl = (stricmp (substring hnStr (hnStr.count - 3) 4) "_SKL") == 0
				if (not sameAsHlod) and endsWithSkl do
					hlodHTreeName = hn
			)
		)

		-- In batch mode, skip files that contain neither meshes nor animation
		-- channels (probably empty / not-actually-w3d). Anim-only files
		-- legitimately have meshes.count == 0 and must still load their
		-- skeleton + keyframes, so check anim/cmpAnim too.
		if (batch and meshes.count == 0 and anim == undefined and cmpAnim == undefined) do
		( return() )
		
		-- Resolve the skeleton source. Three cases, in priority order:
		--   1. user-picked external skeleton (Use External Skeleton checkbox) — always wins
		--   2. main w3d already had a hierarchy chunk → keep it as-is
		--   3. neither — auto-derive from hlodSet/anim/cmpAnim header, prompt if missing
		local skelfilename = undefined
		if externalSkelFile != undefined then
		(
			skelfilename = externalSkelFile
			-- Force re-load even if the main w3d already had a hier so the
			-- external file's bones win.
			hier = undefined
		)
		else if hier == undefined then
		(
			if hlodSet != undefined do skelfilename = (getFilenamePath w3dfilename) + hlodSet.header.hierarchyName + ".w3d"

			if anim != undefined then
				skelfilename = (getFilenamePath w3dfilename) + anim.header.skelName + ".w3d"
			else
				if cmpAnim != undefined do skelfilename = (getFilenamePath w3dfilename) + cmpAnim.header.skelName + ".w3d"

			if (skelfilename != undefined) and (not (doesFileExist skelfilename)) then
				skelfilename = getOpenFileName caption:("Import Skeleton W3D: " + (getFilenameFile skelfilename)) types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|"
		)

		if skelfilename != undefined then
		(
			fstream = fopen skelfilename "rb"  -- binary
			fseek fstream 0 #seek_end
			local filesize = ftell fstream

			fseek fstream 0 #seek_set
			while (ftell fstream < filesize) do
			(
				chunkType = ReadLong fstream #unsigned
				chunkSize = GetChunkSize(ReadLong fstream #unsigned)
				chunkEnd = (ftell fstream) + chunkSize
				case chunkType of
				(
					0x00000100:	--W3D_CHUNK_HIERARCHY	-- hierarchy tree definition
					( hier = ReadHierarchy fstream chunkEnd )
					default:
					( fseek fstream chunkSize #seek_cur )
				)
			)
			fclose fstream
			-- Remember which skeleton file backed this import; the batch tools
			-- key off this so the user doesn't get asked again.
			lastUsedSkeletonFile = skelfilename
		)

		-- Whenever the HLOD header names an external rig, surface it to the
		-- user with the same message the V1.16 reference importer used. We
		-- fire this regardless of whether the auto-derive step actually found
		-- the skeleton on disk -- the import succeeds either way, but the
		-- popup makes the dependency obvious (matches the user-visible
		-- behaviour they asked for on infantry models, which always declare
		-- an HTree even when the rig file is alongside).
		if hlodHTreeName != undefined do
			messageBox ("Meshes in this model require a skeleton file. \n\n Skeleton expected by model: " + (hlodHTreeName as string))

		if debugOutput do
		(
			if hier == undefined then
			(
				if hlodHTreeName != undefined then
					format " expected skeleton (HTree name): %\n" hlodHTreeName
				else
					format " expected skeleton (HTree name): none found\n"
			)
		)
		------ debug start ------
		--print hier
		--print anim
		--print meshes
		--print hlodSet
		------ debug end ------
		
		-- create pivots(bones)
		if hier != undefined then
		(
			-- pivotType: 1 = Max Bone (default original importer), 2 = Sphere
			-- (V1.16-style green geom -- visually distinctive but exporter
			-- treats it as render geometry, beware), 3 = Point Helper (tiny
			-- helper marker; max2w3d.dle's IsW3DBoneNode picks it up via
			-- HELPER_CLASS_ID so Select Bones / W3D export classify it as a
			-- bone instead of geometry). Default to Bone if undefined for
			-- back-compat with any external callers.
			local _pt = pivotType
			if _pt == undefined do _pt = 1
			local pivotBoxColor = (color 0 255 0)

			-- Auto-size pivot markers from the imported meshes' bbox so they
			-- stay readable across infantry / vehicles / structures without a
			-- per-import scale knob. Bones aren't affected -- Max sizes those
			-- automatically from parent-to-child distance.
			-- Done by walking raw vertex data (meshes[].verts is already
			-- populated; mesh nodes don't exist yet).
			local pivotBoxSize = 0.075   -- fallback for empty / no-vert files
			local pointMarkerSize = 0.15 -- ditto
			if meshes.count > 0 do
			(
				local minX = 1e30; local minY = 1e30; local minZ = 1e30
				local maxX = -1e30; local maxY = -1e30; local maxZ = -1e30
				for mi = 1 to meshes.count do
				(
					if meshes[mi].verts == undefined do continue
					for v in meshes[mi].verts do
					(
						if v.x < minX do minX = v.x
						if v.y < minY do minY = v.y
						if v.z < minZ do minZ = v.z
						if v.x > maxX do maxX = v.x
						if v.y > maxY do maxY = v.y
						if v.z > maxZ do maxZ = v.z
					)
				)
				if maxX > minX do
				(
					local diag = length (Point3 (maxX - minX) (maxY - minY) (maxZ - minZ))
					-- ~1% of the bbox diagonal: 1.8u infantry -> ~0.02-0.03,
					-- which is too small visually, so clamp to a useful floor.
					-- Use 2% for spheres, 4% for point helpers (point markers
					-- read smaller per-unit because they're line drawings).
					pivotBoxSize    = amax #(diag * 0.02, 0.5)
					pointMarkerSize = amax #(diag * 0.04, 1.0)
				)
			)

			-- Wrap the whole creation loop in `with redraw off` -- otherwise
			-- each `point ... cross:true` triggers a viewport redraw per pivot
			-- and infantry rigs (30-80 pivots) feel sluggish, especially the
			-- helper paths whose display has more elements than a Bone.
			with redraw off
			(
				--pivotName, parentID, pos, eulerAngles, rotation
				-- to skip the ROOTTRANSFORM, i starts at 2
				for i = 2 to hier.pivots.count do
				(
					curPivot = undefined
					case _pt of
					(
						2: -- Sphere (V1.16 reference look)
						(
							if hier.pivots[i].parentID == 0 then
							(
								curPivot = sphere name:hier.pivots[i].pivotName \
									radius:pivotBoxSize segs:4 wirecolor:pivotBoxColor
								in coordsys world curPivot.rotation = hier.pivots[i].rotation
								in coordsys world curPivot.pos = hier.pivots[i].pos
							)
							else
							(
								curPivot = sphere name:hier.pivots[i].pivotName \
									parent:gmPivots[hier.pivots[i].parentID] \
									radius:pivotBoxSize segs:4 wirecolor:pivotBoxColor
								in coordsys parent curPivot.rotation = hier.pivots[i].rotation
								in coordsys parent curPivot.pos = hier.pivots[i].pos
							)
							setUserProp curPivot "bone" "yes"
						)
						3: -- Point helper (recognised as a W3D bone by max2w3d.dle)
						(
							if hier.pivots[i].parentID == 0 then
							(
								curPivot = point name:hier.pivots[i].pivotName \
									size:pointMarkerSize cross:true box:true \
									axisTripod:false centermarker:false \
									wirecolor:pivotBoxColor
								in coordsys world curPivot.rotation = hier.pivots[i].rotation
								in coordsys world curPivot.pos = hier.pivots[i].pos
							)
							else
							(
								curPivot = point name:hier.pivots[i].pivotName \
									parent:gmPivots[hier.pivots[i].parentID] \
									size:pointMarkerSize cross:true box:true \
									axisTripod:false centermarker:false \
									wirecolor:pivotBoxColor
								in coordsys parent curPivot.rotation = hier.pivots[i].rotation
								in coordsys parent curPivot.pos = hier.pivots[i].pos
							)
						)
						default: -- 1: Max Bone (original behaviour)
						(
							if hier.pivots[i].parentID == 0 then
							(
								curPivot = bone name:hier.pivots[i].pivotName
								in coordsys world curPivot.rotation = hier.pivots[i].rotation
								in coordsys world curPivot.pos = hier.pivots[i].pos
							)
							else
							(
								curPivot = bone name:hier.pivots[i].pivotName parent:gmPivots[hier.pivots[i].parentID]
								in coordsys parent curPivot.rotation = hier.pivots[i].rotation
								in coordsys parent curPivot.pos = hier.pivots[i].pos
							)
						)
					)
					append gmPivots curPivot
				)
			)
		)
		
		-- create meshes
		for i = 1 to meshes.count do
		(
			gmVerts = meshes[i].verts
			gmFaces = #()
			for f = 1 to meshes[i].faces.count do
				gmFaces[f] = meshes[i].faces[f].vertIds + 1 -- gMax array lower-limit is 1 while w3d's is 0
	
			-- create a mesh
			gmMeshes[i] = mesh name:meshes[i].header.meshName vertices:gmVerts faces:gmFaces
			-- Set by the No Multi-Mat splitter when it replaces gmMeshes[i] with a split node;
			-- guards the post-material UV/normal loops that assume the original mesh size.
			local noMultiMatHandled = false
			
			-- create a new material or apply an exist one and
			-- Build a real W3D material (custom plugin material, class "W3D") via the
			-- wwSet* MAXScript API exposed by max2w3d.dle. Mirrors 1.16b: the W3D
			-- material round-trips losslessly to .w3d on export.
			--
			-- When a TEXTURE_STAGE has per-face TEXTURE_IDS (count > 1) the mesh uses
			-- multiple textures within one pass; that maps to a 3ds Max Multimaterial
			-- with one W3D submaterial per unique texture-tuple and a per-face matID.
			if (meshes[i].vertMatls != undefined) and (meshes[i].vertMatls.count > 0) and (meshes[i].matlPasses != undefined) and (meshes[i].matlPasses.count > 0) then
			(
				-- Debug: log which mesh is being built and which textures it
				-- references. Toggle off by `w3dDebugMaterials = false` in the listener.
				if w3dDebugMaterials != false do
				(
					local _texList = ""
					if meshes[i].textures != undefined do
						for _t = 1 to meshes[i].textures.count do
							_texList = _texList + (if _t > 1 then ", " else "") + meshes[i].textures[_t].txFileName
					format "[w3d import] mesh % vmats=% passes=% textures=[%]\n" meshes[i].header.meshName meshes[i].vertMatls.count meshes[i].matlPasses.count _texList
				)
				local vmCount       = meshes[i].vertMatls.count
				local passCount     = meshes[i].matlPasses.count
				local shaderCount   = if meshes[i].shaders  != undefined then meshes[i].shaders.count  else 0
				local textureCount  = if meshes[i].textures != undefined then meshes[i].textures.count else 0
				local sortLevel     = if meshes[i].header != undefined and meshes[i].header.sortLevel != undefined then meshes[i].header.sortLevel else 0
				local nf            = if meshes[i].faces != undefined then meshes[i].faces.count else 0
				local surfaceType   = 0
				if (meshes[i].faces != undefined) and (meshes[i].faces.count > 0) and (meshes[i].faces[1].attrs != undefined) do
					surfaceType = meshes[i].faces[1].attrs

				-- Detect per-face TEXTURE_IDS in any pass/stage. count > 1 => per-face.
				local hasPerFaceTex = false
				for pIdx = 1 to passCount while not hasPerFaceTex do
				(
					local mp = meshes[i].matlPasses[pIdx]
					if mp.textureStages != undefined do
						for sIdx = 1 to mp.textureStages.count while not hasPerFaceTex do
						(
							local ts = mp.textureStages[sIdx]
							if ts.txIds != undefined and ts.txIds.count > 1 do hasPerFaceTex = true
						)
				)

				-- Helper: populate w3dMatl's per-pass parameters. txOverride is an
				-- array indexed [pIdx][sIdx] -> 1-based texture index, or undefined
				-- to fall back to the first txId of each stage.
				fn applyW3DPassParams w3dMatl mesh passCount vmCount shaderCount textureCount txOverride =
				(
					for pIdx = 1 to passCount do
					(
						local pass = pIdx - 1
						local mp = mesh.matlPasses[pIdx]

						local vmIdx = 1
						if mp.vmIds != undefined and mp.vmIds.count > 0 do vmIdx = mp.vmIds[1] + 1
						if vmIdx < 1 do vmIdx = 1
						if vmIdx > vmCount do vmIdx = vmCount
						local vm   = mesh.vertMatls[vmIdx]
						local vinf = vm.vmInfo

						wwSetMatFlags     w3dMatl pass vinf.attrs
						if vm.vmArgs0 != undefined and vm.vmArgs0 != "" do wwSetMapperArgs w3dMatl pass 0 vm.vmArgs0
						if vm.vmArgs1 != undefined and vm.vmArgs1 != "" do wwSetMapperArgs w3dMatl pass 1 vm.vmArgs1
						wwSetAmbient      w3dMatl pass vinf.ambient
						wwSetDiffuse      w3dMatl pass vinf.diffuse
						wwSetSpecular     w3dMatl pass vinf.specular
						wwSetEmissive     w3dMatl pass vinf.emissive
						wwSetShininess    w3dMatl pass vinf.shininess
						wwSetOpacity      w3dMatl pass vinf.opacity
						wwSetTranslucency w3dMatl pass vinf.translucency

						local shIdx = 1
						if mp.shaderIds != undefined and mp.shaderIds.count > 0 do shIdx = mp.shaderIds[1] + 1
						if shIdx < 1 do shIdx = 1
						if shaderCount > 0 and shIdx <= shaderCount and mesh.shaders[shIdx] != undefined do
						(
							local sh = mesh.shaders[shIdx]
							wwSetDepthCompare  w3dMatl pass sh.depthCompare
							wwSetWriteZBuffer  w3dMatl pass (sh.depthMask != 0)
							wwSetDestBlend     w3dMatl pass sh.destBlend
							wwSetPriGradient   w3dMatl pass sh.priGradient
							wwSetSecGradient   w3dMatl pass sh.secGradient
							wwSetSrcBlend      w3dMatl pass sh.srcBlend
							wwSetDetailColor   w3dMatl pass sh.detailColorFunc
							wwSetDetailAlpha   w3dMatl pass sh.detailAlphaFunc
							wwSetAlphaTestFlag w3dMatl pass (sh.alphaTest != 0)
						)

						if mp.textureStages != undefined do
						(
							for sIdx = 1 to mp.textureStages.count do
							(
								local stage = sIdx - 1
								local ts = mp.textureStages[sIdx]
								local tIdx = -1
								if txOverride != undefined and txOverride[pIdx] != undefined and txOverride[pIdx][sIdx] != undefined do
									tIdx = txOverride[pIdx][sIdx]
								if tIdx < 0 do
								(
									tIdx = 1
									if ts.txIds != undefined and ts.txIds.count > 0 do tIdx = ts.txIds[1] + 1
								)
								if tIdx >= 1 and tIdx <= textureCount and mesh.textures[tIdx] != undefined do
								(
									local tex = mesh.textures[tIdx]
									wwSetTexture w3dMatl tex.txFileName ((pass * 2) + stage)
									if tex.txInfo != undefined do
									(
										wwSetTexFlags  w3dMatl pass stage tex.txInfo.attrs
										wwSetAnimType  w3dMatl pass stage tex.txInfo.animType
										wwSetFrames    w3dMatl pass stage tex.txInfo.frameCount
										wwSetFrameRate w3dMatl pass stage tex.txInfo.frameRate
									)
								)
							)
						)
					)
				)

				-- faceTexIndex: read face f's 0-based texture index for (pIdx,sIdx).
				fn faceTexIndex mesh pIdx sIdx f =
				(
					local mp = mesh.matlPasses[pIdx]
					if mp.textureStages == undefined or mp.textureStages.count < sIdx then 0 else
					(
						local ts = mp.textureStages[sIdx]
						if ts.txIds == undefined or ts.txIds.count == 0 then 0
						else if ts.txIds.count == 1 then ts.txIds[1]
						else if f >= 1 and f <= ts.txIds.count then ts.txIds[f]
						else ts.txIds[1]
					)
				)

				local firstMatName = meshes[i].vertMatls[1].vmName

				-- uvTargets: list of W3D materials that need wwSetUV calls in
				-- the per-stage UV loop below. Single-material path: 1 entry.
				-- Multimaterial path: every W3D submat (they share UVs).
				local uvTargets = #()

				if hasPerFaceTex then
				(
					-- Build face -> tupleKey, dedupe to submat list, then assign matIDs.
					local tupleKeys = #()
					local faceMatID  = #()
					if nf > 0 do faceMatID[nf] = 1
					for f = 1 to nf do
					(
						local key = ""
						for pIdx = 1 to passCount do
						(
							local mp = meshes[i].matlPasses[pIdx]
							local stageCnt = if mp.textureStages != undefined then mp.textureStages.count else 0
							for sIdx = 1 to stageCnt do
							(
								local ti = faceTexIndex meshes[i] pIdx sIdx f
								key = key + (ti as string) + ","
							)
							key = key + ";"
						)
						local idx = findItem tupleKeys key
						if idx == 0 do
						(
							append tupleKeys key
							idx = tupleKeys.count
						)
						faceMatID[f] = idx
					)

					local multi = Multimaterial name:firstMatName numsubs:tupleKeys.count
					append sceneMaterials multi

					for k = 1 to tupleKeys.count do
					(
						local txOverride = #()
						local passParts = filterString tupleKeys[k] ";"
						for pIdx = 1 to passParts.count do
						(
							local stageParts = filterString passParts[pIdx] ","
							txOverride[pIdx] = #()
							for sIdx = 1 to stageParts.count do
								txOverride[pIdx][sIdx] = ((stageParts[sIdx] as integer) + 1)
						)

						local subName = firstMatName
						if txOverride[1] != undefined and txOverride[1][1] != undefined and txOverride[1][1] >= 1 and txOverride[1][1] <= textureCount and meshes[i].textures[txOverride[1][1]] != undefined do
						(
							local fn0 = meshes[i].textures[txOverride[1][1]].txFileName
							if fn0 != undefined and fn0 != "" do subName = fn0
						)

						local sub = W3D name:subName
						wwSetSortLevel   sub sortLevel
						wwSetSurfaceType sub surfaceType
						wwSetPassCount   sub passCount
						applyW3DPassParams sub meshes[i] passCount vmCount shaderCount textureCount txOverride

						multi.materialList[k] = sub
						multi.names[k] = subName
						append uvTargets sub
					)

					gmMeshes[i].material = multi
					for f = 1 to nf do setFaceMatID gmMeshes[i] f faceMatID[f]
				)
				else
				(
					-- Build a fresh W3D material per mesh. Reuse-by-name was removed
					-- because vertex-material names (e.g. "Strip Concrete", "Red
					-- Cement") repeat across meshes that reference different texture
					-- files -- matching by name caused the second mesh to inherit
					-- the first mesh's textures.
					local w3dMatl = W3D name:firstMatName
					append sceneMaterials w3dMatl
					wwSetSortLevel   w3dMatl sortLevel
					wwSetSurfaceType w3dMatl surfaceType
					wwSetPassCount   w3dMatl passCount
					applyW3DPassParams w3dMatl meshes[i] passCount vmCount shaderCount textureCount undefined
					gmMeshes[i].material = w3dMatl
					append uvTargets w3dMatl
				)

				-- Per-stage UV channel assignment + UV data setup. Each TEXTURE_STAGE
				-- carries its own per-vertex UVs in stage.txCoords. Stage 0 of pass 0
				-- maps to Max channel 1 by convention; subsequent stages get unique
				-- channel IDs so the W3D material's two-stage param blocks pick the
				-- right coordinates.
				local nv = meshes[i].verts.count

				-- Count how many UV channels we'll consume so we can grow the mesh's map
				-- count up front. meshOp.setMapSupport on a channel beyond getNumMaps()
				-- raises "Map channel index outside valid range" -- the map count must
				-- be expanded with meshop.setNumMaps before any per-channel write.
				local channelsNeeded = 0
				for pIdx = 1 to passCount do
				(
					local mp = meshes[i].matlPasses[pIdx]
					if mp.textureStages != undefined do
					(
						for sIdx = 1 to mp.textureStages.count do
						(
							local ts = mp.textureStages[sIdx]
							if ts.txCoords != undefined and ts.txCoords.count > 0 do
								channelsNeeded += 1
						)
					)
				)
				if channelsNeeded > 0 do
				(
					-- Channels are 1-based for user maps; getNumMaps returns the highest
					-- valid index + 1, so for channels 1..N we need NumMaps = N + 1.
					local needNumMaps = channelsNeeded + 1
					if (meshop.getNumMaps gmMeshes[i]) < needNumMaps do
						meshop.setNumMaps gmMeshes[i] needNumMaps keep:true
				)

				local uvChannel = 1
				for pIdx = 1 to passCount do
				(
					local pass = pIdx - 1
					local mp = meshes[i].matlPasses[pIdx]
					if mp.textureStages != undefined do
					(
						for sIdx = 1 to mp.textureStages.count do
						(
							local stage = sIdx - 1
							local ts = mp.textureStages[sIdx]
							if ts.txCoords != undefined and ts.txCoords.count > 0 do
							(
								meshOp.setMapSupport gmMeshes[i] uvChannel true
								meshOp.setNumMapVerts gmMeshes[i] uvChannel ts.txCoords.count
								for v = 1 to ts.txCoords.count do
								(
									-- ReadMeshTextureCoordArray returns Point2 values, not W3dMeshTextureCoord
									-- structs, so the UV components live at .x / .y (not .u / .v).
									local tc = ts.txCoords[v]
									meshOp.setMapVert gmMeshes[i] uvChannel v (Point3 tc.x tc.y 0)
								)
								meshOp.setNumMapFaces gmMeshes[i] uvChannel nf
								for f = 1 to nf do
								(
									meshOp.setMapFace gmMeshes[i] uvChannel f gmFaces[f]
								)
								for tgt in uvTargets do wwSetUV tgt pass stage uvChannel
								uvChannel += 1
							)
						)
					)
				)
			)
			
			-- (Legacy single-stage texture-coord block removed: the W3D-material
			-- builder above already sets per-stage UVs via meshOp.setMapVert and
			-- registers the channel with wwSetUV.)

			-- set vert normals at v1.03
			if not noMultiMatHandled do
			(
				for v = 1 to meshes[i].normals.count do
				( setNormal gmMeshes[i] v meshes[i].normals[v] )
			)

			-- Fix Vertices and Fix Normals were originally applied here, but they interfere
			-- with the skin-binding pass that runs after this loop:
			--   - Fix Vertices welds verts (changes vertex count) -> Skin's per-vertex
			--     weights would address the wrong verts.
			--   - Fix Normals adds an Edit Normals modifier, then Skin gets stacked on top
			--     of it -> Skin sees the post-Edit-Normals topology and the weights bind
			--     to the wrong points.
			-- Both passes are deferred to after the skin binding loop (search for the
			-- "deferred Fix Vertices / Fix Normals" block below).

			--find the exist pivot of the mesh and replace it.
			if (hlodSet != undefined) and (hier != undefined) then
			(
				meshLod = GetHLodObject (meshes[i].header.containerName + "." + meshes[i].header.meshName)
				if meshLod != undefined then
				(
					p = meshLod.pivotIndex
					if p > 0 then  -- the mesh is in ROOTTRANSFORM when p == 0
					(
						if gmPivots[p] != undefined then
						(
							if gmMeshes[i].name == gmPivots[p].name then
							(
								gmMeshes[i].parent = gmPivots[p].parent
								gmMeshes[i].rotation = gmPivots[p].rotation  --have not to swap the line of rotation and pos, why?
								gmMeshes[i].pos = gmPivots[p].pos
								for c = gmPivots[p].children.count to 1 by -1 do
								(													   --only want to rearrange the hierarchy
									if(gmPivots[p].children[c] != undefined) then 
									( gmPivots[p].children[c].parent = gmMeshes[i] )   --not the pivot positions of the children
								)
								disusedPivot = gmPivots[p]
								gmPivots[p] = gmMeshes[i]
								delete disusedPivot
							)
							else
							(
								gmMeshes[i].parent = gmPivots[p]
								gmMeshes[i].rotation = gmPivots[p].rotation  --have not to swap the line of rotation and pos, why?
								gmMeshes[i].pos = gmPivots[p].pos
							)
						)
					)
				)
			)
			
			-- fix the influenced verts in infantry skin at v1.03
			if (meshes[i].vertInfs != undefined) and (hier != undefined) then
			(
				for v = 1 to meshes[i].vertInfs.boneIds1.count do
				(
					p = meshes[i].vertInfs.boneIds1[v]
					-- please enable these 2 lines when unexpected error happen here 
					if p <= 0 do continue
					if gmPivots[p] == undefined do continue
					in coordsys gmPivots[p] setVert gmMeshes[i] v meshes[i].verts[v]
				)
				
				--to show influenced info at v1.08
				--format "%: \n" meshes[i].header.meshName - obsolete, replaced with the 'Auto-Bind' option
				
				if (autoBindType > 0) do
				( currDeps = #() )
				
				for p = 1 to hier.pivots.count do
				(
					ivs = #()
					for v = 1 to (meshes[i].vertInfs.boneIds1.count - 1) do
					( if meshes[i].vertInfs.boneIds1[v] == (p - 1) do (append ivs v) )
					
					if splitMeshes do
					(
						if (ivs.count > 1) do
						(
							hide gmMeshes[i]
							tmpChunk = meshop.detachVerts gmMeshes[i] ivs delete:false asMesh:true
							
							newChunk = Editable_Mesh()
							newChunk.mesh = tmpChunk
							newChunk.name = hier.pivots[p].pivotName
							newChunk.parent = gmPivots[p-1]
							update newChunk
						)
						update
					)
					
					if (autoBindType > 0) do
					(
						if (ivs.count > 1) do
						(
							try
							(
								currDep = Dependency gmPivots[p-1] ivs
								append currDeps currDep
							)
							catch
							( continue )
						)
					)
					--(format "% %: %\n" p hier.pivots[p].pivotName ivs)
				)
				
				if (autoBindType > 0) do
				(
					currDepStack = DependencyStack gmMeshes[i] currDeps
					append depStacks currDepStack
				)
			)
		)
		
		--somehow when inserting max bones directly to the code generating gmPivots some parts of meshes start flipping around.
		--can't be bothered to look for the reason why, so helper bones are replaced with max ones here.
		
		if maxBinding do
		(
			for i=1 to gmPivots.count do
			(
				if (classOf gmPivots[i] != Bone) do continue
				maxPivot = boneSys.createBone [0,0,0] [0,0,0] [0,0,1]
				maxPivot.width = 0.5
				maxPivot.height = 0.5
				
				maxPivot.name = gmPivots[i].name
				maxPivot.transform = gmPivots[i].transform
				maxPivot.showLinks = true
				
				if (hier.pivots[i+1].parentID != 0) do
				( maxPivot.parent = gmPivots[hier.pivots[i+1].parentID] )
				
				obsltPivot = gmPivots[i]
				gmPivots[i] = maxPivot
				delete obsltPivot
			)
		)
		
		if (anim != undefined) and (hier != undefined) then
		(
			if anim.header.frameCount > 1 then
				animationRange = interval 1 anim.header.frameCount -- edited at v1.07
			else
				animationRange = interval 0 1
			frameRate = anim.header.frameRate
			
			for i = 1 to anim.channels.count do
			(
				curChn = anim.channels[i]
				--curObj = execute ("$'" + hier.pivots[curChn.pivotID + 1].pivotName + "'") -- at v1.02. it should be curChn.pivotID + 1 at v1.04
				
				try
				( curObj = gmPivots[curChn.pivotID] ) -- test at v1.04
				catch
				( continue )
				--print curObj
				--print curChn
				if curObj != undefined then
				(
					datumPos = hier.pivots[curChn.pivotID + 1].pos
					datumRot = hier.pivots[curChn.pivotID + 1].rotation
					case curChn.flags of
					(
						0x0000: --ANIM_CHANNEL_X = 0
						(
							curObj.pos.controller = linear_position()
							curKey = addNewKey curObj.pos.controller 0
							curKey.value = datumPos
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								k = getKeyIndex curObj.pos.controller (f + 1)
								if k == 0 then
								(
									curKey = addNewKey curObj.pos.controller (f + 1)
									curKey.value = datumPos
								)
								else
								( curKey = curObj.pos.controller.keys[k] )
								curKey.value += [curChn.values[(f - curChn.firstFrame + 1)], 0, 0] * (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	curKey = addNewKey curObj.pos.controller (curChn.lastFrame + 2)
							--)
							--else
							--(
							--	curKey = addNewKey curObj.pos.controller (curChn.firstFrame)
							--)
							--curKey.value = datumPos
						)
						0x0001: --ANIM_CHANNEL_Y = 1
						(
							curObj.pos.controller = linear_position()
							curKey = addNewKey curObj.pos.controller 0
							curKey.value = datumPos
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								k = getKeyIndex curObj.pos.controller (f + 1)
								if k == 0 then
								(
									curKey = addNewKey curObj.pos.controller (f + 1)
									curKey.value = datumPos
								)
								else
								(
									curKey = curObj.pos.controller.keys[k]
								)
								curKey.value += [0, curChn.values[(f - curChn.firstFrame + 1)], 0] * (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.lastFrame + 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.lastFrame + 1)
							--		curKey.value = datumPos
							--	)
							--)
							--else
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.firstFrame - 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.firstFrame - 1)
							--		curKey.value = datumPos
							--	)
							--)
						)
						0x0002: --ANIM_CHANNEL_Z = 2
						(
							curObj.pos.controller = linear_position()
							curKey = addNewKey curObj.pos.controller 0
							curKey.value = datumPos
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								k = getKeyIndex curObj.pos.controller (f + 1)
								if k == 0 then
								(
									curKey = addNewKey curObj.pos.controller (f + 1)
									curKey.value = datumPos
								)
								else
								(
									curKey = curObj.pos.controller.keys[k]
								)
								curKey.value += [0, 0, curChn.values[(f - curChn.firstFrame + 1)]] * (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.lastFrame + 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.lastFrame + 1)
							--		curKey.value = datumPos
							--	)
							--)
							--else
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.firstFrame - 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.firstFrame - 1)
							--		curKey.value = datumPos
							--	)
							--)
						)
					--	--0x0003: --ANIM_CHANNEL_XR = 3
					--	--(
					--	--	curKey = addNewKey curObj.pos.controller f
					--	--	curKey.value.x = curChn.values[(f - curChn.firstFrame + 1)]
					--	--)
					--	--0x0004: --ANIM_CHANNEL_YR = 4
					--	--(
					--	--	curKey = addNewKey curObj.pos.controller f
					--	--	curKey.value.y = curChn.values[(f - curChn.firstFrame + 1)]
					--	--)
					--	--0x0005: --ANIM_CHANNEL_ZR = 5
					--	--(
					--	--	curKey = addNewKey curObj.pos.controller f
					--	--	curKey.value.z = curChn.values[(f - curChn.firstFrame + 1)]
					--	--)
						0x0006: --ANIM_CHANNEL_Q = 6
						(
							curObj.rotation.controller = linear_rotation()
							curKey = addNewKey curObj.rotation.controller 0
							curKey.value = datumRot
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								curKey = addNewKey curObj.rotation.controller (f + 1)
								curKey.value = curChn.values[(f - curChn.firstFrame + 1)] - (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	k = getKeyIndex curObj.rotation.controller (curChn.lastFrame + 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.rotation.controller (curChn.lastFrame + 1)
							--		curKey.value = datumRot
							--	)
							--)
							--else
							--(
							--	k = getKeyIndex curObj.rotation.controller (curChn.firstFrame - 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.rotation.controller (curChn.firstFrame - 1)
							--		curKey.value = datumRot
							--	)
							--)
						)
					)
				)
			)
			
			for i = 1 to anim.bitchannels.count do
			(
				curChn = anim.bitchannels[i]
				-- curObj = execute ("$'" + hier.pivots[curChn.pivotID].pivotName + "'") -- at v1.02. it should be curChn.pivotID + 1 at v1.04
				-- pivotID == 0 = ROOTTRANSFORM (not in gmPivots). Skip out-of-range
				-- pivots cleanly unless Strict Mode is enabled by the user.
				if ignoreErrors do
				(
					if curChn.pivotID < 1 or curChn.pivotID > gmPivots.count do continue
				)
				curObj = gmPivots[curChn.pivotID] -- test at v1.04
				if curObj != undefined then
				(
					case curChn.flags of
					(
						0x0000: --BIT_CHANNEL_VIS = 0	// turn meshes on and off depending on anim frame.
						(
							defVal = (curChn.defaultVal > 0)
							-- A single On_Off key at frame 0 evaluates to "off" across
							-- the playable timeline (1..N), which on re-export bakes
							-- "hidden everywhere" into the bit channel and makes the
							-- model invisible in-game. Pre-scan to detect whether the
							-- channel is constant; if so, leave .visibility static and
							-- don't create any controller at all - the exporter then
							-- defaults to "always visible" which matches the file.
							hasTransition = false
							byteIdx = 1
							bitIdx = 1
							for f = curChn.firstFrame to curChn.lastFrame while not hasTransition do
							(
								curVal = bit.get (curChn.values[byteIdx]) bitIdx
								if curVal != defVal then hasTransition = true
								bitIdx += 1
								if bitIdx > 8 then
								(
									byteIdx += 1
									bitIdx = 1
								)
							)
							if not hasTransition then
							(
								curObj.visibility = defVal
							)
							else
							(
								curObj.visibility = defVal
								curObj.visibility.controller = On_Off()
								prevVal = defVal
								byteIdx = 1
								bitIdx = 1
								for f = curChn.firstFrame to curChn.lastFrame do
								(
									curVal = bit.get (curChn.values[byteIdx]) bitIdx
									if curVal != prevVal then
									(
										curKey = addNewKey curObj.visibility.controller f
										curKey.value = curVal
										prevVal = curVal
									)
									bitIdx += 1
									if bitIdx > 8 then
									(
										byteIdx += 1
										bitIdx = 1
									)
								)
							)
							--curKey = addNewKey curObj.visibility.controller (curChn.lastFrame + 1)
							--curKey.selected = defVal
						)
						--0x0001: --BIT_CHANNEL_TIMECODED_VIS
					)
				)
			) --for end
		) --if end
		
		/*for i=1 to cmpAnim.channels.count do
		(
			if cmpAnim.channels[i].type == 2 then
				format "%;%;%\n" cmpAnim.channels[i].pivotID cmpAnim.channels[i].increment gmPivots[cmpAnim.channels[i].pivotID].name
			else
				format "%;%;%\n" cmpAnim.channels[i].pivotID cmpAnim.channels[i].timeCodesCount gmPivots[cmpAnim.channels[i].pivotID].name
		)*/
		
		if (cmpAnim != undefined) and (hier != undefined) then
		(
			if cmpAnim.header.frameCount < 1 do cmpAnim.header.frameCount = 1
			animationRange = interval 1 cmpAnim.header.frameCount -- edited at v1.07
			frameRate = cmpAnim.header.frameRate
			
			case cmpAnim.header.flavour of
			(
				0x0: --ANIM_FLAVOUR_TIMECODED
				(
					for i = 1 to cmpAnim.channels.count do
					(
						curChn = cmpAnim.channels[i]
						try
						( curObj = gmPivots[curChn.pivotID] ) -- test at v1.04
						catch
						( continue )
						if curObj != undefined then
						(
							datumPos = hier.pivots[curChn.pivotID + 1].pos
							datumRot = hier.pivots[curChn.pivotID + 1].rotation
							
							-- added in 1.12, handles channels with a single value
							if curChn.values.count == 1 do
							(
								curChn.values[curChn.values.count+1] = AnimationTimeCodedKey cmpAnim.header.frameCount curChn.values[curChn.values.count].keyValue
								curChn.timeCodesCount += 1
							)
							
							case curChn.flags of
							(
								0x0000: --ANIM_CHANNEL_TIMECODED_X = 0
								(
									curObj.pos.controller = linear_position()
									curKey = addNewKey curObj.pos.controller 0
									curKey.value = datumPos
									if cmpAnim.channels[i].type == 1 then
									(
										for t=1 to curChn.timeCodesCount do
										(
											fCurr = curChn.values[t].keyTime
											vCurr = curChn.values[t].keyValue
											
											if t > 1 then
											(
												fPrev = curChn.values[t-1].keyTime + 1
												vPrev = curChn.values[t-1].keyValue
											)
											else
											(
												fPrev = fCurr
												vPrev = vCurr
											)
											
											if (fCurr >= 0) and (fPrev >= 0) then
											(
												for f = fPrev to fCurr do
												(
													--print f
													k = getKeyIndex curObj.pos.controller (f + 1)
													if k == 0 then
													(
														curKey = addNewKey curObj.pos.controller (f + 1)
														curKey.value = datumPos
													)
													else
													( curKey = curObj.pos.controller.keys[k] )
													
													step = vPrev + ((vCurr - vPrev) * (f - fPrev + 1) / (fCurr - fPrev + 1))
													curKey.value += [step, 0, 0] * (inverse datumRot)
												)
											)
										)
									)
									else if cmpAnim.channels[i].type == 2 do
									(
										k = getKeyIndex curObj.pos.controller 1
										if k == 0 then
										(
											curKey = addNewKey curObj.pos.controller 1
											curKey.value = datumPos + [curChn.initDelta,0,0] * (inverse datumRot)
										)
										else
										(
											curKey = curObj.pos.controller.keys[k]
											curKey.value += [curChn.initDelta,0,0] * (inverse datumRot)
										)
										prevKey = curKey
										
										byteIdx = 1
										bitIdx = 1
										
										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
										--for b = 1 to cmpAnim.channels[i].values.count do
										--( print cmpAnim.channels[i].values[b] )
										for t = 2 to cmpAnim.channels[i].values.count do
										(
											
											for bitIdx = 1 to 8 do
											(
												curVal = bit.get (curChn.values[byteIdx]) bitIdx
												--print curVal
											)
										)
											/*if curVal then
											(
												curKey = addNewKey curObj.pos.controller t
												temp = [curChn.increment,0,0] * (inverse datumRot)
												break()
												curKey.value = prevKey.value + [curChn.increment,0,0]
												prevKey = curKey
												break()
											)
											else
											(
												curKey = addNewKey curObj.pos.controller t
												curKey.value = prevKey.value - [curChn.increment,0,0]
												prevKey = curKey
											)*/
										--)
									)
								)
								0x0001: --ANIM_CHANNEL_TIMECODED_Y = 1
								(
									curObj.pos.controller = linear_position()
									curKey = addNewKey curObj.pos.controller 0
									curKey.value = datumPos
									if cmpAnim.channels[i].type == 1 do
									(
										for t = 1 to curChn.timeCodesCount do
										(
											fNext = curChn.values[t].keyTime
											vNext = curChn.values[t].keyValue
											if t > 1 then
											(
												fPrev = curChn.values[(t - 1)].keyTime + 1
												vPrev = curChn.values[(t - 1)].keyValue
											)
											else
											(
												fPrev = fNext
												vPrev = vNext
											)

											if (fNext >= 0) and (fPrev >= 0) then
											(
												for f = fPrev to fNext do
												(
													k = getKeyIndex curObj.pos.controller (f + 1)
													if k == 0 then
													(
														curKey = addNewKey curObj.pos.controller (f + 1)
														curKey.value = datumPos
													)
													else
													(
														curKey = curObj.pos.controller.keys[k]
													)
													step = vPrev + ((vNext - vPrev) * (f - fPrev + 1) / (fNext - fPrev + 1))
													curKey.value += [0, step, 0] * (inverse datumRot)
												)
											)
										)
									)
									if cmpAnim.channels[i].type == 2 do
									(
										k = getKeyIndex curObj.pos.controller 1
										if k == 0f then
										(
											curKey = addNewKey curObj.pos.controller 1
											curKey.value = datumPos + [0,curChn.initDelta,0] * (inverse datumRot)
										)
										else
										(
											curKey = curObj.pos.controller.keys[k]
											curKey.value += [0,curChn.initDelta,0] * (inverse datumRot)
										)
										
										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
									)
								)
								0x0002: --ANIM_CHANNEL_TIMECODED_Z = 2
								(
									curObj.pos.controller = linear_position()
									curKey = addNewKey curObj.pos.controller 0
									curKey.value = datumPos
									if cmpAnim.channels[i].type == 1 do
									(
										for t = 1 to curChn.timeCodesCount do
										(
											fNext = curChn.values[t].keyTime
											vNext = curChn.values[t].keyValue
											if t > 1 then
											(
												fPrev = curChn.values[(t - 1)].keyTime + 1
												vPrev = curChn.values[(t - 1)].keyValue
											)
											else
											(
												fPrev = fNext
												vPrev = vNext
											)
											if (fNext >= 0) and (fPrev >= 0) then
											(
												for f = fPrev to fNext do
												(
													k = getKeyIndex curObj.pos.controller (f + 1)
													if k == 0 then
													(
														curKey = addNewKey curObj.pos.controller (f + 1)
														curKey.value = datumPos
													)
													else
													(
														curKey = curObj.pos.controller.keys[k]
													)
													step = vPrev + ((vNext - vPrev) * (f - fPrev + 1) / (fNext - fPrev + 1))
													curKey.value += [0, 0, step] * (inverse datumRot)
												)
											)
										)
									)
									if cmpAnim.channels[i].type == 2 do
									(
										k = getKeyIndex curObj.pos.controller 1
										if k == 0f then
										(
											curKey = addNewKey curObj.pos.controller 1
											curKey.value = datumPos + [0,0,curChn.initDelta] * (inverse datumRot)
										)
										else
										(
											curKey = curObj.pos.controller.keys[k]
											curKey.value += [0,0,curChn.initDelta] * (inverse datumRot)
										)
										
										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
									)
								)
								0x0006: --ANIM_CHANNEL_TIMECODED_Q = 6
								(
									curObj.rotation.controller = linear_rotation()
									curKey = addNewKey curObj.rotation.controller 0
									curKey.value = datumRot
									if cmpAnim.channels[i].type == 1 do
									(
										for t = 1 to curChn.timeCodesCount do
										(
											f = curChn.values[t].keyTime
											curKey = addNewKey curObj.rotation.controller (f + 1)
											curKey.value = curChn.values[t].keyValue - (inverse datumRot)
											
											/*prvKey = getKey curObj.rotation.controller (curObj.rotation.controller.keys.count - 1)
											if (prvKey.time < curKey.time - 1) do
											(
												for q = (prvKey.time + 1) to (curKey.time - 1) do
												(
													prvCoef = ((curKey.time - q) as Integer)/((curKey.time - prvKey.time) as Integer)
													curCoef = ((q - prvKey.time) as Integer)/((curKey.time - prvKey.time) as Integer)
													
													x = curCoef*curKey.value.x + prvCoef*prvKey.value.x
													y = curCoef*curKey.value.y + prvCoef*prvKey.value.y
													z = curCoef*curKey.value.z + prvCoef*prvKey.value.z
													w = curCoef*curKey.value.w + prvCoef*prvKey.value.w
													
													newKey = addNewKey curObj.rotation.controller q
													newKey.value = Quat x y z w
												)
											)*/
										)
									)
									if cmpAnim.channels[i].type == 2 do
									(
										curKey = addNewKey curObj.rotation.controller 1
										curKey.value = datumRot + curChn.initDelta
										
										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
									)
								)
								0x000F:
								(
								)
							)
						)
					)
					--for i = 1 to cmpAnim.bitchannels.count do
					--(
					--	curChn = cmpAnim.bitchannels[i]
					--	curObj = gmPivots[curChn.pivotID] -- test at v1.04
					--	if curObj != undefined then
					--	(
					--		case curChn.flags of
					--		(
					--			--0x0000: --BIT_CHANNEL_VIS = 0	// turn meshes on and off depending on anim frame.
					--			0x0001: --BIT_CHANNEL_TIMECODED_VIS = 1
					--			(
					--				defVal = (curChn.defaultVal > 0)
					--				curObj.visibility = defVal
					--				curObj.visibility.controller = On_Off()
					--				curKey = addNewKey curObj.visibility.controller 0
					--				curKey.selected = defVal
					--				prevVal = defVal
					--				byteIdx = 1
					--				bitIdx = 1
					--				for t = 1 to curChn.timeCodesCount do
					--				(
					--					f = curChn.values[t].time
					--					curVal = bit.get (curChn.values[byteIdx]) bitIdx
					--					if curVal != prevVal then
					--					(
					--						curKey = addNewKey curObj.visibility.controller (f + 1)
					--						curKey.selected = curVal
					--						prevVal = curVal
					--					)
					--					bitIdx += 1
					--					if bitIdx > 8 then
					--					(
					--						byteIdx += 1
					--						bitIdx = 1							
					--					)
					--				)
					--			)
					--		)
					--	)
					--) --for end
				)
				0x1: --ANIM_FLAVOUR_ADAPTIVE_DELTA
				(
				)
				--0x2: --ANIM_FLAVOUR_VALID
			)
		) --if end
					
		if wwBinding do
		(
			for m = 1 to meshes.count do
			(
				if (meshes[m].vertInfs != undefined) do
				(
					--convertTo gmMeshes[m] Editable_Poly
					--convertTo gmMeshes[m] Editable_Mesh
					bindSpaceWarp gmMeshes[m] wwSkin
					
					for p = 1 to gmPivots.count do
					(
						if gmPivots[p] != undefined do
							wwAddBone gmPivots[p] gmMeshes[m]
					)
					
					for v = 1 to (meshes[m].vertInfs.boneIds1.count) do
					(
						--print v
						--print meshes[m].vertInfs.boneIds1[v]
						--print meshes[m].vertInfs.boneWgts1[v]
						--print meshes[m].vertInfs.boneIds2[v]
						--print meshes[m].vertInfs.boneWgts2[v]
						--print "---------------"
						
						-- Bone-index guards: vertInfs reference into gmPivots, but if the
						-- skeleton came from a different file (Use External Skeleton) or
						-- the model contains bone indices past the loaded pivot count,
						-- the lookup yields `undefined`. wwSetBoneWeight requires a real
						-- INode, so skip the influence rather than throwing.
						local b1 = meshes[m].vertInfs.boneIds1[v]
						if (b1 > 0) and (b1 <= gmPivots.count) do
						(
							curBone = gmPivots[b1]
							if curBone != undefined do
								wwSetBoneWeight gmMeshes[m] (v - 1) 1 curBone meshes[m].vertInfs.boneWgts1[v]
						)
						local b2 = meshes[m].vertInfs.boneIds2[v]
						if (b2 > 0) and (b2 <= gmPivots.count) and (meshes[m].vertInfs.boneWgts1[v] < 100) do
						(
							curBone = gmPivots[b2]
							if curBone != undefined do
								wwSetBoneWeight gmMeshes[m] (v - 1) 2 curBone meshes[m].vertInfs.boneWgts2[v]
						)
					)
				)
			)
		)
			
		if maxBinding do
		(
			for m = 1 to meshes.count do
			(
				if (meshes[m].vertInfs != undefined) do
				(
					local currSkin = skin()
					addModifier gmMeshes[m] currSkin
					currSkin.bone_Limit = 2
					
					setCommandPanelTaskMode #modify
					modPanel.setCurrentObject currSkin ui:true
					
					for p = 1 to gmPivots.count do
					( skinOps.addBone currSkin gmPivots[p] 0 ) --0 for no redrawing
					
					max modify mode
					redrawViews()
					
					for v = 1 to (meshes[m].vertInfs.boneIds1.count) do
					(
						if (meshes[m].vertInfs.boneIds1[v] > 0) do
						(
							skinOps.unNormalizeVertex currSkin v false
							skinOps.selectBone currSkin meshes[m].vertInfs.boneIds1[v]
							skinOps.replaceVertexWeights currSkin v meshes[m].vertInfs.boneIds1[v] 1
							skinOps.setVertexWeights currSkin v meshes[m].vertInfs.boneIds1[v] 1							
						)
						
						if (meshes[m].vertInfs.boneIds2[v] > 0) and (meshes[m].vertInfs.boneWgts1[v] < 100) do
						(
							skinOps.selectBone currSkin meshes[m].vertInfs.boneIds2[v]
							skinOps.setVertexWeights currSkin v meshes[m].vertInfs.boneIds2[v] (0.01*meshes[m].vertInfs.boneWgts2[v])
						)
					)
				)
			)
		)
		
		-- ---- deferred Fix Vertices / Fix Normals ----
		-- Run after wwBinding / maxBinding so that Skin or W3DSkin (which were applied to
		-- gmMeshes[m] during the binding pass) see the original topology when they bind,
		-- and the geometry edits below sit on top of (or beneath) Skin without changing
		-- the vert count Skin already weighted to.
		if fixVertices do
		(
			for i = 1 to gmMeshes.count do
			(
				if gmMeshes[i] == undefined do continue

				-- Skip skinned meshes: Skin's per-vertex weights are bound to specific
				-- vertex indices, and welding renumbers/removes verts, which would
				-- silently break the binding. Skinning is the higher-priority feature.
				local isSkinned = false
				try
				(
					for m in gmMeshes[i].modifiers while not isSkinned do
					(
						local cn = (classOf m) as string
						if cn == "Skin" or cn == "Physique" do isSkinned = true
					)
				) catch ()

				if isSkinned then
				(
					if debugOutput do
						format "  -> Fix Vertices [%]: skipped (mesh has Skin/Physique; weld would break weights)\n" gmMeshes[i].name
					continue
				)

				try
				(
					local vBefore = gmMeshes[i].numVerts
					local elementId = 0

					for f = 1 to gmMeshes[i].numFaces do
						setFaceSmoothGroup gmMeshes[i] f 0
					update gmMeshes[i]

					local visited = #{}
					for f = 1 to gmMeshes[i].numFaces do
					(
						if visited[f] do continue
						elementId += 1
						local elemFaces = meshOp.getElementsUsingFace gmMeshes[i] #{f}
						local sg = bit.shift 1 (mod (elementId - 1) 32)
						for ef in elemFaces do
						(
							setFaceSmoothGroup gmMeshes[i] ef sg
							visited[ef] = true
						)
					)
					update gmMeshes[i]

					meshOp.weldVertsByThreshold gmMeshes[i] #all 0.01
					update gmMeshes[i]

					if debugOutput do
					(
						try
						(
							local vAfter = gmMeshes[i].numVerts
							local welded = vBefore - vAfter
							local sgSpan = if elementId <= 32 then (elementId as string) else ("32 (cycled, " + (elementId as string) + " elements)")
							format "  -> Fix Vertices [%]: cleared SGs, found % element(s), assigned SG span=%, welded %->% verts (-% removed) at threshold 0.01\n" gmMeshes[i].name elementId sgSpan vBefore vAfter welded
						)
						catch ( format "  -> Fix Vertices [%]: completed but debug print failed: %\n" gmMeshes[i].name (getCurrentException()) )
					)
				)
				catch
				(
					if debugOutput do
						format "  -> Fix Vertices [%]: FAILED with error: %\n" gmMeshes[i].name (getCurrentException())
				)
			)
		)

		-- "Import extended w3d information": surface the W3D_MESH_HEADER3 Attributes
		-- (Geometry Type + Hide/2-Sided/Shadow/Shatter/Tangents/Prelit/AlwaysDynLight,
		-- Collision Physical/Projectile/Vis/Camera/Vehicle) and SortLevel into each
		-- imported mesh's W3D Tools panel via the wwSetFlags / wwSetSorting primitives
		-- in max2w3d.dle. Without this pass, imported meshes always read back as the
		-- default (Normal, no flags) regardless of what the source .w3d encoded.
		-- W3DBOX (collision box) attrs are decoded by the same wwSetFlags helper.
		if importExtendedW3D do
		(
			if debugOutput do
				format "=== Import extended W3D Info: applying mesh-header attrs ===\n"
			for i = 1 to gmMeshes.count do
			(
				if gmMeshes[i] == undefined do continue
				if meshes[i] == undefined or meshes[i].header == undefined do continue
				local hdr = meshes[i].header
				if debugOutput do
				(
					format "  [%] read: attrs=% sortLevel=% (props: %)\n" \
						gmMeshes[i].name (bit.intAsHex hdr.attrs) hdr.sortLevel (cfDecodeW3DAttrs hdr.attrs)
				)
				try
				(
					wwSetFlags gmMeshes[i] hdr.attrs
					wwSetSorting gmMeshes[i] hdr.sortLevel
					if debugOutput do
						format "  [%] applied: wwSetFlags + wwSetSorting OK\n" gmMeshes[i].name
				)
				catch
				(
					if debugOutput do
						format "  [%] FAILED to apply (rebuilt max2w3d.dle required): %\n" gmMeshes[i].name (getCurrentException())
				)
			)
		)

		if fixNormals do
		(
			for i = 1 to gmMeshes.count do
			(
				if gmMeshes[i] == undefined do continue
				try
				(
					-- Smoothing-group baseline write goes to the base mesh; if a modifier is
					-- already on the stack (Skin or the Edit_Mesh from Fix Vertices), the base
					-- mesh is locked. Wrap in try/catch and fall through — Edit Normals' Reset
					-- still works without it, just from the modifier's own normal data.
					-- Skip the SG=1 baseline when Fix Vertices ran: that pass assigned a
					-- unique SG per element to preserve hard edges across the weld, and
					-- forcing every face to SG 1 here would smooth across those element
					-- seams. Reset will recompute from whatever SGs are in place.
					if not fixVertices do
					(
						try
						(
							for f = 1 to gmMeshes[i].numFaces do
								setFaceSmoothGroup gmMeshes[i] f 1
							update gmMeshes[i]
						) catch ()
					)

					local enMod = Edit_Normals()
					addModifier gmMeshes[i] enMod

					local prevSel = selection as array
					select gmMeshes[i]
					max modify mode

					subobjectLevel = 0
					modPanel.setCurrentObject enMod
					subobjectLevel = 1
					modPanel.setCurrentObject enMod

					local nrmCount = enMod.EditNormalsMod.GetNumNormals()
					if nrmCount > 0 do
					(
						enMod.EditNormalsMod.SetSelection #{1..nrmCount}
						enMod.EditNormalsMod.Reset()
					)

					subobjectLevel = 0

					try
					(
						if prevSel.count == 0 then clearSelection() else select prevSel
					) catch ()
				) catch ()
			)
		)
		-- ---- end deferred ----

		if pickbox != undefined then
		(
			sName = pickbox.boxName
			dotPos = findString sName "."
			if (dotPos != undefined) and (dotPos < sName.count) do (sName = subString sName (dotPos + 1) -1)
			gmBox = Box name:sName pos:pickbox.centre 
			gmBox.width = pickbox.extent.x 
			gmBox.length = pickbox.extent.y 
			gmBox.height = pickbox.extent.z
			gmBox.wirecolor = pickbox.boxColor

			-- W3DBOX attrs (W3D_BOX_ATTRIBUTE_ALIGNED/ORIENTED + W3D_MESH_FLAG_COLLISION_TYPE_*)
			-- get decoded by the same wwSetFlags helper used for meshes.
			if importExtendedW3D do
			(
				if debugOutput do
					format "  [%] read: box attrs=% (props: %)\n" \
						gmBox.name (bit.intAsHex pickbox.attrs) (cfDecodeW3DAttrs pickbox.attrs)
				try
				(
					wwSetFlags gmBox pickbox.attrs
					if debugOutput do
						format "  [%] applied: wwSetFlags OK\n" gmBox.name
				)
				catch
				(
					if debugOutput do
						format "  [%] FAILED to apply (rebuilt max2w3d.dle required): %\n" gmBox.name (getCurrentException())
				)
			)
		)
		
		if batch do
		(
			saveMaxFile(substring w3dfilename 1 (w3dfilename.count-4))
			resetMaxFile #noPrompt
		)
	)
)

macroscript ImportW3D
	category: "W3D Importer/Processor"
	buttontext: "Import W3D"
	tooltip: "W3D Importer"
	icon:#("gMax",2)
( createDialog rltMain )

rollout rltMain "W3D Importer" width:177 height:292
(
	button btnW3DImporter "Import a file" pos:[25,17] width:127 height:36

	-- Tab strip: clicking these toggles which group of controls is visible below.
	-- (MAXScript rollouts have no native tab control, but a radio-button strip is the
	-- conventional substitute and behaves exactly like tabs.)
	radiobuttons rbgTab "" pos:[12,60] width:153 height:18 labels:#("Basic", "Advanced") default:1 columns:2

	-- BASIC tab controls
	checkbox ckbSplitDependencies "Split by dependencies" pos:[25,85] width:127 height:15 enabled:true
	checkbox ckbAutoBind "Auto-Bind" pos:[25,102] width:127 height:15 checked:true
	radiobuttons rbgAutoBind "Auto-Bind type" pos:[17,127] width:162 height:30 enabled:true labels:#("max skin", "w3d skin") default:1 columns:2
	checkbox ckbBatchProcessing "Batch processing" pos:[25,165] width:127 height:15 checked:false
	-- Pivot representation: 1 = Max Bone (default, original importer behaviour),
	-- 2 = Sphere (V1.16-style; renders as a small green geom but max2w3d.dle
	-- treats it as render geometry, NOT a W3D bone -- exporter / Select Bones
	-- won't see it), 3 = Point Helper (recommended alternative -- HELPER_CLASS_ID
	-- so W3D Tools' Select Bones picks it up and it stays out of the geometry
	-- export).
	dropDownList ddlPivotType "Pivots:" pos:[25,182] width:152 height:40 items:#("Bone (default)", "Sphere", "Point Helper (slow)") selection:1 tooltip:"How to represent imported hierarchy pivots in the scene. Bone = Max bone (original). Sphere = V1.16-style green sphere (visual only -- gets exported as geometry!). Point Helper = small marker that W3D Tools recognises as a bone."

	-- ADVANCED tab controls (overlap the same vertical space; visibility toggled by rbgTab)
	checkbox ckbDebugOutput "Debug Output" pos:[25,85] width:127 height:15 checked:false visible:false
	checkbox ckbUseW3DMatl "Use W3D Materials" pos:[25,102] width:127 height:15 checked:false visible:false
	checkbox ckbImportExtendedW3D "Import extended W3D Info" pos:[25,119] width:152 height:15 checked:false visible:false tooltip:"Restore each mesh's W3D Tools settings (Geometry Type, geometry flags like Hide / 2-Sided / Shadow / Shatter / Tangents / Prelit / AlwaysDynLight, Collision flags, Static Sort Level) from the imported .w3d's MESH_HEADER3 Attributes. Requires the rebuilt max2w3d.dle (provides wwSetFlags / wwSetSorting)."
	checkbox ckbIgnoreErrors "Strict Mode" pos:[25,136] width:127 height:15 checked:false visible:false tooltip:"Halt the import if a channel references an invalid pivot ID, instead of skipping it."
	checkbox ckbFixNormals "Fix Normals" pos:[25,153] width:127 height:15 checked:false visible:false tooltip:"Destructive fallback for W3D files with broken normals: forces all faces to one smoothing group, then resets normals via Edit_Normals."
	checkbox ckbTga2Dds "tga2DDS" pos:[25,170] width:65 height:15 checked:false visible:false tooltip:"Rewrite .tga texture references to .dds (extension only; filename preserved)"
	checkbox ckbTga2DdsRev "rev" pos:[92,170] width:60 height:15 checked:false enabled:false visible:false tooltip:"Reverse: rename .dds to .tga (only available while tga2DDS is enabled)"
	checkbox ckbFixVertices "Fix Vertices" pos:[25,187] width:127 height:15 checked:false visible:false tooltip:"Per-element smoothing groups, then weld vertices at 0.01 threshold (preserves smoothing across the weld)"
	checkbox ckbNoMultiMat "No Multi-Mat" pos:[25,204] width:127 height:15 checked:false visible:false tooltip:"Split meshes that would use a multi-material into separate meshes (one per texture), each with a single material assigned"
	checkbox ckbUseWWSkin "Use 2023WWSkin" pos:[25,221] width:127 height:15 checked:false visible:false tooltip:"Bind skinned meshes using the 2023-toolchain WWSkin (Westwood Space Warp + WWSkin Binding) instead of Max's native Skin modifier. Requires the rebuilt max2w3d.dle (Phase 1+ of the WWSkin port)."
	checkbox ckbUseExternalSkel "Use External Skeleton" pos:[25,238] width:127 height:15 checked:false visible:false tooltip:"Load the bone hierarchy from an external .w3d file (e.g. a shared skeleton) instead of the main w3d / auto-derive."
	button btnSelectSkeleton "Select Skeleton" pos:[25,255] width:152 height:18 enabled:false visible:false

	-- Path to the user-picked external skeleton w3d. Lives at rollout scope
	-- so it survives across multiple imports without re-prompting.
	local externalSkeletonFile = undefined

	on btnW3DImporter pressed do
	(
		if ckbBatchProcessing.checked then
		(
			fldrPath = getSavePath()
			if (fldrPath != undefined) do
			(
				w3dFiles = getFiles(fldrPath + "\\*.w3d")
				for i=1 to w3dFiles.count do
				( cfW3DImporter w3dFiles[i] ckbSplitDependencies.checked rbgAutoBind.state true ckbDebugOutput.checked ckbUseW3DMatl.checked (not ckbIgnoreErrors.checked) ckbFixNormals.checked ckbTga2Dds.checked ckbFixVertices.checked ckbNoMultiMat.checked ckbTga2DdsRev.checked ckbUseWWSkin.checked (if ckbUseExternalSkel.checked then externalSkeletonFile else undefined) ckbImportExtendedW3D.checked ddlPivotType.selection )
			)
		)
		else
		( cfW3DImporter undefined ckbSplitDependencies.checked rbgAutoBind.state false ckbDebugOutput.checked ckbUseW3DMatl.checked (not ckbIgnoreErrors.checked) ckbFixNormals.checked ckbTga2Dds.checked ckbFixVertices.checked ckbNoMultiMat.checked ckbTga2DdsRev.checked ckbUseWWSkin.checked (if ckbUseExternalSkel.checked then externalSkeletonFile else undefined) ckbImportExtendedW3D.checked ddlPivotType.selection )
	)

	-- enable rev only while tga2DDS is on; uncheck it when tga2DDS is turned off
	on ckbTga2Dds changed st do
	(
		ckbTga2DdsRev.enabled = st
		if not st do ckbTga2DdsRev.checked = false
	)

	-- Fix Normals and Fix Vertices are mutually exclusive: Fix Vertices' per-element
	-- SGs preserve hard edges across the weld, while Fix Normals forces every face
	-- to a single SG and resets normals. Running both produces smoothing artifacts
	-- across element seams, so enabling one disables the other.
	on ckbFixNormals changed st do
	(
		if st do ckbFixVertices.checked = false
	)
	on ckbFixVertices changed st do
	(
		if st do ckbFixNormals.checked = false
	)
	
	on ckbSplitDependencies changed state do
	( if ckbSplitDependencies.checked then ckbAutoBind.checked = false )
	
	on ckbAutoBind changed state do
	(
		if ckbAutoBind.checked then
		(
			ckbSplitDependencies.checked = false

			rbgAutoBind.enabled = true
			rbgAutoBind.state = 1

			ckbBatchProcessing.enabled = true

			-- Mutually exclusive with the 2023 WWSkin override on the Advanced
			-- tab — checking Auto-Bind clears it so users aren't confused why
			-- the radio choice is being ignored.
			if ckbUseWWSkin.checked do ckbUseWWSkin.checked = false
		)
		else
		(
			rbgAutoBind.enabled = false
			rbgAutoBind.state = 0

			ckbBatchProcessing.checked = false
			ckbBatchProcessing.enabled = false
		)
	)

	-- 2023 WWSkin override: when on, the binding path is forced to the new
	-- WWSkin Space Warp regardless of Basic-tab Auto-Bind, so reflect that in
	-- the UI by disabling the Basic Auto-Bind controls.
	on ckbUseWWSkin changed state do
	(
		if ckbUseWWSkin.checked then
		(
			ckbAutoBind.checked   = false
			ckbAutoBind.enabled   = false
			rbgAutoBind.enabled   = false
			rbgAutoBind.state     = 0
		)
		else
		(
			ckbAutoBind.enabled   = true
		)
	)

	-- External Skeleton: enables the Select Skeleton button. Unchecking clears
	-- the picked file so the next run falls back to the auto-derive path.
	on ckbUseExternalSkel changed state do
	(
		btnSelectSkeleton.enabled = state
		if not state do
		(
			externalSkeletonFile = undefined
			btnSelectSkeleton.caption = "Select Skeleton"
		)
	)

	on btnSelectSkeleton pressed do
	(
		local picked = getOpenFileName \
			caption:"Select Skeleton W3D" \
			types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|"
		if picked != undefined do
		(
			externalSkeletonFile = picked
			btnSelectSkeleton.caption = (filenameFromPath picked)
		)
	)

	on ckbBatchProcessing changed state do
	(
		if ckbBatchProcessing.checked then btnW3DImporter.caption = "Import files"
		else btnW3DImporter.caption = "Import a file"
	)

	-- Tab switcher: state 1 = Basic, state 2 = Advanced.
	on rbgTab changed st do
	(
		local basic = (st == 1)
		ckbSplitDependencies.visible = basic
		ckbAutoBind.visible          = basic
		rbgAutoBind.visible          = basic
		ckbBatchProcessing.visible   = basic
		ddlPivotType.visible         = basic

		ckbUseW3DMatl.visible        = not basic
		ckbDebugOutput.visible       = not basic
		ckbIgnoreErrors.visible      = not basic
		ckbFixNormals.visible        = not basic
		ckbTga2Dds.visible           = not basic
		ckbTga2DdsRev.visible        = not basic
		ckbFixVertices.visible       = not basic
		ckbNoMultiMat.visible        = not basic
		ckbUseWWSkin.visible         = not basic
		ckbImportExtendedW3D.visible = not basic
		ckbUseExternalSkel.visible   = not basic
		btnSelectSkeleton.visible    = not basic
	)

	on rltMain open do
	(
		local i
		deltaTable = #()

		for i=1 to 16 do
		( append deltaTable (pow 10 (float(i)-7)) ) -- Technically needs to be i-9, but Max rounds 10^(-8) and 10^(-7) to 0
		for i=1 to 240 do
		( append deltaTable (1-sin(float(i-1)/240*90)) )

		-- Detect whether the W3D Tools material plugin is registered. If not, disable the checkbox.
		local w3dMatlAvailable = false
		try
		(
			local probe = W3DMaterial()
			if probe != undefined do w3dMatlAvailable = true
		)
		catch ( w3dMatlAvailable = false )
		ckbUseW3DMatl.enabled = w3dMatlAvailable
		if not w3dMatlAvailable do
		(
			ckbUseW3DMatl.checked = false
			ckbUseW3DMatl.caption = "Use W3D materials (not installed)"
		)
	)
)
createDialog rltMain