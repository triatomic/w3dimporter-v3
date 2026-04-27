-- w3d importer --
-- version 3.1 --
-- scripted by coolfile --
-- msn: coolfile_cn@hotmail.com --
-- edited and augmented by NDC --
-- edited by tria --

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
	textureStage
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
				txStage = ReadMeshTextureStage fstream subChunkEnd
			)
			0x0000004A:	--W3D_CHUNK_TEXTURE_STAGE (NEW)	// wrapper around a texture stage.
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txIds =#()
				join txIds vmIds
				txStage = W3dMeshTextureStage txIds (ReadMeshTextureCoordArray fstream subChunkEnd)
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshMaterialPass vmIds shaderIds txStage
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
			--0x00000023:	--W3D_CHUNK_PRELIT_UNLIT	// optional unlit material chunk wrapper
			--0x00000024:	--W3D_CHUNK_PRELIT_VERTEX	// optional vertex-lit material chunk wrapper
			--0x00000025:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_PASS	// optional lightmapped multi-pass material chunk wrapper
			--0x00000026:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_TEXTURE	// optional lightmapped multi-texture material chunk wrapper
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
function cfW3DImporter w3dfilename splitMeshes autoBindType batch debugOutput useW3DMatl ignoreErrors fixNormals tga2dds fixVertices noMultiMat tga2ddsRev =
(
	-- for the interface in future version
	userSeparateMaterial = false

	global anim = undefined
	global cmpAnim = undefined
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
	if (autoBindType > 0) do
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
		
		if (batch and meshes.count == 0) do
		( return() )
		
		-- if the hier isn't present, find the dependent skeleton file
		if hier == undefined then
		(
			if hlodSet != undefined do skelfilename = (getFilenamePath w3dfilename) + hlodSet.header.hierarchyName + ".w3d"
			
			if anim != undefined then
				skelfilename = (getFilenamePath w3dfilename) + anim.header.skelName + ".w3d"
			else
				if cmpAnim != undefined do skelfilename = (getFilenamePath w3dfilename) + cmpAnim.header.skelName + ".w3d"
			
			if (skelfilename != undefined) and (not (doesFileExist skelfilename)) then
				skelfilename = getOpenFileName caption:("Import Skeleton W3D: " + (getFilenameFile skelfilename)) types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|"
			
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
			--pivotName, parentID, pos, eulerAngles, rotation
			-- to skip the ROOTTRANSFORM, i starts at 2
			for i = 2 to hier.pivots.count do
			(
				-- if hier.pivots[i].parentID < 0 do continue -- -1 means ROOTTRANSFORM
				------ debug start ------
				--print "-----"
				--print i
				--print hier.pivots[i].pivotName
				--print hier.pivots[i].parentID
				------ debug end ------
				curPivot = undefined
				--gmPivots[i-1] = bone name:hier.pivots[i].pivotName pos:hier.pivots[i].pos rotation:hier.pivots[i].rotation -- v1.03 bug
				if hier.pivots[i].parentID == 0 then
				(
					curPivot = bone name:hier.pivots[i].pivotName
					in coordsys world curPivot.rotation = hier.pivots[i].rotation
					in coordsys world curPivot.pos = hier.pivots[i].pos
				)
				else
				(
					--gmPivots[i-1] = bone name:hier.pivots[i].pivotName parent:gmPivots[hier.pivots[i].parentID] pos:hier.pivots[i].pos rotation:hier.pivots[i].rotation
					--in coordsys parent gmPivots[i-1].rotation = hier.pivots[i].rotation
					--in coordsys parent gmPivots[i-1].pos = hier.pivots[i].pos
					curPivot = bone name:hier.pivots[i].pivotName parent:gmPivots[hier.pivots[i].parentID]
					in coordsys parent curPivot.rotation = hier.pivots[i].rotation
					in coordsys parent curPivot.pos = hier.pivots[i].pos
				)
				append gmPivots curPivot
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
			if (meshes[i].vertMatls != undefined) and (meshes[i].vertMatls.count > 0) then
			(
				numTextures = 0
				if meshes[i].textures != undefined do numTextures = meshes[i].textures.count

				-- Optional .tga <-> .dds extension rewrite. Many W3D files reference TGA
				-- textures that have been re-exported as DDS later; toggling tga2dds swaps just
				-- the extension (case-insensitive, name preserved) so the bitmaptex calls
				-- and debug output below pick up the .dds versions automatically.
				-- When tga2ddsRev is also on, the rewrite goes the other direction (.dds -> .tga).
				if tga2dds and (meshes[i].textures != undefined) do
				(
					local fromExt = if tga2ddsRev then ".dds" else ".tga"
					local toExt   = if tga2ddsRev then ".tga" else ".dds"
					for t = 1 to meshes[i].textures.count do
					(
						local fn0 = meshes[i].textures[t].txFileName
						if fn0 != undefined and fn0.count >= 4 do
						(
							local ext = toLower (substring fn0 (fn0.count - 3) 4)
							if ext == fromExt do
								meshes[i].textures[t].txFileName = (substring fn0 1 (fn0.count - 4)) + toExt
						)
					)
				)

				-- W3D shader enums (from shader.h):
				--   SrcBlend: 0=ZERO, 1=ONE, 2=SRC_ALPHA, 3=ONE_MINUS_SRC_ALPHA
				--   DstBlend: 0=ZERO, 1=ONE, 2=SRC_COLOR, 3=ONE_MINUS_SRC_COLOR, 4=SRC_ALPHA, 5=ONE_MINUS_SRC_ALPHA
				-- Per-shader alpha test (mirror of ShaderClass::Uses_Alpha() in shader.h)
				fn shaderUsesAlphaW3D sh =
				(
					if sh.alphaTest != 0 do return true
					if (sh.destBlend == 4) or (sh.destBlend == 5) do return true
					if (sh.srcBlend == 2) or (sh.srcBlend == 3) do return true
					return false
				)
				-- Additive preset (SC_ADDITIVE in shader.cpp): srcBlend=ONE(1), destBlend=ONE(1)
				fn shaderIsAdditiveW3D sh =
				(
					return ((sh.srcBlend == 1) and (sh.destBlend == 1))
				)

				-- Mesh-level rollups (inline shader scans because MAXScript disallows nested fn refs)
				meshAlpha = false
				meshAlphaTest = false
				meshAdditive = false
				-- W3DMaterial blendmode enum: 0=Opaque,1=Add,2=Multiply,3=MultiplyAndAdd,4=Screen,
				--                              5=AlphaBlend,6=AlphaTest,7=AlphaTestAndBlend,8=Custom
				meshBlendMode = 0 -- defaults to Opaque if no shader signals otherwise
				if (meshes[i].shaders != undefined) and (meshes[i].shaders.count > 0) do
				(
					for s = 1 to meshes[i].shaders.count do
					(
						sh = meshes[i].shaders[s]
						if sh.alphaTest != 0 do meshAlphaTest = true
						if (sh.alphaTest != 0) or (sh.destBlend == 4) or (sh.destBlend == 5) or (sh.srcBlend == 2) or (sh.srcBlend == 3) do meshAlpha = true
						if (sh.srcBlend == 1) and (sh.destBlend == 1) do meshAdditive = true

						-- Derive the W3DMaterial blendmode from this shader.
						-- IMPORTANT: alphaTest is orthogonal to blend mode in W3D, so it must be
						-- checked BEFORE the opaque/add/etc. blend patterns. The AlphaTest preset
						-- has the same src/dst as Opaque (ONE/ZERO) and only differs by alphaTest.
						local thisBm = -1
						if (sh.srcBlend == 2) and (sh.destBlend == 5) then thisBm = (if sh.alphaTest != 0 then 7 else 5) -- AlphaTestAndBlend / AlphaBlend
						else if sh.alphaTest != 0 then thisBm = 6   -- AlphaTest (any blend, but typically ONE/ZERO)
						else if (sh.srcBlend == 1) and (sh.destBlend == 0) then thisBm = 0   -- Opaque
						else if (sh.srcBlend == 1) and (sh.destBlend == 1) then thisBm = 1   -- Add
						else if (sh.srcBlend == 0) and (sh.destBlend == 2) then thisBm = 2   -- Multiply
						else if (sh.srcBlend == 1) and (sh.destBlend == 2) then thisBm = 3   -- MultiplyAndAdd
						else if (sh.srcBlend == 1) and (sh.destBlend == 3) then thisBm = 4   -- Screen
						else thisBm = 8   -- Custom (unrecognised src/dst combo)

						-- Promote the mesh's blend mode toward the most expressive shader.
						-- Order of promotion: Opaque < Custom < AlphaTest < AlphaBlend < AlphaTestAndBlend < Screen < MultiplyAndAdd < Multiply < Add
						-- (Add wins because it's the strongest visual override; this matches the precedence used elsewhere.)
						if thisBm == 1 then meshBlendMode = 1
						else if (meshBlendMode != 1) and (thisBm == 7) then meshBlendMode = 7
						else if (meshBlendMode != 1) and (meshBlendMode != 7) and (thisBm == 5) then meshBlendMode = 5
						else if (meshBlendMode != 1) and (meshBlendMode != 7) and (meshBlendMode != 5) and (thisBm == 6) then meshBlendMode = 6
						else if (meshBlendMode == 0) and (thisBm > 0) then meshBlendMode = thisBm
					)
				)

				------ debug: material/texture diagnostics ------
				if debugOutput do
				(
					format "=== Mesh: % ===\n" meshes[i].header.meshName
					format "  vertMatls.count = %\n" meshes[i].vertMatls.count
					format "  textures.count  = %\n" numTextures
					if meshes[i].textures != undefined do
					(
						for t = 1 to meshes[i].textures.count do
						( format "    texture[%] = %\n" t meshes[i].textures[t].txFileName )
					)
					-- material info header (declared pass count from W3D_CHUNK_MATERIAL_INFO)
					if meshes[i].matlheader != undefined do
					( format "  matlheader: passCount=% vertMatlCount=% shaderCount=% textureCount=%\n" meshes[i].matlheader.passCount meshes[i].matlheader.vertMatlCount meshes[i].matlheader.shaderCount meshes[i].matlheader.textureCount )
					-- walk every MATERIAL_PASS chunk (one per render pass)
					local mPasses = meshes[i].matlPasses
					if mPasses == undefined or mPasses.count == 0 then
					(
						if meshes[i].matlPass != undefined then ( mPasses = #(meshes[i].matlPass) ) else ( mPasses = #() )
					)
					format "  matlPasses.count = %\n" mPasses.count
					for p = 1 to mPasses.count do
					(
						local mpD = mPasses[p]
						format "  -- pass[%] --\n" p
						if (mpD.textureStage != undefined) and (mpD.textureStage.txIds != undefined) then
							format "    txIds.count = %, values = %\n" mpD.textureStage.txIds.count mpD.textureStage.txIds
						else
							format "    txIds = undefined\n"
						if mpD.vmIds != undefined then
							format "    vmIds.count = %, values = %\n" mpD.vmIds.count mpD.vmIds
						else
							format "    vmIds = undefined\n"
						if mpD.shaderIds != undefined then
							format "    shaderIds.count = %, values = %\n" mpD.shaderIds.count mpD.shaderIds
						else
							format "    shaderIds = undefined\n"
					)
					-- alpha diagnostics
					format "  shaders.count = %\n" (if meshes[i].shaders != undefined then meshes[i].shaders.count else 0)
					if meshes[i].shaders != undefined do
					(
						for s = 1 to meshes[i].shaders.count do
						(
							sh = meshes[i].shaders[s]
							-- per-shader literal label inferred from src/dst blend (alphaTest checked first)
							local blendLabel = "Custom"
							if (sh.srcBlend == 2) and (sh.destBlend == 5) then blendLabel = (if sh.alphaTest != 0 then "AlphaTestAndBlend" else "AlphaBlend")
							else if sh.alphaTest != 0 then blendLabel = "AlphaTest"
							else if (sh.srcBlend == 1) and (sh.destBlend == 0) then blendLabel = "Opaque"
							else if (sh.srcBlend == 1) and (sh.destBlend == 1) then blendLabel = "Add"
							else if (sh.srcBlend == 0) and (sh.destBlend == 2) then blendLabel = "Multiply"
							else if (sh.srcBlend == 1) and (sh.destBlend == 2) then blendLabel = "MultiplyAndAdd"
							else if (sh.srcBlend == 1) and (sh.destBlend == 3) then blendLabel = "Screen"
							format "    shader[%]: srcBlend=%, destBlend=%, alphaTest=%, WriteZBuffer=%  -> alpha=%, additive=%, blendMode=%\n" s sh.srcBlend sh.destBlend sh.alphaTest sh.depthMask (shaderUsesAlphaW3D sh) (shaderIsAdditiveW3D sh) blendLabel
						)
					)
					-- per-vertex-material info (one entry per pass): colors + stage0/stage1 mapping types + mapper args.
					-- W3D vmInfo.attrs encodes mapping types: bits 8-15 = stage0Mapping, bits 16-23 = stage1Mapping.
					-- vmArgs0/vmArgs1 are the per-stage mapper args strings (match stage0mappingargs/stage1mappingargs).
					if meshes[i].vertMatls != undefined do
					(
						for v = 1 to meshes[i].vertMatls.count do
						(
							local vmEntry = meshes[i].vertMatls[v]
							format "    vertMatl[%]: name=%\n" v vmEntry.vmName
							if vmEntry.vmInfo != undefined do
							(
								format "      ambient   = %\n" vmEntry.vmInfo.ambient
								format "      diffuse   = %\n" vmEntry.vmInfo.diffuse
								format "      specular  = %\n" vmEntry.vmInfo.specular
								format "      emissive  = %\n" vmEntry.vmInfo.emissive
								format "      opacity      = %\n" vmEntry.vmInfo.opacity
								format "      translucency = %\n" vmEntry.vmInfo.translucency
								format "      shininess    = %\n" vmEntry.vmInfo.shininess
								local attrsVal = vmEntry.vmInfo.attrs
								local stage0Map = bit.and (bit.shift attrsVal -8) 0xFF
								local stage1Map = bit.and (bit.shift attrsVal -16) 0xFF
								-- W3DMaterialMappingType enum (from w3dmaterial.h)
								local mapNames = #("UV","Environment","ClassicEnvironment","Screen","LinearOffset","Silhouette","Scale","Grid","Rotate","Sine","Step","ZigZag","WSClassicEnv","WSEnvironment","GridClassicEnv","GridEnvironment","Random","Edge","BumpEnv","GridWSClassicEnv","GridWSEnv")
								local s0Label = if (stage0Map + 1) >= 1 and (stage0Map + 1) <= mapNames.count then mapNames[stage0Map + 1] else "Unknown"
								local s1Label = if (stage1Map + 1) >= 1 and (stage1Map + 1) <= mapNames.count then mapNames[stage1Map + 1] else "Unknown"
								format "      attrs=0x% stage0mapping=% (%) stage1mapping=% (%)\n" (bit.intAsHex attrsVal) stage0Map s0Label stage1Map s1Label
								-- W3D doesn't store stage0mappinguvchannel or speculartodiffuse; defaults on import.
								format "      stage0mappinguvchannel = 1 (default; W3D file has no value)\n"
								format "      stage1mappinguvchannel = 1 (default; W3D file has no value)\n"
								format "      speculartodiffuse = off (default; W3D file has no value)\n"
							)
							if vmEntry.vmArgs0 != undefined and vmEntry.vmArgs0 != "" do
								format "      stage0mappingargs = \"%\"\n" vmEntry.vmArgs0
							if vmEntry.vmArgs1 != undefined and vmEntry.vmArgs1 != "" do
								format "      stage1mappingargs = \"%\"\n" vmEntry.vmArgs1
						)
					)
					format "  meshUsesAlpha = %\n" meshAlpha
					format "  meshIsAlphaTest = %\n" meshAlphaTest
					format "  meshIsAdditive = %\n" meshAdditive
					-- final W3DMaterial blendmode that buildW3DMatl will set
					local pickedLabel = "Opaque"
					case meshBlendMode of
					(
						0: pickedLabel = "Opaque"
						1: pickedLabel = "Add"
						2: pickedLabel = "Multiply"
						3: pickedLabel = "MultiplyAndAdd"
						4: pickedLabel = "Screen"
						5: pickedLabel = "AlphaBlend"
						6: pickedLabel = "AlphaTest"
						7: pickedLabel = "AlphaTestAndBlend"
						8: pickedLabel = "Custom"
					)
					format "  W3DMaterial blendmode -> % (%)\n" meshBlendMode pickedLabel
				)
				------ end debug ------

				-- Build a W3DMaterial (from the installed W3D Tools plugin) configured from a vertex material + texture.
				-- Returns undefined if the W3DMaterial class is not available.
				-- blendMode enum: 0=Opaque, 1=Add, 2=Multiply, 3=MultiplyAndAdd, 4=Screen,
				--                 5=AlphaBlend, 6=AlphaTest, 7=AlphaTestAndBlend, 8=Custom
				-- Pick the blend mode for sub-material `subIx` (0-based texture index in W3D, 1-based here).
				-- Looks for a face whose txIds entry matches subIx-1, then reads that face's shader from shaderIds.
				-- Falls back to meshBlendMode if no per-face data is present.
				-- (shader->blendMode logic is inlined because MAXScript disallows nested fn cross-refs.)
				fn pickBlendModeForSub mesh subIx fallback =
				(
					if mesh.matlPass == undefined do return fallback
					if mesh.shaders == undefined or mesh.shaders.count == 0 do return fallback

					local txIds = undefined
					if mesh.matlPass.textureStage != undefined do txIds = mesh.matlPass.textureStage.txIds
					local shIds = mesh.matlPass.shaderIds

					if shIds == undefined or shIds.count == 0 do return fallback

					-- Short-form matlPass: shaderIds has 1 entry. If the mesh actually has multiple
					-- shaders (one per pass), map sub index -> shaders[subIx] directly; otherwise
					-- every sub uses the single referenced shader.
					if shIds.count == 1 do
					(
						local sxSel = -1
						if mesh.shaders.count > 1 and subIx >= 1 and subIx <= mesh.shaders.count then
							sxSel = subIx
						else if subIx > mesh.shaders.count then
						(
							-- unmapped sub beyond shader count (orphan texture not face-referenced).
							-- Use SAGE naming convention: textures ending in "_G" are glow/Add, else Opaque base.
							local tName = ""
							try ( tName = mesh.textures[subIx].txFileName ) catch ()
							if tName != undefined and tName != "" do
							(
								local lcName = toLower tName
								-- strip extension
								local dotIx = findString lcName "."
								local baseName = lcName
								if dotIx != undefined and dotIx > 1 do baseName = substring lcName 1 (dotIx - 1)
								if baseName.count >= 2 and (substring baseName (baseName.count - 1) 2) == "_g" do return 1
							)
							sxSel = 1  -- default to first/base shader (typically Opaque)
						)
						else
							sxSel = shIds[1] + 1
						if sxSel < 1 or sxSel > mesh.shaders.count do return fallback
						local sh = mesh.shaders[sxSel]
						-- alphaTest must be checked before opaque/add patterns (see comment in rollup).
						if (sh.srcBlend == 2) and (sh.destBlend == 5) do return (if sh.alphaTest != 0 then 7 else 5)
						if sh.alphaTest != 0 do return 6
						if (sh.srcBlend == 1) and (sh.destBlend == 0) do return 0
						if (sh.srcBlend == 1) and (sh.destBlend == 1) do return 1
						if (sh.srcBlend == 0) and (sh.destBlend == 2) do return 2
						if (sh.srcBlend == 1) and (sh.destBlend == 2) do return 3
						if (sh.srcBlend == 1) and (sh.destBlend == 3) do return 4
						return 8
					)

					-- No per-face txIds: assume sub i uses shader i (best-effort).
					if txIds == undefined or txIds.count <= 1 do
					(
						if subIx < 1 or subIx > shIds.count do return fallback
						local sx2 = shIds[subIx] + 1
						if sx2 < 1 or sx2 > mesh.shaders.count do return fallback
						local sh2 = mesh.shaders[sx2]
						if (sh2.srcBlend == 2) and (sh2.destBlend == 5) do return (if sh2.alphaTest != 0 then 7 else 5)
						if sh2.alphaTest != 0 do return 6
						if (sh2.srcBlend == 1) and (sh2.destBlend == 0) do return 0
						if (sh2.srcBlend == 1) and (sh2.destBlend == 1) do return 1
						if (sh2.srcBlend == 0) and (sh2.destBlend == 2) do return 2
						if (sh2.srcBlend == 1) and (sh2.destBlend == 2) do return 3
						if (sh2.srcBlend == 1) and (sh2.destBlend == 3) do return 4
						return 8
					)

					-- Per-face txIds + per-face shaderIds: walk faces, collect blend modes used by any face whose
					-- texture matches this sub, and promote toward the strongest expressive shader (Add wins).
					local picked = -1
					local target = subIx - 1
					local n = txIds.count
					if shIds.count < n do n = shIds.count
					for f = 1 to n do
					(
						if txIds[f] != target do continue
						local sx3 = shIds[f] + 1
						if sx3 < 1 or sx3 > mesh.shaders.count do continue
						local sh3 = mesh.shaders[sx3]
						local bm = 8
						if (sh3.srcBlend == 2) and (sh3.destBlend == 5) then bm = (if sh3.alphaTest != 0 then 7 else 5)
						else if sh3.alphaTest != 0 then bm = 6
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 0) then bm = 0
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 1) then bm = 1
						else if (sh3.srcBlend == 0) and (sh3.destBlend == 2) then bm = 2
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 2) then bm = 3
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 3) then bm = 4

						if picked == -1 then picked = bm
						else if bm == 1 then picked = 1
						else if (picked != 1) and (bm == 7) then picked = 7
						else if (picked != 1) and (picked != 7) and (bm == 5) then picked = 5
						else if (picked != 1) and (picked != 7) and (picked != 5) and (bm == 6) then picked = 6
						else if (picked == 0) and (bm > 0) then picked = bm
					)
					if picked == -1 do return fallback
					return picked
				)

				fn buildW3DMatl matName vm texFile blendMode =
				(
					local m = undefined
					try ( m = W3DMaterial name:matName ) catch ( m = undefined )
					if m == undefined do return undefined

					-- vertex material colors / opacity / shininess
					try ( setProperty m #ambientcolour vm.vmInfo.ambient ) catch ()
					try ( setProperty m #diffusecolour vm.vmInfo.diffuse ) catch ()
					try ( setProperty m #specularcolour vm.vmInfo.specular ) catch ()
					try ( setProperty m #emissivecolour vm.vmInfo.emissive ) catch ()
					try ( setProperty m #opacity vm.vmInfo.opacity ) catch ()
					try ( setProperty m #shininess vm.vmInfo.shininess ) catch ()
					try ( setProperty m #translucency vm.vmInfo.translucency ) catch ()

					-- stage0/stage1 mapping types come from W3D vmInfo.attrs bitfield:
					-- bits 8-15 = stage0Mapping, bits 16-23 = stage1Mapping. The mapper-args
					-- strings live in vmArgs0/vmArgs1.
					if vm.vmInfo != undefined do
					(
						local attrsVal = vm.vmInfo.attrs
						local stage0Map = bit.and (bit.shift attrsVal -8) 0xFF
						local stage1Map = bit.and (bit.shift attrsVal -16) 0xFF
						try ( setProperty m #stage0mapping stage0Map ) catch ()
						try ( setProperty m #stage1mapping stage1Map ) catch ()
					)
					if vm.vmArgs0 != undefined and vm.vmArgs0 != "" do
					( try ( setProperty m #stage0mappingargs vm.vmArgs0 ) catch () )
					if vm.vmArgs1 != undefined and vm.vmArgs1 != "" do
					( try ( setProperty m #stage1mappingargs vm.vmArgs1 ) catch () )

					-- W3D doesn't carry these; apply sensible defaults.
					try ( setProperty m #stage0mappinguvchannel 1 ) catch ()
					try ( setProperty m #stage1mappinguvchannel 1 ) catch ()
					try ( setProperty m #speculartodiffuse false ) catch ()

					-- blend mode comes straight from the W3D shader classification
					try ( setProperty m #blendmode blendMode ) catch ()
					try ( setProperty m #alphatest (blendMode == 6 or blendMode == 7) ) catch ()

					-- additive (Add): don't write to z-buffer, force alphatest off, set src/dst = One/One
					if blendMode == 1 do
					(
						try ( setProperty m #customblendwritezbuffer false ) catch ()
						try ( setProperty m #alphatest false ) catch ()
						try ( setProperty m #blendmodesrc 1 ) catch ()  -- One
						try ( setProperty m #blendmodedest 1 ) catch () -- One
					)
					-- alpha blend (5) and alpha-test+blend (7): set src/dst = SrcAlpha / OneMinusSrcAlpha
					-- The plugin's blendmode dropdown sometimes doesn't auto-fill these; write them explicitly.
					if (blendMode == 5) or (blendMode == 7) do
					(
						try ( setProperty m #customblendwritezbuffer false ) catch ()
						try ( setProperty m #blendmodesrc 2 ) catch ()  -- SrcAlpha
						try ( setProperty m #blendmodedest 5 ) catch () -- OneMinusSrcAlpha
					)

					-- stage 0 texture
					if texFile != undefined and texFile != "" do
					(
						try ( setProperty m #stage0texenabled true ) catch ()
						try ( setProperty m #stage0texturemap (bitmaptex filename:texFile) ) catch ()
						try ( setProperty m #stage0display true ) catch () -- show in viewport
					)
					return m
				)

				-- Detect "single material, two texture stages" pattern:
				-- W3D encodes this as 1 vertMatl + 1 shader + 2 textures, with the vertMatl's
				-- attrs bitfield (or vmArgs1) signalling a stage-1 mapping. In that case the
				-- engine renders it as one material with stage0 = textures[1] and stage1 =
				-- textures[2] (e.g. SHIELDS: noise + gradient via LinearOffset on both stages).
				-- Without this detection the importer would split it into a multi-material,
				-- which is wrong because the engine never renders these as separate sub-materials.
				local twoStageHandled = false
				if useW3DMatl and (numTextures == 2) and (meshes[i].vertMatls.count == 1) and (meshes[i].shaders != undefined) and (meshes[i].shaders.count == 1) do
				(
					local tsVm = meshes[i].vertMatls[1]
					local tsStage1Map = 0
					if tsVm.vmInfo != undefined do
						tsStage1Map = bit.and (bit.shift tsVm.vmInfo.attrs -16) 0xFF
					local tsHasStage1Args = (tsVm.vmArgs1 != undefined) and (tsVm.vmArgs1 != "")
					if (tsStage1Map != 0) or tsHasStage1Args do
					(
						-- buildW3DMatl writes stage 0 (texture[1]) and both stages' mapping
						-- types/args from the vertex material; we just append stage 1's texture.
						local tex0 = meshes[i].textures[1].txFileName
						local tex1 = meshes[i].textures[2].txFileName
						local tsMatl = buildW3DMatl meshes[i].header.meshName tsVm tex0 meshBlendMode
						if tsMatl != undefined do
						(
							try ( setProperty tsMatl #stage1texenabled true ) catch ()
							try ( setProperty tsMatl #stage1texturemap (bitmaptex filename:tex1) ) catch ()
							try ( setProperty tsMatl #stage1display true ) catch ()
							gmMeshes[i].material = tsMatl
							twoStageHandled = true
							if debugOutput do
							(
								format "  -> single W3DMaterial, two stages: stage0=% stage1=%\n" tex0 tex1
							)
						)
					)
				)

				-- Detect "single sub-material, multi-pass" pattern (e.g. base + glow) using matlPasses:
				-- W3D stores one MATERIAL_PASS chunk per render pass. When each pass has uniform
				-- single-valued vmIds/txIds/shaderIds (every face uses the same triple in that pass),
				-- the file is describing a single sub-material with N render passes -- not a multi-sub.
				-- Build an N-sub MultiMaterial (one W3DMaterial per pass) so that on re-export the W3D
				-- exporter writes all passes back out. Pass 2+ properties aren't writable on a single
				-- W3DMaterial from MAXScript, so multi-sub is the round-trip workaround.
				if (not twoStageHandled) and (meshes[i].matlPasses != undefined) and (meshes[i].matlPasses.count >= 2) and (meshes[i].shaders != undefined) and (meshes[i].vertMatls != undefined) do
				(
					local mPs = meshes[i].matlPasses
					local nPasses = mPs.count
					-- per-pass arrays of (vmIx, txIx, shIx) -- 1-based for max
					local passVmIx = #()
					local passTxIx = #()
					local passShIx = #()
					local passUniform = true
					for p = 1 to nPasses while passUniform do
					(
						local pp = mPs[p]
						if pp == undefined do ( passUniform = false; exit )
						local tIds = undefined
						if pp.textureStage != undefined do tIds = pp.textureStage.txIds
						local vIds = pp.vmIds
						local sIds = pp.shaderIds
						-- check uniformity (or single-element short form)
						if tIds != undefined and tIds.count > 1 do
						( for k = 2 to tIds.count while passUniform do ( if tIds[k] != tIds[1] do passUniform = false ) )
						if passUniform and vIds != undefined and vIds.count > 1 do
						( for k = 2 to vIds.count while passUniform do ( if vIds[k] != vIds[1] do passUniform = false ) )
						if passUniform and sIds != undefined and sIds.count > 1 do
						( for k = 2 to sIds.count while passUniform do ( if sIds[k] != sIds[1] do passUniform = false ) )
						if passUniform do
						(
							local txZero = if tIds != undefined and tIds.count > 0 then tIds[1] else 0
							local vmZero = if vIds != undefined and vIds.count > 0 then vIds[1] else 0
							local shZero = if sIds != undefined and sIds.count > 0 then sIds[1] else 0
							append passTxIx (txZero + 1)
							append passVmIx (vmZero + 1)
							append passShIx (shZero + 1)
						)
					)
					if passUniform and passTxIx.count == nPasses do
					(
						-- classify shader -> blendMode
						fn _tpClassify sh =
						(
							if sh == undefined do return 0
							if (sh.srcBlend == 2) and (sh.destBlend == 5) do return (if sh.alphaTest != 0 then 7 else 5)
							if sh.alphaTest != 0 do return 6
							if (sh.srcBlend == 1) and (sh.destBlend == 0) do return 0
							if (sh.srcBlend == 1) and (sh.destBlend == 1) do return 1
							if (sh.srcBlend == 0) and (sh.destBlend == 2) do return 2
							if (sh.srcBlend == 1) and (sh.destBlend == 2) do return 3
							if (sh.srcBlend == 1) and (sh.destBlend == 3) do return 4
							return 8
						)
						-- build one W3DMaterial sub per pass
						local subs = #()
						local subNames = #()
						local bms = #()
						local texFiles = #()
						local allBuilt = true
						for p = 1 to nPasses while allBuilt do
						(
							local vmIx = passVmIx[p]
							local txIx = passTxIx[p]
							local shIx = passShIx[p]
							if vmIx < 1 or vmIx > meshes[i].vertMatls.count do ( allBuilt = false; exit )
							if txIx < 1 or txIx > meshes[i].textures.count do ( allBuilt = false; exit )
							if shIx < 1 or shIx > meshes[i].shaders.count do ( allBuilt = false; exit )
							local pVm = meshes[i].vertMatls[vmIx]
							local pTex = meshes[i].textures[txIx].txFileName
							local pBm = _tpClassify meshes[i].shaders[shIx]
							local pName = pVm.vmName + "_pass" + (p as string)
							local pSub = undefined
							if useW3DMatl then
							(
								pSub = buildW3DMatl pName pVm pTex pBm
							)
							else
							(
								-- standard material per pass: alpha/additive wired from this pass's blendmode
								local pAlpha = (pBm == 5) or (pBm == 7)
								local pAdditive = (pBm == 1)
								pSub = standardMaterial name:pName
								pSub.ambient = pVm.vmInfo.ambient
								pSub.diffuse = pVm.vmInfo.diffuse
								pSub.specular = pVm.vmInfo.specular
								pSub.glossiness = pVm.vmInfo.shininess * 100
								pSub.opacity = pVm.vmInfo.opacity * 100
								local pDiffTex = bitmaptex filename:pTex
								try ( pDiffTex.alphaSource = 2 ) catch ()
								pSub.diffuseMap = pDiffTex
								showTextureMap pSub pSub.diffuseMap true
								if pAlpha do
								(
									local pOpTex = bitmaptex filename:pTex
									pOpTex.monoOutput = 1
									pSub.opacityMap = pOpTex
									showTextureMap pSub pSub.opacityMap true
								)
								if pAdditive do
								(
									local pAddOp = bitmaptex filename:pTex
									pSub.opacityMap = pAddOp
									showTextureMap pSub pSub.opacityMap true
									local pAddSi = bitmaptex filename:pTex
									pSub.selfIllumMap = pAddSi
									showTextureMap pSub pSub.selfIllumMap true
									try ( pSub.useSelfIllumColor = true ) catch ()
								)
							)
							if pSub == undefined do ( allBuilt = false; exit )
							append subs pSub
							append subNames pName
							append bms pBm
							append texFiles pTex
						)
						if allBuilt and subs.count == nPasses do
						(
							local mpMulti = multiMaterial numsubs:nPasses name:meshes[i].header.meshName
							for p = 1 to nPasses do
							(
								mpMulti.materialList[p] = subs[p]
								mpMulti.names[p] = subNames[p]
							)
							gmMeshes[i].material = mpMulti
							twoStageHandled = true

							-- Viewport heuristic: 3ds Max multi-sub renders only one sub per face.
							-- The W3D pass order is preserved in the material list (so re-export round-trips),
							-- but for visual fidelity we point face matIDs at the "main" pass:
							--   * If any pass is AlphaBlend (5) or AlphaTestAndBlend (7), prefer that
							--     pass -- it's typically the authored building/object texture composited
							--     onto an Opaque base/tint pass (e.g. WELL: lakedusk Opaque + cbmogwell01 AlphaBlend).
							--   * Otherwise default to sub 1 (pass 1, the base).
							local viewportSub = 1
							for p = 1 to nPasses do
							(
								if (bms[p] == 5) or (bms[p] == 7) do ( viewportSub = p; exit )
							)
							if viewportSub != 1 do
							(
								for f = 1 to meshes[i].faces.count do
								( setFaceMatID gmMeshes[i] f viewportSub )
								update gmMeshes[i]
							)

							if debugOutput do
							(
								format "  -> %-pass MultiMaterial (viewport sub=%):\n" nPasses viewportSub
								for p = 1 to nPasses do
								( format "       sub[%]: tex=% blendmode=% vm=% sh=%\n" p texFiles[p] bms[p] passVmIx[p] passShIx[p] )
							)
						)
					)
				)

				if twoStageHandled then
				(
					-- already assigned a single two-stage / two-pass W3DMaterial; skip the multi-material path
				)
				else if numTextures > 1 then
				(
					-- build a MultiMaterial with one sub-material per texture
					baseVm = meshes[i].vertMatls[1]
					gmMultiMatl = multiMaterial numsubs:numTextures name:meshes[i].header.meshName
					for m = 1 to numTextures do
					(
						-- pick a vertex material if available, else reuse the first
						vmIx = m
						if vmIx > meshes[i].vertMatls.count do vmIx = 1
						curVm = meshes[i].vertMatls[vmIx]

						subName = curVm.vmName + "_" + (meshes[i].textures[m].txFileName)
						subMatl = undefined
						if useW3DMatl do
						(
							local subBlendMode = pickBlendModeForSub meshes[i] m meshBlendMode
							if debugOutput do
							(
								local subBmLabel = "Opaque"
								case subBlendMode of
								(
									0: subBmLabel = "Opaque"
									1: subBmLabel = "Add"
									2: subBmLabel = "Multiply"
									3: subBmLabel = "MultiplyAndAdd"
									4: subBmLabel = "Screen"
									5: subBmLabel = "AlphaBlend"
									6: subBmLabel = "AlphaTest"
									7: subBmLabel = "AlphaTestAndBlend"
									8: subBmLabel = "Custom"
								)
								format "  -> sub[%] tex=% picked blendmode=% (%)\n" m meshes[i].textures[m].txFileName subBlendMode subBmLabel
							)
							subMatl = buildW3DMatl subName curVm meshes[i].textures[m].txFileName subBlendMode
						)

						if subMatl == undefined then
						(
							-- per-sub blendmode classification (same logic as W3D material path).
							-- Without this every sub inherits the mesh-wide meshAlpha/meshAdditive flag,
							-- which is wrong when a mesh has e.g. one Opaque base + one Add glow sub.
							local subBlendModeS = pickBlendModeForSub meshes[i] m 0
							local subAlpha = (subBlendModeS == 5) or (subBlendModeS == 7)
							local subAdditive = (subBlendModeS == 1)
							local subAlphaTest = (subBlendModeS == 6) or (subBlendModeS == 7)

							subMatl = standardMaterial name:subName
							subMatl.ambient = curVm.vmInfo.ambient
							subMatl.diffuse = curVm.vmInfo.diffuse
							subMatl.specular = curVm.vmInfo.specular
							subMatl.glossiness = curVm.vmInfo.shininess * 100
							subMatl.opacity = curVm.vmInfo.opacity * 100
							diffuseTex = bitmaptex filename:meshes[i].textures[m].txFileName
							-- default the diffuse bitmap to alphaSource = None so opaque meshes don't
							-- accidentally render transparent because the .dds carries an alpha channel.
							-- The alpha / additive branches below rely on this being None, so it's safe
							-- to set unconditionally here.
							try ( diffuseTex.alphaSource = 2 ) catch () -- 0=Image,1=RGB Intensity,2=None(Opaque)
							subMatl.diffuseMap = diffuseTex
							showTextureMap subMatl subMatl.diffuseMap true

							-- if this sub uses alpha, wire opacity to the same bitmap with mono output = Alpha
							if subAlpha do
							(
								opTex = bitmaptex filename:meshes[i].textures[m].txFileName
								opTex.monoOutput = 1 -- 0=RGB Intensity, 1=Alpha
								subMatl.opacityMap = opTex
								showTextureMap subMatl subMatl.opacityMap true
							)
							-- additive blending: assign texture to opacity and self-illumination, with selfIllumColor on
							if subAdditive do
							(
								addOpTex = bitmaptex filename:meshes[i].textures[m].txFileName
								subMatl.opacityMap = addOpTex
								showTextureMap subMatl subMatl.opacityMap true

								addSiTex = bitmaptex filename:meshes[i].textures[m].txFileName
								subMatl.selfIllumMap = addSiTex
								showTextureMap subMatl subMatl.selfIllumMap true

								try ( subMatl.useSelfIllumColor = true ) catch ()

								if debugOutput do
								( format "  -> sub[%] additive: opacity+selfIllum maps wired\n" m )
							)
							if debugOutput do
							(
								local sbLabel = "Opaque"
								case subBlendModeS of
								(
									1: sbLabel = "Add"
									2: sbLabel = "Multiply"
									3: sbLabel = "MultiplyAndAdd"
									4: sbLabel = "Screen"
									5: sbLabel = "AlphaBlend"
									6: sbLabel = "AlphaTest"
									7: sbLabel = "AlphaTestAndBlend"
									8: sbLabel = "Custom"
								)
								format "  -> std sub[%] tex=% blendmode=% (%) alpha=% additive=%\n" m meshes[i].textures[m].txFileName subBlendModeS sbLabel subAlpha subAdditive
							)
						)

						gmMultiMatl.materialList[m] = subMatl
						gmMultiMatl.materialIDList[m] = m
						gmMultiMatl.names[m] = subName
					)
					gmMeshes[i].material = gmMultiMatl

					-- assign per-face material IDs from txIds (0-based in w3d, 1-based in max)
					txIdList = undefined
					if (meshes[i].matlPass != undefined) and (meshes[i].matlPass.textureStage != undefined) do
					( txIdList = meshes[i].matlPass.textureStage.txIds )

					if txIdList != undefined then
					(
						if txIdList.count == 1 then
						(
							for f = 1 to meshes[i].faces.count do
							( setFaceMatID gmMeshes[i] f (txIdList[1] + 1) )
						)
						else
						(
							for f = 1 to meshes[i].faces.count do
							(
								if f <= txIdList.count do
								( setFaceMatID gmMeshes[i] f (txIdList[f] + 1) )
							)
						)
						update gmMeshes[i]
					)

					-- "No Multi-Mat" splitter: instead of leaving the mesh with a multi-material,
					-- split it into separate mesh objects (one per matID actually used), each
					-- with a single material assigned. Builds every bucket as a new mesh from
					-- the W3D source data (verts, faces, normals, txCoords) and then deletes
					-- the original node entirely. This is more reliable than mutating the
					-- original via meshOp.deleteFaces, which corrupts the TVFace/normal arrays
					-- and triggers "TVFace index out of range" errors downstream.
					if noMultiMat do
					(
						try
						(
							-- Snapshot the W3D source data for this mesh.
							local srcVertsW = meshes[i].verts
							local srcNormalsW = meshes[i].normals
							local srcFacesW = meshes[i].faces -- array of W3dMeshFace (vertIds is 0-based)
							local srcTxCoordsW = undefined
							if (meshes[i].matlPass != undefined) and (meshes[i].matlPass.textureStage != undefined) and (meshes[i].matlPass.textureStage.txCoords != undefined) do
								srcTxCoordsW = meshes[i].matlPass.textureStage.txCoords

							-- bucket faces by matID using the live mesh's per-face IDs (these were
							-- assigned just above from txIdList).
							local matIdBuckets = #()
							local matIdList2 = #()
							for f = 1 to gmMeshes[i].numFaces do
							(
								local mid = getFaceMatID gmMeshes[i] f
								local idx = findItem matIdList2 mid
								if idx == 0 then
								(
									append matIdList2 mid
									append matIdBuckets #{f}
								)
								else
								(
									matIdBuckets[idx][f] = true
								)
							)

							if matIdList2.count > 1 then
							(
								local origName = gmMeshes[i].name
								local origParent = gmMeshes[i].parent
								local origTransform = gmMeshes[i].transform
								local createdNames = #()
								local createdNodes = #()

								for k = 1 to matIdList2.count do
								(
									local mid = matIdList2[k]
									local newName = origName + " [matID " + (mid as string) + "]"
									local bucketFaces = matIdBuckets[k]

									-- Collect this bucket's face vertex-index triples (1-based) and
									-- the unique source vert IDs they use.
									local usedVerts = #{}
									local faceTris = #()
									for f in bucketFaces do
									(
										-- W3D vertIds are 0-based; +1 to match MAXScript indexing.
										local v0 = (srcFacesW[f].vertIds.x as integer) + 1
										local v1 = (srcFacesW[f].vertIds.y as integer) + 1
										local v2 = (srcFacesW[f].vertIds.z as integer) + 1
										append faceTris #(f, v0, v1, v2)
										usedVerts[v0] = true
										usedVerts[v1] = true
										usedVerts[v2] = true
									)

									-- Compact: only carry the verts this bucket actually uses.
									local oldToNew = #()
									local newVerts = #()
									local newNormals = #()
									for v in usedVerts do
									(
										append newVerts srcVertsW[v]
										if srcNormalsW != undefined and v <= srcNormalsW.count do
											append newNormals srcNormalsW[v]
										oldToNew[v] = newVerts.count
									)

									local newFaces = #()
									for tri in faceTris do
										append newFaces [oldToNew[tri[2]], oldToNew[tri[3]], oldToNew[tri[4]]]

									local newNode = undefined
									try ( newNode = mesh name:newName vertices:newVerts faces:newFaces ) catch ()

									if newNode != undefined then
									(
										-- per-vert normals
										for v = 1 to newNormals.count do
										( try ( setNormal newNode v newNormals[v] ) catch () )

										-- texture vertices (UVs) — copy txCoords for the used verts.
										if srcTxCoordsW != undefined do
										(
											try
											(
												setNumTVerts newNode newVerts.count
												buildTVFaces newNode
												local idxList = #()
												for v in usedVerts do append idxList v
												for j = 1 to idxList.count do
												(
													local sv = idxList[j]
													if sv <= srcTxCoordsW.count do
													(
														local uv = srcTxCoordsW[sv]
														setTVert newNode j (Point3 uv.x uv.y 0)
													)
												)
												-- setTVFace expects three integer args, not a Point3.
												for fIx = 1 to newFaces.count do
												(
													local nf = newFaces[fIx]
													setTVFace newNode fIx (nf.x as integer) (nf.y as integer) (nf.z as integer)
												)
											) catch ()
										)

										try ( newNode.material = gmMultiMatl.materialList[mid] ) catch ()
										try ( newNode.transform = origTransform ) catch ()
										try ( newNode.parent = origParent ) catch ()
										update newNode
										append createdNames newName
										append createdNodes newNode
										if debugOutput do
											format "    -> created matID % node=% (verts=% faces=%) at pos=%\n" mid newNode.name newVerts.count newFaces.count newNode.pos
									)
									else
									(
										if debugOutput do
											format "    -> matID % FAILED to create new mesh node\n" mid
									)
								)

								-- Replace the original in gmMeshes so downstream post-processing
								-- (normals reset, fix vertices, HLOD reparent) operates on a real
								-- node instead of the soon-to-be-deleted original. Pick the first
								-- created node as the representative.
								if createdNodes.count > 0 then
								(
									try ( delete gmMeshes[i] ) catch ()
									gmMeshes[i] = createdNodes[1]
									noMultiMatHandled = true
								)

								if debugOutput do
									format "  -> No Multi-Mat: split [%] into % mesh(es): %\n" origName createdNames.count createdNames
							)
							else
							(
								if debugOutput do
									format "  -> No Multi-Mat: [%] only uses 1 matID, no split needed\n" gmMeshes[i].name
							)
						)
						catch
						(
							if debugOutput do
								format "  -> No Multi-Mat [%]: FAILED with error: %\n" meshes[i].header.meshName (getCurrentException())
						)
					)
				)
				else
				(
					gmMatl = undefined
					matlName = meshes[i].vertMatls[1].vmName

					if userSeparateMaterial or (sceneMaterials[matlName] == undefined) then
					(
						-- Try W3D Tools material first when requested
						if useW3DMatl do
						(
							local texFile = ""
							if (meshes[i].textures != undefined) and (meshes[i].textures.count > 0) do
							( texFile = meshes[i].textures[1].txFileName )
							gmMatl = buildW3DMatl matlName meshes[i].vertMatls[1] texFile meshBlendMode
						)

						if gmMatl != undefined then
						(
							append sceneMaterials gmMatl
						)
						else
						(
						gmMatl = standardMaterial name:matlName
						gmMatl.ambient = meshes[i].vertMatls[1].vmInfo.ambient
						gmMatl.diffuse = meshes[i].vertMatls[1].vmInfo.diffuse
						gmMatl.specular = meshes[i].vertMatls[1].vmInfo.specular
						--gmMatl.emissive = meshes[i].vertMatls[1].vmInfo.emissive
						gmMatl.glossiness = meshes[i].vertMatls[1].vmInfo.shininess * 100
						gmMatl.opacity = meshes[i].vertMatls[1].vmInfo.opacity * 100
						--gmMatl.translucency = meshes[i].vertMatls[1].vmInfo.translucency
						if (meshes[i].textures != undefined) and (meshes[i].textures.count > 0) then
						(
							diffuseTex = bitmaptex filename:meshes[i].textures[1].txFileName
							-- default alphaSource = None so opaque meshes don't render transparent
							-- when the bitmap carries an alpha channel (alpha/additive branches below
							-- expect this to be None as well, so it's safe to set unconditionally).
							try ( diffuseTex.alphaSource = 2 ) catch () -- 0=Image,1=RGB Intensity,2=None(Opaque)
							gmMatl.diffuseMap = diffuseTex
							showTextureMap gmMatl gmMatl.diffuseMap true

							if meshAlpha do
							(
								opTex = bitmaptex filename:meshes[i].textures[1].txFileName
								opTex.monoOutput = 1 -- Alpha
								gmMatl.opacityMap = opTex
								showTextureMap gmMatl gmMatl.opacityMap true
							)
							if meshAdditive do
							(
								addOpTex = bitmaptex filename:meshes[i].textures[1].txFileName
								gmMatl.opacityMap = addOpTex
								showTextureMap gmMatl gmMatl.opacityMap true

								addSiTex = bitmaptex filename:meshes[i].textures[1].txFileName
								gmMatl.selfIllumMap = addSiTex
								showTextureMap gmMatl gmMatl.selfIllumMap true

								try ( gmMatl.useSelfIllumColor = true ) catch ()

								if debugOutput do
								( format "  -> additive: opacity+selfIllum maps wired\n" )
							)
						)
						append sceneMaterials gmMatl
						)  -- end inner else (standardMaterial fallback)
					)
					else
					(
						gmMatl = sceneMaterials[matlName]
					)
					gmMeshes[i].material = gmMatl
				)
			)
			
			-- map a texture at v1.02
			-- Skip when No Multi-Mat already replaced gmMeshes[i] with a split node:
			-- the split path already set up its own per-bucket UVs/normals, and the
			-- original-sized arrays here would index out of range on the smaller node.
			if not noMultiMatHandled and (meshes[i].matlPass != undefined) and (meshes[i].matlPass.textureStage != undefined) and (meshes[i].matlPass.textureStage.txCoords != undefined) then
			(
				numTVerts = meshes[i].matlPass.textureStage.txCoords.count
				setNumTVerts gmMeshes[i] numTVerts
				for v = 1 to numTVerts do
				(
					txCoord = meshes[i].matlPass.textureStage.txCoords[v]
					setTVert gmMeshes[i] v (Point3 txCoord.x txCoord.y 0)
				)
				numTFaces = meshes[i].faces.count
				buildTVFaces gmMeshes[i]

				for f = 1 to numTFaces do
				( setTVFace gmMeshes[i] f gmFaces[f] )
			)

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
					( wwAddBone gmPivots[p] gmMeshes[m] )
					
					for v = 1 to (meshes[m].vertInfs.boneIds1.count) do
					(
						--print v
						--print meshes[m].vertInfs.boneIds1[v]
						--print meshes[m].vertInfs.boneWgts1[v]
						--print meshes[m].vertInfs.boneIds2[v]
						--print meshes[m].vertInfs.boneWgts2[v]
						--print "---------------"
						
						if (meshes[m].vertInfs.boneIds1[v] > 0) do
						(
							curBone = gmPivots[meshes[m].vertInfs.boneIds1[v]]
							wwSetBoneWeight gmMeshes[m] (v - 1) 1 curBone meshes[m].vertInfs.boneWgts1[v]
						)
						if (meshes[m].vertInfs.boneIds2[v] > 0) and (meshes[m].vertInfs.boneWgts1[v] < 100) do
						(
							curBone = gmPivots[meshes[m].vertInfs.boneIds2[v]]
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
					try
					(
						for f = 1 to gmMeshes[i].numFaces do
							setFaceSmoothGroup gmMeshes[i] f 1
						update gmMeshes[i]
					) catch ()

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

rollout rltMain "W3D Importer" width:177 height:247
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

	-- ADVANCED tab controls (overlap the same vertical space; visibility toggled by rbgTab)
	checkbox ckbUseW3DMatl "Use W3D Materials" pos:[25,85] width:127 height:15 checked:false visible:false
	checkbox ckbDebugOutput "Debug Output" pos:[25,102] width:127 height:15 checked:false visible:false
	checkbox ckbIgnoreErrors "Strict Mode" pos:[25,119] width:127 height:15 checked:false visible:false tooltip:"Halt the import if a channel references an invalid pivot ID, instead of skipping it."
	checkbox ckbFixNormals "Fix Normals" pos:[25,136] width:127 height:15 checked:true visible:false
	checkbox ckbTga2Dds "tga2DDS" pos:[25,153] width:65 height:15 checked:false visible:false tooltip:"Rewrite .tga texture references to .dds (extension only; filename preserved)"
	checkbox ckbTga2DdsRev "rev" pos:[92,153] width:60 height:15 checked:false enabled:false visible:false tooltip:"Reverse: rename .dds to .tga (only available while tga2DDS is enabled)"
	checkbox ckbFixVertices "Fix Vertices" pos:[25,170] width:127 height:15 checked:false visible:false tooltip:"Per-element smoothing groups, then weld vertices at 0.01 threshold (preserves smoothing across the weld)"
	checkbox ckbNoMultiMat "No Multi-Mat" pos:[25,187] width:127 height:15 checked:false visible:false tooltip:"Split meshes that would use a multi-material into separate meshes (one per texture), each with a single material assigned"

	on btnW3DImporter pressed do
	(
		if ckbBatchProcessing.checked then
		(
			fldrPath = getSavePath()
			if (fldrPath != undefined) do
			(
				w3dFiles = getFiles(fldrPath + "\\*.w3d")
				for i=1 to w3dFiles.count do
				( cfW3DImporter w3dFiles[i] ckbSplitDependencies.checked rbgAutoBind.state true ckbDebugOutput.checked ckbUseW3DMatl.checked (not ckbIgnoreErrors.checked) ckbFixNormals.checked ckbTga2Dds.checked ckbFixVertices.checked ckbNoMultiMat.checked ckbTga2DdsRev.checked )
			)
		)
		else
		( cfW3DImporter undefined ckbSplitDependencies.checked rbgAutoBind.state false ckbDebugOutput.checked ckbUseW3DMatl.checked (not ckbIgnoreErrors.checked) ckbFixNormals.checked ckbTga2Dds.checked ckbFixVertices.checked ckbNoMultiMat.checked ckbTga2DdsRev.checked )
	)

	-- enable rev only while tga2DDS is on; uncheck it when tga2DDS is turned off
	on ckbTga2Dds changed st do
	(
		ckbTga2DdsRev.enabled = st
		if not st do ckbTga2DdsRev.checked = false
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
		)
		else
		(
			rbgAutoBind.enabled = false
			rbgAutoBind.state = 0
			
			ckbBatchProcessing.checked = false
			ckbBatchProcessing.enabled = false
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

		ckbUseW3DMatl.visible        = not basic
		ckbDebugOutput.visible       = not basic
		ckbIgnoreErrors.visible      = not basic
		ckbFixNormals.visible        = not basic
		ckbTga2Dds.visible           = not basic
		ckbTga2DdsRev.visible        = not basic
		ckbFixVertices.visible       = not basic
		ckbNoMultiMat.visible        = not basic
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