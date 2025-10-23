import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart';
import 'index.dart';

/* GLTF PARSER */
class GLTFParser {
  late FileLoader fileLoader;
  late Map<String, dynamic> json;
  late dynamic extensions;
  late Map plugins;
  late Map<String, dynamic> options;
  late GLTFRegistry cache;
  late Map associations;
  late Map primitiveCache;
  late Map meshCache;
  late Map cameraCache;
  late Map lightCache;
  late Map nodeNamesUsed;
  late TextureLoader textureLoader;

  Function? createNodeAttachment;
  Function? extendMaterialParams;
  Function? loadBufferView;

  late Map textureCache;
  late Map sourceCache;

  GLTFParser(json, Map<String, dynamic>? options) {
    this.json = json ?? {};
    extensions = {};
    plugins = {};
    this.options = options ?? {};

    // loader object cache
    cache = GLTFRegistry();

    textureCache = {};
    sourceCache = {};

    // associations between Three.js objects and glTF elements
    associations = {};

    // BufferGeometry caching
    primitiveCache = {};

    // Object3D instance caches
    meshCache = {"refs": {}, "uses": {}};
    cameraCache = {"refs": {}, "uses": {}};
    lightCache = {"refs": {}, "uses": {}};

    // Track node names, to ensure no duplicates
    nodeNamesUsed = {};

    // Use an ImageBitmapLoader if imageBitmaps are supported. Moves much of the
    // expensive work of uploading a texture to the GPU off the main thread.
    // if ( createImageBitmap != null && /Firefox/.test( navigator.userAgent ) == false ) {
    //   this.textureLoader = new ImageBitmapLoader( this.options.manager );
    // } else {
    textureLoader = TextureLoader(this.options["manager"]);
    // }

    textureLoader.setCrossOrigin(this.options["crossOrigin"]);
    textureLoader.setRequestHeader(this.options["requestHeader"]);

    fileLoader = FileLoader(this.options["manager"]);
    fileLoader.setResponseType('arraybuffer');

    if (this.options["crossOrigin"] == 'use-credentials') {
      fileLoader.setWithCredentials(true);
    }

    loadBufferView = loadBufferView2;
  }

  setExtensions(extensions) {
    this.extensions = extensions;
  }

  setPlugins(plugins) {
    this.plugins = plugins;
  }

  parse(onLoad, onError) async {
    var parser = this;
    var json = this.json;
    var extensions = this.extensions;

    // Clear the loader cache
    cache.removeAll();

    // Mark the special nodes/meshes in json for efficient parse
    _invokeAll((ext) {
      return ext._markDefs != null && ext._markDefs() != null;
    });

    final scenes = await getDependencies('scene');
    final animations = await getDependencies('animation');
    final cameras = await getDependencies('camera');

    var result = {
      "scene": scenes[json["scene"] ?? 0],
      "scenes": scenes,
      "animations": animations,
      "cameras": cameras,
      "asset": json["asset"],
      "parser": parser,
      "userData": {}
    };

    addUnknownExtensionsToUserData(extensions, result, json);

    assignExtrasToUserData(result, json);

    onLoad(result);
  }

  /// Marks the special nodes/meshes in json for efficient parse.
  // _markDefs() {
  //   var nodeDefs = json["nodes"] ?? [];
  //   var skinDefs = json["skins"] ?? [];
  //   var meshDefs = json["meshes"] ?? [];

  //   // Nothing in the node definition indicates whether it is a Bone or an
  //   // Object3D. Use the skins' joint references to mark bones.
  //   for (var skinIndex = 0, skinLength = skinDefs.length; skinIndex < skinLength; skinIndex++) {
  //     var joints = skinDefs[skinIndex]["joints"];

  //     for (var i = 0, il = joints.length; i < il; i++) {
  //       nodeDefs[joints[i]]["isBone"] = true;
  //     }
  //   }

  //   // Iterate over all nodes, marking references to shared resources,
  //   // as well as skeleton joints.
  //   for (var nodeIndex = 0, nodeLength = nodeDefs.length; nodeIndex < nodeLength; nodeIndex++) {
  //     Map<String, dynamic> nodeDef = nodeDefs[nodeIndex];

  //     if (nodeDef["mesh"] != null) {
  //       _addNodeRef(meshCache, nodeDef["mesh"]);

  //       // Nothing in the mesh definition indicates whether it is
  //       // a SkinnedMesh or Mesh. Use the node's mesh reference
  //       // to mark SkinnedMesh if node has skin.
  //       if (nodeDef["skin"] != null) {
  //         meshDefs[nodeDef["mesh"]]["isSkinnedMesh"] = true;
  //       }
  //     }

  //     if (nodeDef["camera"] != null) {
  //       _addNodeRef(cameraCache, nodeDef["camera"]);
  //     }
  //   }
  // }

  /// Counts references to shared node / Object3D resources. These resources
  /// can be reused, or "instantiated", at multiple nodes in the scene
  /// hierarchy. Mesh, Camera, and Light instances are instantiated and must
  /// be marked. Non-scenegraph resources (like Materials, Geometries, and
  /// Textures) can be reused directly and are not marked here.
  ///
  /// Example: CesiumMilkTruck sample model reuses "Wheel" meshes.
  // _addNodeRef(cache, index) {
  //   if (index == null) return;

  //   if (cache["refs"][index] == null) {
  //     cache["refs"][index] = cache["uses"][index] = 0;
  //   }

  //   cache["refs"][index]++;
  // }

  /// Returns a reference to a shared resource, cloning it if necessary.
  _getNodeRef(cache, index, object) {
    if (cache["refs"][index] <= 1) return object;

    var ref = object.clone();

    ref.name += '_instance_${(cache["uses"][index]++)}';

    return ref;
  }

  _invokeOne(Function func) async {
    var extensions = plugins.values.toList();
    extensions.add(this);

    for (var i = 0; i < extensions.length; i++) {
      var result = await func(extensions[i]);
      if (result != null) return result;
    }
  }

  _invokeAll(Function func) async {
    var extensions = plugins.values.toList();
    unshift(extensions, this);

    var results = [];

    for (var i = 0; i < extensions.length; i++) {
      var result = await func(extensions[i]);

      if (result != null) results.add(result);
    }

    return results;
  }

  /// Requests the specified dependency asynchronously, with caching.
  /// @param {string} type
  /// @param {number} index
  /// @return {Promise<Object3D|Material|THREE.Texture|AnimationClip|ArrayBuffer|Object>}
  getDependency(type, index) async {
    var cacheKey = '$type:$index';
    var dependency = cache.get(cacheKey);

    // print(" GLTFParse.getDependency type: ${type} index: ${index} ");

    if (dependency == null) {
      switch (type) {
        case 'scene':
          dependency = await loadScene(index);
          break;

        case 'node':
          dependency = await loadNode(index);
          break;

        case 'mesh':
          dependency = await _invokeOne((ext) async {
            return ext.loadMesh != null ? await ext.loadMesh(index) : null;
          });
          break;

        case 'accessor':
          dependency = await loadAccessor(index);
          break;

        case 'bufferView':
          dependency = await _invokeOne((ext) async {
            return ext.loadBufferView != null ? await ext.loadBufferView(index) : null;
          });

          break;

        case 'buffer':
          dependency = await loadBuffer(index);
          break;

        case 'material':
          dependency = await _invokeOne((ext) async {
            return ext.loadMaterial != null ? await ext.loadMaterial(index) : null;
          });
          break;

        case 'texture':
          dependency = await _invokeOne((ext) async {
            return ext.loadTexture != null ? await ext.loadTexture(index) : null;
          });
          break;

        case 'skin':
          dependency = await loadSkin(index);
          break;

        case 'animation':
          dependency = await loadAnimation(index);
          break;

        case 'camera':
          dependency = await loadCamera(index);
          break;

        default:
          throw ('GLTFParser getDependency Unknown type: $type');
      }

      cache.add(cacheKey, dependency);
    }

    return dependency;
  }

  /// Requests all dependencies of the specified type asynchronously, with caching.
  /// @param {string} type
  /// @return {Promise<Array<Object>>}
  getDependencies(type) async {
    var dependencies = cache.get(type);

    if (dependencies != null) {
      return dependencies;
    }

    var parser = this;
    var defs = json[type + (type == 'mesh' ? 'es' : 's')] ?? [];

    List deps = [];

    int l = defs.length;

    for (var i = 0; i < l; i++) {
      var dep = await parser.getDependency(type, i);
      deps.add(dep);
    }

    cache.add(type, deps);

    return deps;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#buffers-and-buffer-views
  /// @param {number} bufferIndex
  /// @return {Promise<ArrayBuffer>}
  loadBuffer(bufferIndex) async {
    Map<String, dynamic> bufferDef = json["buffers"][bufferIndex];
    var loader = fileLoader;

    if (bufferDef["type"] != null && bufferDef["type"] != 'arraybuffer') {
      throw ('THREE.GLTFLoader: ${bufferDef["type"]} buffer type is not supported.');
    }

    // If present, GLB container is required to be the first buffer.
    if (bufferDef["uri"] == null && bufferIndex == 0) {
      return extensions[gltfExtensions["KHR_BINARY_GLTF"]].body;
    }

    var options = this.options;

    var url = LoaderUtils.resolveURL(bufferDef["uri"], options["path"]);

    final res = await loader.loadAsync(url);

    return res;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#buffers-and-buffer-views
  /// @param {number} bufferViewIndex
  /// @return {Promise<ArrayBuffer>}
  loadBufferView2(bufferViewIndex) async {
    var bufferViewDef = json["bufferViews"][bufferViewIndex];
    var buffer = await getDependency('buffer', bufferViewDef["buffer"]);

    var byteLength = bufferViewDef["byteLength"] ?? 0;
    var byteOffset = bufferViewDef["byteOffset"] ?? 0;

    // use sublist(0) clone new list, if not when load texture decode image will fail ? and with no error, return null image

    if (buffer is Uint8List) {
      return Uint8List.view(buffer.buffer, byteOffset, byteLength).sublist(0).buffer;
    } else {
      return Uint8List.view(buffer, byteOffset, byteLength).sublist(0).buffer;
    }
  }

  /// Specification: https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#accessors
  /// @param {number} accessorIndex
  /// @return {Promise<BufferAttribute|InterleavedBufferAttribute>}
  loadAccessor(accessorIndex) async {
    var parser = this;
    var json = this.json;

    Map<String, dynamic> accessorDef = this.json["accessors"][accessorIndex];

    if (accessorDef["bufferView"] == null && accessorDef["sparse"] == null) {
      // Ignore empty accessors, which may be used to declare runtime
      // information about attributes coming from another source (e.g. Draco
      // compression extension).
      return null;
    }

    var bufferView;
    if (accessorDef["bufferView"] != null) {
      bufferView = await getDependency('bufferView', accessorDef["bufferView"]);
    } else {
      bufferView = null;
    }

    var sparseIndicesBufferView;
    var sparseValuesBufferView;

    if (accessorDef["sparse"] != null) {
      final sparse = accessorDef["sparse"];
      sparseIndicesBufferView = await getDependency('bufferView', sparse["indices"]["bufferView"]);
      sparseValuesBufferView = await getDependency('bufferView', sparse["values"]["bufferView"]);
    }

    int itemSize = webGlTypeSizes[accessorDef["type"]]!;
    var typedArray = GLTypeData(accessorDef["componentType"]);

    // For VEC3: itemSize is 3, elementBytes is 4, itemBytes is 12.
    var elementBytes = typedArray.getBytesPerElement();
    var itemBytes = elementBytes * itemSize;
    var byteOffset = accessorDef["byteOffset"] ?? 0;
    var byteStride =
        accessorDef["bufferView"] != null ? json["bufferViews"][accessorDef["bufferView"]]["byteStride"] : null;
    var normalized = accessorDef["normalized"] == true;
    List<double> array;
    var bufferAttribute;

    // The buffer is not interleaved if the stride is the item size in bytes.
    if (byteStride != null && byteStride != itemBytes) {
      // Each "slice" of the buffer, as defined by 'count' elements of 'byteStride' bytes, gets its own InterleavedBuffer
      // This makes sure that IBA.count reflects accessor.count properly
      var ibSlice = Math.floor(byteOffset / byteStride);
      var ibCacheKey =
          'InterleavedBuffer:${accessorDef["bufferView"]}:${accessorDef["componentType"]}:$ibSlice:${accessorDef["count"]}';
      var ib = parser.cache.get(ibCacheKey);

      if (ib == null) {
        // array = TypedArray.view( bufferView, ibSlice * byteStride, accessorDef.count * byteStride / elementBytes );
        array = typedArray.view(bufferView, ibSlice * byteStride, accessorDef["count"] * byteStride / elementBytes);

        // Integer parameters to IB/IBA are in array elements, not bytes.
        ib = InterleavedBuffer(Float32Array.fromList(array), byteStride / elementBytes);

        parser.cache.add(ibCacheKey, ib);
      }

      bufferAttribute = InterleavedBufferAttribute(ib, itemSize, (byteOffset % byteStride) / elementBytes, normalized);
    } else {
      if (bufferView == null) {
        array = typedArray.createList(accessorDef["count"] * itemSize);
        bufferAttribute = GLTypeData.createBufferAttribute(array, itemSize, normalized);
      } else {
        var array = typedArray.view(bufferView, byteOffset, accessorDef["count"] * itemSize);
        bufferAttribute = GLTypeData.createBufferAttribute(array, itemSize, normalized);
      }
    }

    // https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#sparse-accessors
    if (accessorDef["sparse"] != null) {
      var itemSizeIndices = webGlTypeSizes["SCALAR"]!;
      var typedArrayIndices = GLTypeData(accessorDef["sparse"]["indices"]["componentType"]);

      var byteOffsetIndices = accessorDef["sparse"]["indices"]["byteOffset"] ?? 0;
      var byteOffsetValues = accessorDef["sparse"]["values"]["byteOffset"] ?? 0;

      var sparseIndices = typedArrayIndices.view(
          sparseIndicesBufferView, byteOffsetIndices, accessorDef["sparse"]["count"] * itemSizeIndices);
      var sparseValues =
          typedArray.view(sparseValuesBufferView, byteOffsetValues, accessorDef["sparse"]["count"] * itemSize);

      if (bufferView != null) {
        // Avoid modifying the original ArrayBuffer, if the bufferView wasn't initialized with zeroes.
        bufferAttribute =
            Float32BufferAttribute(bufferAttribute.array.clone(), bufferAttribute.itemSize, bufferAttribute.normalized);
      }

      for (var i = 0, il = sparseIndices.length; i < il; i++) {
        var index = sparseIndices[i];

        bufferAttribute.setX(index, sparseValues[i * itemSize]);
        if (itemSize >= 2) bufferAttribute.setY(index, sparseValues[i * itemSize + 1]);
        if (itemSize >= 3) bufferAttribute.setZ(index, sparseValues[i * itemSize + 2]);
        if (itemSize >= 4) bufferAttribute.setW(index, sparseValues[i * itemSize + 3]);
        if (itemSize >= 5) throw ('THREE.GLTFLoader: Unsupported itemSize in sparse BufferAttribute.');
      }
    }

    return bufferAttribute;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#textures
  /// @param {number} textureIndex
  /// @return {Promise<THREE.Texture>}
  loadTexture(textureIndex) async {
    var parser = this;
    Map<String, dynamic> json = this.json;
    var options = this.options;

    Map<String, dynamic> textureDef = json["textures"][textureIndex];
    var sourceIndex = textureDef["source"];
    var sourceDef = json["images"][sourceIndex];

    var textureExtensions = textureDef["extensions"] ?? {};

    // var source;

    // if (textureExtensions[gltfExtensions["MSFT_TEXTURE_DDS"]] != null) {
    //   source = json["images"][textureExtensions[gltfExtensions["MSFT_TEXTURE_DDS"]]["source"]];
    // } else {
    //   source = json["images"][textureDef["source"]];
    // }

    var loader;

    if (sourceDef["uri"] != null) {
      loader = options["manager"].getHandler(sourceDef["uri"]);
    }

    loader ??= textureExtensions[gltfExtensions["MSFT_TEXTURE_DDS"]] != null
        ? parser.extensions[gltfExtensions["MSFT_TEXTURE_DDS"]]["ddsLoader"]
        : textureLoader;

    return loadTextureImage(textureIndex, sourceIndex, loader);
  }

  loadTextureImage(textureIndex, sourceIndex, loader) async {
    // print(" GLTFParser.loadTextureImage source: ${source} textureIndex: ${textureIndex} loader: ${loader} ");

    var parser = this;
    var json = this.json;

    Map textureDef = json["textures"][textureIndex];
    Map sourceDef = json["images"][sourceIndex];

    // var URL = self.URL || self.webkitURL;

    var cacheKey = '${(sourceDef["uri"] ?? sourceDef["bufferView"])}:${textureDef["sampler"]}';

    if (textureCache[cacheKey] != null) {
      // See https://github.com/mrdoob/three.js/issues/21559.
      return textureCache[cacheKey];
    }

    loader.flipY = false;
    var texture = await loadImageSource(sourceIndex, loader);

    texture.flipY = false;

    if (textureDef["name"] != null) texture.name = textureDef["name"];

    var samplers = json["samplers"] ?? {};
    Map sampler = samplers[textureDef["sampler"]] ?? {};

    texture.magFilter = webGlFilters[sampler["magFilter"]] ?? LinearFilter;
    texture.minFilter = webGlFilters[sampler["minFilter"]] ?? LinearMipmapLinearFilter;
    texture.wrapS = webGlWrappings[sampler["wrapS"]] ?? RepeatWrapping;
    texture.wrapT = webGlWrappings[sampler["wrapT"]] ?? RepeatWrapping;

    parser.associations[texture] = {"textures": textureIndex};

    textureCache[cacheKey] = texture;

    return texture;

    // String sourceURI = sourceDef["uri"] ?? "";
    // var isObjectURL = false;

    // var texture;
    // loader.flipY = false;

    // if (sourceDef["bufferView"] != null) {
    //   // Load binary image data from bufferView, if provided.

    //   // print("GLTFParser.loadTextureImage textureIndex: ${textureIndex} source->bufferView is not null TODO ");

    //   var bufferView =
    //       await parser.getDependency('bufferView', sourceDef["bufferView"]);

    //   if (sourceDef["mimeType"] == 'image/png') {
    //     // Inspect the PNG 'IHDR' chunk to determine whether the image could have an
    //     // alpha channel. This check is conservative — the image could have an alpha
    //     // channel with all values == 1, and the indexed type (colorType == 3) only
    //     // sometimes contains alpha.
    //     //
    //     // https://en.wikipedia.org/wiki/Portable_Network_Graphics#File_header
    //     var colorType = new ByteData.view(bufferView, 25, 1).getUint8(0);
    //   }

    //   // should be in a isolate
    //   // var _image = Image.decodeImage( bufferView.asUint8List() );
    //   // var _pixels = _image!.getBytes();

    //   // var imageElement = ImageElement(data: _pixels, width: _image.width, height: _image.height);
    //   // texture = Texture(imageElement, null, null, null, null, null, null, null, null, null);

    //   isObjectURL = true;
    //   var blob = Blob(bufferView.asUint8List(), {"type": source["mimeType"]});
    //   // sourceURI = createObjectURL( blob );

    //   texture = await loader.loadAsync(blob, null);
    // } else if (sourceDef["uri"] == null) {
    //   throw ('THREE.GLTFLoader: Image ' +
    //       textureIndex +
    //       ' is missing URI and bufferView');
    // } else if (sourceDef["uri"] != null) {
    //   // https://github.com/wasabia/three_dart/issues/10

    //   texture = await loader.loadAsync(
    //       LoaderUtils.resolveURL(sourceURI, options["path"]), null);
    // }

    // texture.needsUpdate = true;
    // texture.flipY = false;

    // if (textureDef["name"] != null) {
    //   texture.name = textureDef["name"];
    // } else {
    //   texture.name = sourceDef["name"] ?? "";
    // }

    // var samplers = json["samplers"] ?? {};
    // var sampler = samplers[textureDef["sampler"]] ?? {};

    // texture.magFilter = WEBGL_FILTERS[sampler["magFilter"]] ?? LinearFilter;
    // texture.minFilter =
    //     WEBGL_FILTERS[sampler["minFilter"]] ?? LinearMipmapLinearFilter;
    // texture.wrapS = WEBGL_WRAPPINGS[sampler["wrapS"]] ?? RepeatWrapping;
    // texture.wrapT = WEBGL_WRAPPINGS[sampler["wrapT"]] ?? RepeatWrapping;

    // // parser.associations.set( texture, {
    // //   type: 'textures',
    // //   index: textureIndex
    // // } );

    // parser.associations[texture] = {"type": "textures", "index": textureIndex};

    // // this.textureCache[ cacheKey ] = texture;

    // return texture;
  }

  loadImageSource(sourceIndex, loader) async {
    var parser = this;
    var json = this.json;
    var options = this.options;
    var texture;

    if (sourceCache[sourceIndex] != null) {
      texture = sourceCache[sourceIndex];
      return texture.clone();
    }

    Map sourceDef = json["images"][sourceIndex];

    // var URL = self.URL || self.webkitURL;

    var sourceURI = sourceDef["uri"] ?? '';
    // var isObjectURL = false;

    print("loader: $loader ");

    if (sourceDef["bufferView"] != null) {
      // Load binary image data from bufferView, if provided.

      var bufferView = await parser.getDependency('bufferView', sourceDef["bufferView"]);

      // isObjectURL = true;
      var blob = Blob(bufferView.asUint8List(), {"type": sourceDef["mimeType"]});
      // sourceURI = URL.createObjectURL( blob );

      texture = await loader.loadAsync(blob, null);
    } else if (sourceDef["uri"] != null) {
      texture = await loader.loadAsync(LoaderUtils.resolveURL(sourceURI, options["path"]), null);
    } else if (sourceDef["uri"] == null) {
      throw ('THREE.GLTFLoader: Image $sourceIndex is missing URI and bufferView');
    }

    sourceCache[sourceIndex] = texture;
    return texture;
  }

  /// Asynchronously assigns a texture to the given material parameters.
  /// @param {Object} materialParams
  /// @param {string} mapName
  /// @param {Object} mapDef
  /// @return {Promise}
  assignTexture(materialParams, mapName, Map<String, dynamic> mapDef, [encoding]) async {
    var parser = this;

    var texture = await getDependency('texture', mapDef["index"]);

    // Materials sample aoMap from UV set 1 and other maps from UV set 0 - this can't be configured
    // However, we will copy UV set 0 to UV set 1 on demand for aoMap
    if (mapDef["texCoord"] != null && mapDef["texCoord"] != 0 && !(mapName == 'aoMap' && mapDef["texCoord"] == 1)) {
      print('THREE.GLTFLoader: Custom UV set ${mapDef["texCoord"]} for texture $mapName not yet supported.');
    }

    if (parser.extensions[gltfExtensions["KHR_TEXTURE_TRANSFORM"]] != null) {
      var transform =
          mapDef["extensions"] != null ? mapDef["extensions"][gltfExtensions["KHR_TEXTURE_TRANSFORM"]] : null;

      if (transform != null) {
        var gltfReference = parser.associations[texture];
        texture = parser.extensions[gltfExtensions["KHR_TEXTURE_TRANSFORM"]].extendTexture(texture, transform);
        parser.associations[texture] = gltfReference;
      }
    }

    if (encoding != null) {
      texture.encoding = encoding;
    }

    materialParams[mapName] = texture;

    return texture;
  }

  /// Assigns final material to a Mesh, Line, or Points instance. The instance
  /// already has a material (generated from the glTF material options alone)
  /// but reuse of the same glTF material may require multiple threejs materials
  /// to accomodate different primitive types, defines, etc. New materials will
  /// be created if necessary, and reused from a cache.
  /// @param  {Object3D} mesh Mesh, Line, or Points instance.
  assignFinalMaterial(mesh) {
    var geometry = mesh.geometry;
    var material = mesh.material;

    bool useVertexTangents = geometry.attributes["tangent"] != null;
    bool useVertexColors = geometry.attributes["color"] != null;
    bool useFlatShading = geometry.attributes["normal"] == null;

    if (mesh is Points) {
      var cacheKey = 'PointsMaterial: ${material.uuid}';

      var pointsMaterial = cache.get(cacheKey);

      if (pointsMaterial == null) {
        pointsMaterial = PointsMaterial({});
        pointsMaterial.copy(material);
        pointsMaterial.color.copy(material.color);
        pointsMaterial.map = material.map;
        pointsMaterial.sizeAttenuation = false; // glTF spec says points should be 1px

        cache.add(cacheKey, pointsMaterial);
      }

      material = pointsMaterial;
    } else if (mesh is Line) {
      var cacheKey = 'LineBasicMaterial: ${material.uuid}';

      var lineMaterial = cache.get(cacheKey);

      if (lineMaterial == null) {
        lineMaterial = LineBasicMaterial({});
        lineMaterial.copy(material);
        lineMaterial.color.copy(material.color);

        cache.add(cacheKey, lineMaterial);
      }

      material = lineMaterial;
    }

    // Clone the material if it will be modified
    if (useVertexTangents || useVertexColors || useFlatShading) {
      var cacheKey = 'ClonedMaterial: ${material.uuid}:';

      if (material.type == "GLTFSpecularGlossinessMaterial") cacheKey += 'specular-glossiness:';
      if (useVertexTangents) cacheKey += 'vertex-tangents:';
      if (useVertexColors) cacheKey += 'vertex-colors:';
      if (useFlatShading) cacheKey += 'flat-shading:';

      var cachedMaterial = cache.get(cacheKey);

      if (cachedMaterial == null) {
        cachedMaterial = material.clone();

        if (useVertexTangents) cachedMaterial.vertexTangents = true;
        if (useVertexColors) cachedMaterial.vertexColors = true;
        if (useFlatShading) cachedMaterial.flatShading = true;

        cache.add(cacheKey, cachedMaterial);

        associations[cachedMaterial] = associations[material];
      }

      material = cachedMaterial;
    }

    // workarounds for mesh and geometry

    if (material.aoMap != null && geometry.attributes["uv2"] == null && geometry.attributes["uv"] != null) {
      geometry.setAttribute('uv2', geometry.attributes["uv"]);
    }

    // https://github.com/mrdoob/three.js/issues/11438#issuecomment-507003995
    if (material.normalScale != null && !useVertexTangents) {
      material.normalScale.y = -material.normalScale.y;
    }

    if (material.clearcoatNormalScale != null && !useVertexTangents) {
      material.clearcoatNormalScale.y = -material.clearcoatNormalScale.y;
    }

    mesh.material = material;
  }

  getMaterialType(materialIndex) {
    return MeshStandardMaterial;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#materials
  /// @param {number} materialIndex
  /// @return {Promise<Material>}
  loadMaterial(materialIndex) async {
    var parser = this;
    var json = this.json;
    var extensions = this.extensions;
    Map<String, dynamic> materialDef = json["materials"][materialIndex];

    var materialType;
    Map<String, dynamic> materialParams = {};
    Map<String, dynamic> materialExtensions = materialDef["extensions"] ?? {};

    List pending = [];

    if (materialExtensions[gltfExtensions["KHR_MATERIALS_PBR_SPECULAR_GLOSSINESS"]] != null) {
      var sgExtension = extensions[gltfExtensions["KHR_MATERIALS_PBR_SPECULAR_GLOSSINESS"]];
      materialType = sgExtension.getMaterialType(materialIndex);
      pending.add(sgExtension.extendParams(materialParams, materialDef, parser));
    } else if (materialExtensions[gltfExtensions["KHR_MATERIALS_UNLIT"]] != null) {
      var kmuExtension = extensions[gltfExtensions["KHR_MATERIALS_UNLIT"]];
      materialType = kmuExtension.getMaterialType(materialIndex);
      pending.add(kmuExtension.extendParams(materialParams, materialDef, parser));
    } else {
      // Specification:
      // https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#metallic-roughness-material

      Map<String, dynamic> metallicRoughness = materialDef["pbrMetallicRoughness"] ?? {};

      materialParams["color"] = Color(1.0, 1.0, 1.0);
      materialParams["opacity"] = 1.0;

      if (metallicRoughness["baseColorFactor"] is List) {
        List<double> array = List<double>.from(metallicRoughness["baseColorFactor"].map((e) => e.toDouble()));

        materialParams["color"].fromArray(array);
        materialParams["opacity"] = array[3];
      }

      if (metallicRoughness["baseColorTexture"] != null) {
        pending.add(
            await parser.assignTexture(materialParams, 'map', metallicRoughness["baseColorTexture"], sRGBEncoding));
      }

      materialParams["metalness"] = metallicRoughness["metallicFactor"] ?? 1.0;
      materialParams["roughness"] = metallicRoughness["roughnessFactor"] ?? 1.0;

      if (metallicRoughness["metallicRoughnessTexture"] != null) {
        pending.add(
            await parser.assignTexture(materialParams, 'metalnessMap', metallicRoughness["metallicRoughnessTexture"]));
        pending.add(
            await parser.assignTexture(materialParams, 'roughnessMap', metallicRoughness["metallicRoughnessTexture"]));
      }

      materialType = await _invokeOne((ext) async {
        return ext.getMaterialType != null ? await ext.getMaterialType(materialIndex) : null;
      });

      final v = await _invokeAll((ext) {
        return ext.extendMaterialParams != null && ext.extendMaterialParams(materialIndex, materialParams) != null;
      });

      pending.add(v);
    }

    if (materialDef["doubleSided"] == true) {
      materialParams["side"] = DoubleSide;
    }

    var alphaMode = materialDef["alphaMode"] ?? alphaModes["OPAQUE"];

    if (alphaMode == alphaModes["BLEND"]) {
      materialParams["transparent"] = true;

      // See: https://github.com/mrdoob/three.js/issues/17706
      materialParams["depthWrite"] = false;
    } else {
      materialParams["transparent"] = false;

      if (alphaMode == alphaModes["MASK"]) {
        materialParams["alphaTest"] = materialDef["alphaCutoff"] ?? 0.5;
      }
    }

    if (materialDef["normalTexture"] != null && materialType != MeshBasicMaterial) {
      pending.add(await parser.assignTexture(materialParams, 'normalMap', materialDef["normalTexture"]));

      if (materialDef["normalTexture"]["scale"] != null) {
        materialParams["normalScale"] = Vector2(materialDef["normalTexture"].scale, materialDef["normalTexture"].scale);
      }
    }

    if (materialDef["occlusionTexture"] != null && materialType != MeshBasicMaterial) {
      pending.add(await parser.assignTexture(materialParams, 'aoMap', materialDef["occlusionTexture"]));

      if (materialDef["occlusionTexture"]["strength"] != null) {
        materialParams["aoMapIntensity"] = materialDef["occlusionTexture"]["strength"];
      }
    }

    if (materialDef["emissiveFactor"] != null && materialType != MeshBasicMaterial) {
      materialParams["emissive"] =
          Color(1, 1, 1).fromArray(List<double>.from(materialDef["emissiveFactor"].map((e) => e.toDouble())));
    }

    if (materialDef["emissiveTexture"] != null && materialType != MeshBasicMaterial) {
      pending
          .add(await parser.assignTexture(materialParams, 'emissiveMap', materialDef["emissiveTexture"], sRGBEncoding));
    }

    // await Future.wait(pending);

    var material;

    if (materialType == GLTFMeshStandardSGMaterial) {
      material = extensions[gltfExtensions["KHR_MATERIALS_PBR_SPECULAR_GLOSSINESS"]].createMaterial(materialParams);
    } else {
      material = createMaterialType(materialType, materialParams);
    }

    if (materialDef["name"] != null) material.name = materialDef["name"];

    assignExtrasToUserData(material, materialDef);

    parser.associations[material] = {"type": 'materials', "index": materialIndex};

    if (materialDef["extensions"] != null) addUnknownExtensionsToUserData(extensions, material, materialDef);

    return material;
  }

  createMaterialType(materialType, Map<String, dynamic> materialParams) {
    if (materialType == GLTFMeshStandardSGMaterial) {
      return GLTFMeshStandardSGMaterial(materialParams);
    } else if (materialType == MeshBasicMaterial) {
      return MeshBasicMaterial(materialParams);
    } else if (materialType == MeshPhysicalMaterial) {
      return MeshPhysicalMaterial(materialParams);
    } else if (materialType == MeshStandardMaterial) {
      return MeshStandardMaterial(materialParams);
    } else {
      throw ("GLTFParser createMaterialType materialType: ${materialType.runtimeType.toString()} is not support ");
    }
  }

  /// When Object3D instances are targeted by animation, they need unique names.
  createUniqueName(originalName) {
    var sanitizedName = PropertyBinding.sanitizeNodeName(originalName ?? '');

    var name = sanitizedName;

    for (var i = 1; nodeNamesUsed[name] != null; ++i) {
      name = '${sanitizedName}_$i';
    }

    nodeNamesUsed[name] = true;

    return name;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#geometry
  ///
  /// Creates BufferGeometries from primitives.
  ///
  /// @param {Array<GLTF.Primitive>} primitives
  /// @return {Promise<Array<BufferGeometry>>}
  loadGeometries(primitives) async {
    var parser = this;
    var extensions = this.extensions;
    var cache = primitiveCache;

    createDracoPrimitive(primitive) async {
      var geometry = await extensions[gltfExtensions["KHR_DRACO_MESH_COMPRESSION"]].decodePrimitive(primitive, parser);
      return await addPrimitiveAttributes(geometry, primitive, parser);
    }

    List<BufferGeometry> pending = [];

    for (var i = 0, il = primitives.length; i < il; i++) {
      Map<String, dynamic> primitive = primitives[i];
      var cacheKey = createPrimitiveKey(primitive);

      // See if we've already created this geometry
      var cached = cache[cacheKey];

      if (cached != null) {
        // Use the cached geometry if it exists
        pending.add(cached.promise);
      } else {
        var geometryPromise;

        if (primitive["extensions"] != null &&
            primitive["extensions"][gltfExtensions["KHR_DRACO_MESH_COMPRESSION"]] != null) {
          // Use DRACO geometry if available
          geometryPromise = await createDracoPrimitive(primitive);
        } else {
          // Otherwise create a new geometry
          geometryPromise = await addPrimitiveAttributes(BufferGeometry(), primitive, parser);
        }

        // Cache this geometry
        cache[cacheKey] = {"primitive": primitive, "promise": geometryPromise};

        pending.add(geometryPromise);
      }
    }

    return pending;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/blob/master/specification/2.0/README.md#meshes
  /// @param {number} meshIndex
  /// @return {Promise<Group|Mesh|SkinnedMesh>}
  loadMesh(meshIndex) async {
    var parser = this;
    var json = this.json;
    var extensions = this.extensions;

    Map<String, dynamic> meshDef = json["meshes"][meshIndex];
    var primitives = meshDef["primitives"];

    List<Future> pending = [];

    for (var i = 0, il = primitives.length; i < il; i++) {
      var material = primitives[i]["material"] == null
          ? createDefaultMaterial(cache)
          : await getDependency('material', primitives[i]["material"]);

      pending.add(Future.sync(() => material));
    }

    pending.add(parser.loadGeometries(primitives));

    final results = await Future.wait(pending);

    var materials = slice(results, 0, results.length - 1);
    var geometries = results[results.length - 1];

    var meshes = [];

    for (var i = 0, il = geometries.length; i < il; i++) {
      var geometry = geometries[i];
      Map<String, dynamic> primitive = primitives[i];

      // 1. create Mesh

      var mesh;

      var material = materials[i];

      if (primitive["mode"] == webGlConstants["TRIANGLES"] ||
          primitive["mode"] == webGlConstants["TRIANGLE_STRIP"] ||
          primitive["mode"] == webGlConstants["TRIANGLE_FAN"] ||
          primitive["mode"] == null) {
        // .isSkinnedMesh isn't in glTF spec. See ._markDefs()
        mesh = meshDef["isSkinnedMesh"] == true ? SkinnedMesh(geometry, material) : Mesh(geometry, material);

        if (mesh is SkinnedMesh && !mesh.geometry!.attributes["skinWeight"].normalized) {
          // we normalize floating point skin weight array to fix malformed assets (see #15319)
          // it's important to skip this for non-float32 data since normalizeSkinWeights assumes non-normalized inputs
          mesh.normalizeSkinWeights();
        }

        if (primitive["mode"] == webGlConstants["TRIANGLE_STRIP"]) {
          mesh.geometry = toTrianglesDrawMode(mesh.geometry, TriangleStripDrawMode);
        } else if (primitive["mode"] == webGlConstants["TRIANGLE_FAN"]) {
          mesh.geometry = toTrianglesDrawMode(mesh.geometry, TriangleFanDrawMode);
        }
      } else if (primitive["mode"] == webGlConstants["LINES"]) {
        mesh = LineSegments(geometry, material);
      } else if (primitive["mode"] == webGlConstants["LINE_STRIP"]) {
        mesh = Line(geometry, material);
      } else if (primitive["mode"] == webGlConstants["LINE_LOOP"]) {
        mesh = LineLoop(geometry, material);
      } else if (primitive["mode"] == webGlConstants["POINTS"]) {
        mesh = Points(geometry, material);
      } else {
        throw ('THREE.GLTFLoader: Primitive mode unsupported: ${primitive["mode"]}');
      }

      if (mesh.geometry.morphAttributes.keys.length > 0) {
        updateMorphTargets(mesh, meshDef);
      }

      mesh.name = parser.createUniqueName(meshDef["name"] ?? ('mesh_$meshIndex'));

      assignExtrasToUserData(mesh, meshDef);

      if (primitive["extensions"] != null) addUnknownExtensionsToUserData(extensions, mesh, primitive);

      parser.assignFinalMaterial(mesh);

      meshes.add(mesh);
    }

    if (meshes.length == 1) {
      return meshes[0];
    }

    var group = Group();

    for (var i = 0, il = meshes.length; i < il; i++) {
      group.add(meshes[i]);
    }

    return group;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#cameras
  /// @param {number} cameraIndex
  /// @return {Promise<THREE.Camera>}
  loadCamera(cameraIndex) {
    var camera;
    Map<String, dynamic> cameraDef = json["cameras"][cameraIndex];
    var params = cameraDef[cameraDef["type"]];

    if (params == null) {
      print('THREE.GLTFLoader: Missing camera parameters.');
      return;
    }

    if (cameraDef["type"] == 'perspective') {
      camera = PerspectiveCamera(
          MathUtils.radToDeg(params["yfov"]), params["aspectRatio"] ?? 1, params["znear"] ?? 1, params["zfar"] ?? 2e6);
    } else if (cameraDef["type"] == 'orthographic') {
      camera = OrthographicCamera(
          -params["xmag"], params["xmag"], params["ymag"], -params["ymag"], params["znear"], params["zfar"]);
    }

    if (cameraDef["name"] != null) camera.name = createUniqueName(cameraDef["name"]);

    assignExtrasToUserData(camera, cameraDef);

    return camera;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#skins
  /// @param {number} skinIndex
  /// @return {Promise<Object>}
  loadSkin(skinIndex) async {
    var skinDef = json["skins"][skinIndex];

    var skinEntry = {"joints": skinDef["joints"]};

    if (skinDef["inverseBindMatrices"] == null) {
      return skinEntry;
    }

    var accessor = await getDependency('accessor', skinDef["inverseBindMatrices"]);

    skinEntry["inverseBindMatrices"] = accessor;
    return skinEntry;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#animations
  /// @param {number} animationIndex
  /// @return {Promise<AnimationClip>}
  loadAnimation(animationIndex) async {
    var json = this.json;

    Map<String, dynamic> animationDef = json["animations"][animationIndex];

    List<Future> pendingNodes = [];
    List<Future> pendingInputAccessors = [];
    List<Future> pendingOutputAccessors = [];
    List<Future> pendingSamplers = [];
    List<Future> pendingTargets = [];

    for (var i = 0, il = animationDef["channels"].length; i < il; i++) {
      Map<String, dynamic> channel = animationDef["channels"][i];
      Map<String, dynamic> sampler = animationDef["samplers"][channel["sampler"]];
      Map<String, dynamic> target = channel["target"];
      var name = target["node"] ?? target["id"]; // NOTE: target.id is deprecated.
      var input = animationDef["parameters"] != null ? animationDef["parameters"][sampler["input"]] : sampler["input"];
      var output =
          animationDef["parameters"] != null ? animationDef["parameters"][sampler["output"]] : sampler["output"];

      pendingNodes.add(getDependency('node', name));
      pendingInputAccessors.add(getDependency('accessor', input));
      pendingOutputAccessors.add(getDependency('accessor', output));
      pendingSamplers.add(Future.sync(() => sampler));
      pendingTargets.add(Future.sync(() => target));
    }

    final dependencies = await Future.wait([
      Future.wait(pendingNodes),
      Future.wait(pendingInputAccessors),
      Future.wait(pendingOutputAccessors),
      Future.wait(pendingSamplers),
      Future.wait(pendingTargets)
    ]);

    var nodes = dependencies[0];
    var inputAccessors = dependencies[1];
    var outputAccessors = dependencies[2];
    var samplers = dependencies[3];
    var targets = dependencies[4];

    List<KeyframeTrack> tracks = [];

    for (var i = 0, il = nodes.length; i < il; i++) {
      var node = nodes[i];
      var inputAccessor = inputAccessors[i];

      var outputAccessor = outputAccessors[i];
      Map<String, dynamic> sampler = samplers[i];
      Map<String, dynamic> target = targets[i];

      if (node == null) continue;

      node.updateMatrix();
      node.matrixAutoUpdate = true;

      var typedKeyframeTrack = TypedKeyframeTrack(PathProperties.getValue(target["path"]));

      var targetName = node.name ?? node.uuid;

      var interpolation =
          sampler["interpolation"] != null ? gltfInterpolation[sampler["interpolation"]] : InterpolateLinear;

      var targetNames = [];

      if (PathProperties.getValue(target["path"]) == PathProperties.weights) {
        // Node may be a Group (glTF mesh with several primitives) or a Mesh.
        node.traverse((object) {
          if (object.morphTargetInfluences != null) {
            targetNames.add(object.name ?? object.uuid);
          }
        });
      } else {
        targetNames.add(targetName);
      }

      var outputArray = outputAccessor.array;

      if (outputAccessor.normalized) {
        var scale = getNormalizedComponentScale(outputArray.runtimeType);

        var scaled = Float32List(outputArray.length);

        for (var j = 0, jl = outputArray.length; j < jl; j++) {
          scaled[j] = outputArray[j] * scale;
        }

        outputArray = scaled;
      }

      for (var j = 0, jl = targetNames.length; j < jl; j++) {
        var track = typedKeyframeTrack.createTrack(
          targetNames[j] + '.' + PathProperties.getValue(target["path"]),
          inputAccessor.array,
          outputArray,
          interpolation,
        );

        // Override interpolation with custom factory method.
        if (sampler["interpolation"] == 'CUBICSPLINE') {
          track.createInterpolant = (result) {
            // A CUBICSPLINE keyframe in glTF has three output values for each input value,
            // representing inTangent, splineVertex, and outTangent. As a result, track.getValueSize()
            // must be divided by three to get the interpolant's sampleSize argument.
            return GLTFCubicSplineInterpolant(track.times, track.values, track.getValueSize() / 3, result);
          };

          // Mark as CUBICSPLINE. `track.getInterpolation()` doesn't support custom interpolants.
          // track.createInterpolant.isInterpolantFactoryMethodGLTFCubicSpline = true;
          // TODO
          print(
              "GLTFParser.loadAnimation isInterpolantFactoryMethodGLTFCubicSpline TODO ?? how to handle this case ??? ");
        }

        tracks.add(track);
      }
    }

    var name = animationDef["name"] ?? 'animation_$animationIndex';

    return AnimationClip(name, -1, tracks);
  }

  createNodeMesh(nodeIndex) async {
    var json = this.json;
    var parser = this;
    Map<String, dynamic> nodeDef = json["nodes"][nodeIndex];

    if (nodeDef["mesh"] == null) return null;

    var mesh = await parser.getDependency('mesh', nodeDef["mesh"]);

    var node = parser._getNodeRef(parser.meshCache, nodeDef["mesh"], mesh);

    // if weights are provided on the node, override weights on the mesh.
    if (nodeDef["weights"] != null) {
      node.traverse((o) {
        if (!o.isMesh) return;

        for (var i = 0, il = nodeDef["weights"].length; i < il; i++) {
          o.morphTargetInfluences[i] = nodeDef["weights"][i];
        }
      });
    }

    return node;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#nodes-and-hierarchy
  /// @param {number} nodeIndex
  /// @return {Promise<Object3D>}
  loadNode(nodeIndex) async {
    var json = this.json;
    var extensions = this.extensions;
    var parser = this;

    Map<String, dynamic> nodeDef = json["nodes"][nodeIndex];

    // reserve node's name before its dependencies, so the root has the intended name.
    var nodeName = nodeDef["name"] != null ? parser.createUniqueName(nodeDef["name"]) : '';

    var pending = [];

    var meshPromise = await parser._invokeOne((ext) {
      return ext.createNodeMesh != null ? ext.createNodeMesh(nodeIndex) : null;
    });

    if (meshPromise != null) {
      pending.add(meshPromise);
    }
    // if ( nodeDef["mesh"] != null ) {
    //   var mesh = await parser.getDependency( 'mesh', nodeDef["mesh"] );
    //   var node = await parser._getNodeRef( parser.meshCache, nodeDef["mesh"], mesh );
    //   // if weights are provided on the node, override weights on the mesh.
    //   if ( nodeDef["weights"] != null ) {
    //     node.traverse( ( o ) {
    //       if ( ! o.isMesh ) return;
    //       for ( var i = 0, il = nodeDef["weights"].length; i < il; i ++ ) {
    //         o.morphTargetInfluences[ i ] = nodeDef["weights"][ i ];
    //       }
    //     } );
    //   }
    //   pending.add(node);
    // }

    if (nodeDef["camera"] != null) {
      var camera = await parser.getDependency('camera', nodeDef["camera"]);

      pending.add(await parser._getNodeRef(parser.cameraCache, nodeDef["camera"], camera));
    }

    // parser._invokeAll( ( ext ) async {
    //   return ext.createNodeAttachment != null ? await ext.createNodeAttachment( nodeIndex ) : null;
    // } ).forEach( ( promise ) {
    //   pending.add( promise );
    // } );

    List results = await parser._invokeAll((ext) async {
      return ext.createNodeAttachment != null ? await ext.createNodeAttachment(nodeIndex) : null;
    });

    var objects = [];

    for (var element in pending) {
      objects.add(element);
    }

    for (var element in results) {
      objects.add(element);
    }

    var node;

    // .isBone isn't in glTF spec. See ._markDefs
    if (nodeDef["isBone"] == true) {
      node = Bone();
    } else if (objects.length > 1) {
      node = Group();
    } else if (objects.length == 1) {
      node = objects[0];
    } else {
      node = Object3D();
    }

    if (objects.isEmpty || node != objects[0]) {
      for (var i = 0, il = objects.length; i < il; i++) {
        node.add(objects[i]);
      }
    }

    if (nodeDef["name"] != null) {
      node.userData["name"] = nodeDef["name"];
      node.name = nodeName;
    }

    assignExtrasToUserData(node, nodeDef);

    if (nodeDef["extensions"] != null) addUnknownExtensionsToUserData(extensions, node, nodeDef);

    if (nodeDef["matrix"] != null) {
      var matrix = Matrix4();
      matrix.fromArray(List<num>.from(nodeDef["matrix"]));
      node.applyMatrix4(matrix);
    } else {
      if (nodeDef["translation"] != null) {
        node.position.fromArray(List<num>.from(nodeDef["translation"]));
      }

      if (nodeDef["rotation"] != null) {
        node.quaternion.fromArray(List<num>.from(nodeDef["rotation"]));
      }

      if (nodeDef["scale"] != null) {
        node.scale.fromArray(List<num>.from(nodeDef["scale"]));
      }
    }

    parser.associations[node] = {"type": 'nodes', "index": nodeIndex};

    return node;
  }

  /// Specification: https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#scenes
  /// @param {number} sceneIndex
  /// @return {Promise<Group>}

  buildNodeHierarchy(nodeId, parentObject, json, parser) async {
    Map<String, dynamic> nodeDef = json["nodes"][nodeId];

    var node = await parser.getDependency('node', nodeId);

    if (nodeDef["skin"] != null) {
      // build skeleton here as well

      var skinEntry;

      var skin = await parser.getDependency('skin', nodeDef["skin"]);
      skinEntry = skin;

      var jointNodes = [];

      for (var i = 0, il = skinEntry["joints"].length; i < il; i++) {
        var node = await parser.getDependency('node', skinEntry["joints"][i]);

        jointNodes.add(node);
      }

      node.traverse((mesh) {
        if (mesh is SkinnedMesh) {
          List<Bone> bones = [];
          List<Matrix4> boneInverses = [];

          for (var j = 0, jl = jointNodes.length; j < jl; j++) {
            var jointNode = jointNodes[j];

            if (jointNode != null) {
              bones.add(jointNode);

              var mat = Matrix4();

              if (skinEntry["inverseBindMatrices"] != null) {
                mat.fromArray(skinEntry["inverseBindMatrices"].array, j * 16);
              }

              boneInverses.add(mat);
            } else {
              print('THREE.GLTFLoader: Joint "%s" could not be found. ${skinEntry["joints"][j]}');
            }
          }

          mesh.bind(Skeleton(bones, boneInverses), mesh.matrixWorld);
        }
      });
    }

    // build node hierachy

    parentObject.add(node);

    if (nodeDef["children"] != null) {
      var children = nodeDef["children"];

      for (var i = 0, il = children.length; i < il; i++) {
        var child = children[i];
        await buildNodeHierarchy(child, node, json, parser);
      }
    }
  }

  loadScene(sceneIndex) async {
    var json = this.json;
    var extensions = this.extensions;
    Map<String, dynamic> sceneDef = this.json["scenes"][sceneIndex];
    var parser = this;

    // Loader returns Group, not Scene.
    // See: https://github.com/mrdoob/three.js/issues/18342#issuecomment-578981172
    var scene = Group();
    if (sceneDef["name"] != null) scene.name = parser.createUniqueName(sceneDef["name"]);

    assignExtrasToUserData(scene, sceneDef);

    if (sceneDef["extensions"] != null) addUnknownExtensionsToUserData(extensions, scene, sceneDef);

    var nodeIds = sceneDef["nodes"] ?? [];

    for (var i = 0, il = nodeIds.length; i < il; i++) {
      await buildNodeHierarchy(nodeIds[i], scene, json, parser);
    }

    return scene;
  }
}
//class GLTFParser end...

class TypedKeyframeTrack {
  late String path;

  TypedKeyframeTrack(this.path);

  createTrack(v0, v1, v2, v3) {
    switch (path) {
      case PathProperties.weights:
        return NumberKeyframeTrack(v0, v1, v2, v3);

      case PathProperties.rotation:
        return QuaternionKeyframeTrack(v0, v1, v2, v3);

      case PathProperties.position:
      case PathProperties.scale:
      default:
        return VectorKeyframeTrack(v0, v1, v2, v3);
    }
  }
}
