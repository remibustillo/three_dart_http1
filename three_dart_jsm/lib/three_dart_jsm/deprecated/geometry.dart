import 'index.dart';
import 'package:three_dart/three_dart.dart' as three;

int _geometryId = 0; // Geometry uses even numbers as Id
var _geometrym1 = three.Matrix4();
var _geometryobj = three.Object3D();
var _geometryoffset = three.Vector3.init();

class Geometry with three.EventDispatcher {
  int id = _geometryId += 2;
  String uuid = three.MathUtils.generateUUID();
  String name = '';
  String type = 'Geometry';
  List<three.Vector3> vertices = [];
  List<three.Color> colors = [];
  List<Face3> faces = [];
  List<List<List<three.Vector2>>?> faceVertexUvs = [[]];
  List<MorphTarget> morphTargets = [];
  List<MorphNormals> morphNormals = [];
  List<three.Vector4> skinWeights = [];
  List<three.Vector4> skinIndices = [];
  List<double> lineDistances = [];
  three.Box3? boundingBox;
  three.Sphere? boundingSphere;

  // update flags

  bool elementsNeedUpdate = false;
  bool verticesNeedUpdate = false;
  bool uvsNeedUpdate = false;
  bool normalsNeedUpdate = false;
  bool colorsNeedUpdate = false;
  bool lineDistancesNeedUpdate = false;
  bool groupsNeedUpdate = false;

  bool isGeometry = true;
  bool isBufferGeometry = false;

  DirectGeometry? directGeometry;

  Map<String, dynamic> parameters = {};

  Geometry();

  applyMatrix4(matrix) {
    var normalMatrix = three.Matrix3().getNormalMatrix(matrix);

    for (var i = 0, il = vertices.length; i < il; i++) {
      var vertex = vertices[i];
      vertex.applyMatrix4(matrix);
    }

    for (var i = 0, il = faces.length; i < il; i++) {
      var face = faces[i];
      face.normal.applyMatrix3(normalMatrix).normalize();

      for (var j = 0, jl = face.vertexNormals.length; j < jl; j++) {
        face.vertexNormals[j].applyMatrix3(normalMatrix).normalize();
      }
    }

    if (boundingBox != null) {
      computeBoundingBox();
    }

    if (boundingSphere != null) {
      computeBoundingSphere();
    }

    verticesNeedUpdate = true;
    normalsNeedUpdate = true;

    return this;
  }

  rotateX(angle) {
    // rotate geometry around world x-axis

    _geometrym1.makeRotationX(angle);

    applyMatrix4(_geometrym1);

    return this;
  }

  rotateY(angle) {
    // rotate geometry around world y-axis

    _geometrym1.makeRotationY(angle);

    applyMatrix4(_geometrym1);

    return this;
  }

  rotateZ(angle) {
    // rotate geometry around world z-axis

    _geometrym1.makeRotationZ(angle);

    applyMatrix4(_geometrym1);

    return this;
  }

  translate(x, y, z) {
    // translate geometry

    _geometrym1.makeTranslation(x, y, z);

    applyMatrix4(_geometrym1);

    return this;
  }

  scale(x, y, z) {
    // scale geometry

    _geometrym1.makeScale(x, y, z);

    applyMatrix4(_geometrym1);

    return this;
  }

  lookAt(three.Vector3 vector) {
    _geometryobj.lookAt(vector);

    _geometryobj.updateMatrix();

    applyMatrix4(_geometryobj.matrix);

    return this;
  }

  fromBufferGeometry(geometry) {
    var scope = this;

    var index = geometry.index;
    var attributes = geometry.attributes;

    if (attributes["position"] == null) {
      print('THREE.Geometry.fromBufferGeometry(): Position attribute required for conversion.');
      return this;
    }

    var position = attributes["position"];
    var normal = attributes["normal"];
    var color = attributes["color"];
    var uv = attributes["uv"];
    var uv2 = attributes["uv2"];

    if (uv2 != null) faceVertexUvs[1] = [];

    for (var i = 0; i < position.count; i++) {
      scope.vertices.add(three.Vector3.init().fromBufferAttribute(position, i));

      if (color != null) {
        scope.colors.add(three.Color(0, 0, 0).fromBufferAttribute(color, i));
      }
    }

    addFace(int a, int b, int c, materialIndex) {
      List<three.Color> vertexColors =
          (color == null) ? [] : [scope.colors[a].clone(), scope.colors[b].clone(), scope.colors[c].clone()];

      List<three.Vector3> vertexNormals = (normal == null)
          ? []
          : [
              three.Vector3.init().fromBufferAttribute(normal, a),
              three.Vector3.init().fromBufferAttribute(normal, b),
              three.Vector3.init().fromBufferAttribute(normal, c)
            ];

      var face = Face3(a, b, c, vertexNormals, vertexColors, materialIndex: materialIndex ?? 0);

      scope.faces.add(face);

      if (uv != null) {
        scope.faceVertexUvs[0]?.add([
          three.Vector2(null, null).fromBufferAttribute(uv, a),
          three.Vector2(null, null).fromBufferAttribute(uv, b),
          three.Vector2(null, null).fromBufferAttribute(uv, c)
        ]);
      }

      if (uv2 != null) {
        scope.faceVertexUvs[1]?.add([
          three.Vector2(null, null).fromBufferAttribute(uv2, a),
          three.Vector2(null, null).fromBufferAttribute(uv2, b),
          three.Vector2(null, null).fromBufferAttribute(uv2, c)
        ]);
      }
    }

    var groups = geometry.groups;

    if (groups.length > 0) {
      for (var i = 0; i < groups.length; i++) {
        var group = groups[i];

        int start = group["start"];
        int count = group["count"];

        for (int j = start, jl = start + count; j < jl; j += 3) {
          if (index != null) {
            addFace(
                index.getX(j).toInt(), index.getX(j + 1).toInt(), index.getX(j + 2).toInt(), group["materialIndex"]);
          } else {
            addFace(j, j + 1, j + 2, group["materialIndex"]);
          }
        }
      }
    } else {
      if (index != null) {
        for (var i = 0; i < index.count; i += 3) {
          addFace(index.getX(i), index.getX(i + 1), index.getX(i + 2), null);
        }
      } else {
        for (var i = 0; i < position.count; i += 3) {
          addFace(i, i + 1, i + 2, null);
        }
      }
    }

    computeFaceNormals();

    if (geometry.boundingBox != null) {
      boundingBox = geometry.boundingBox.clone();
    }

    if (geometry.boundingSphere != null) {
      boundingSphere = geometry.boundingSphere.clone();
    }

    return this;
  }

  center() {
    computeBoundingBox();

    boundingBox!.getCenter(_geometryoffset).negate();

    translate(_geometryoffset.x, _geometryoffset.y, _geometryoffset.z);

    return this;
  }

  normalize() {
    computeBoundingSphere();

    var center = boundingSphere!.center;
    var radius = boundingSphere!.radius;

    var s = (radius == 0 ? 1 : 1.0 / radius).toDouble();

    var matrix = three.Matrix4();
    matrix.set(s, 0, 0, -s * center.x, 0, s, 0, -s * center.y, 0, 0, s, -s * center.z, 0, 0, 0, 1);

    applyMatrix4(matrix);

    return this;
  }

  computeFaceNormals() {
    var cb = three.Vector3.init(), ab = three.Vector3.init();

    for (var f = 0, fl = faces.length; f < fl; f++) {
      var face = faces[f];

      var vA = vertices[face.a];
      var vB = vertices[face.b];
      var vC = vertices[face.c];

      cb.subVectors(vC, vB);
      ab.subVectors(vA, vB);
      cb.cross(ab);

      cb.normalize();

      face.normal.copy(cb);
    }
  }

  computeVertexNormals({bool areaWeighted = true}) {
    var vertices = List<three.Vector3>.filled(this.vertices.length, three.Vector3(0, 0, 0));

    for (var v = 0, vl = this.vertices.length; v < vl; v++) {
      vertices[v] = three.Vector3.init();
    }

    if (areaWeighted) {
      // vertex normals weighted by triangle areas
      // http://www.iquilezles.org/www/articles/normals/normals.htm

      var cb = three.Vector3.init(), ab = three.Vector3.init();

      for (var f = 0, fl = faces.length; f < fl; f++) {
        var face = faces[f];

        var vA = this.vertices[face.a];
        var vB = this.vertices[face.b];
        var vC = this.vertices[face.c];

        cb.subVectors(vC, vB);
        ab.subVectors(vA, vB);
        cb.cross(ab);

        vertices[face.a].add(cb);
        vertices[face.b].add(cb);
        vertices[face.c].add(cb);
      }
    } else {
      computeFaceNormals();

      for (var f = 0, fl = faces.length; f < fl; f++) {
        var face = faces[f];

        vertices[face.a].add(face.normal);
        vertices[face.b].add(face.normal);
        vertices[face.c].add(face.normal);
      }
    }

    for (var v = 0, vl = this.vertices.length; v < vl; v++) {
      vertices[v].normalize();
    }

    for (var f = 0, fl = faces.length; f < fl; f++) {
      var face = faces[f];

      var vertexNormals = face.vertexNormals;

      if (vertexNormals.length == 3) {
        vertexNormals[0].copy(vertices[face.a]);
        vertexNormals[1].copy(vertices[face.b]);
        vertexNormals[2].copy(vertices[face.c]);
      } else {
        vertexNormals[0] = vertices[face.a].clone();
        vertexNormals[1] = vertices[face.b].clone();
        vertexNormals[2] = vertices[face.c].clone();
      }
    }

    if (faces.isNotEmpty) {
      normalsNeedUpdate = true;
    }
  }

  computeFlatVertexNormals() {
    computeFaceNormals();

    for (var f = 0, fl = faces.length; f < fl; f++) {
      var face = faces[f];

      var vertexNormals = face.vertexNormals;

      if (vertexNormals.length == 3) {
        vertexNormals[0].copy(face.normal);
        vertexNormals[1].copy(face.normal);
        vertexNormals[2].copy(face.normal);
      } else {
        vertexNormals[0] = face.normal.clone();
        vertexNormals[1] = face.normal.clone();
        vertexNormals[2] = face.normal.clone();
      }
    }

    if (faces.isNotEmpty) {
      normalsNeedUpdate = true;
    }
  }

  // computeMorphNormals() {

  // 	// save original normals
  // 	// - create temp variables on first access
  // 	//   otherwise just copy (for faster repeated calls)

  // 	for ( var f = 0, fl = this.faces.length; f < fl; f ++ ) {

  // 		var face = this.faces[ f ];

  // 		if ( ! face.__originalFaceNormal ) {

  // 			face.__originalFaceNormal = face.normal.clone();

  // 		} else {

  // 			face.__originalFaceNormal.copy( face.normal );

  // 		}

  // 		if ( ! face.__originalVertexNormals ) face.__originalVertexNormals = [];

  // 		for ( var i = 0, il = face.vertexNormals.length; i < il; i ++ ) {

  // 			if ( ! face.__originalVertexNormals[ i ] ) {

  // 				face.__originalVertexNormals[ i ] = face.vertexNormals[ i ].clone();

  // 			} else {

  // 				face.__originalVertexNormals[ i ].copy( face.vertexNormals[ i ] );

  // 			}

  // 		}

  // 	}

  // 	// use temp geometry to compute face and vertex normals for each morph

  // 	var tmpGeo = new Geometry();
  // 	tmpGeo.faces = this.faces;

  // 	for ( var i = 0, il = this.morphTargets.length; i < il; i ++ ) {

  // 		// create on first access

  // 		if ( ! this.morphNormals[ i ] ) {

  // 			this.morphNormals[ i ] = {};
  // 			this.morphNormals[ i ].faceNormals = [];
  // 			this.morphNormals[ i ].vertexNormals = [];

  // 			var dstNormalsFace = this.morphNormals[ i ].faceNormals;
  // 			var dstNormalsVertex = this.morphNormals[ i ].vertexNormals;

  // 			for ( var f = 0, fl = this.faces.length; f < fl; f ++ ) {

  // 				var faceNormal = new Vector3();
  // 				var vertexNormals = { a: new Vector3(), b: new Vector3(), c: new Vector3() };

  // 				dstNormalsFace.push( faceNormal );
  // 				dstNormalsVertex.push( vertexNormals );

  // 			}

  // 		}

  // 		var morphNormals = this.morphNormals[ i ];

  // 		// set vertices to morph target

  // 		tmpGeo.vertices = this.morphTargets[ i ].vertices;

  // 		// compute morph normals

  // 		tmpGeo.computeFaceNormals();
  // 		tmpGeo.computeVertexNormals();

  // 		// store morph normals

  // 		for ( var f = 0, fl = this.faces.length; f < fl; f ++ ) {

  // 			var face = this.faces[ f ];

  // 			var faceNormal = morphNormals.faceNormals[ f ];
  // 			var vertexNormals = morphNormals.vertexNormals[ f ];

  // 			faceNormal.copy( face.normal );

  // 			vertexNormals.a.copy( face.vertexNormals[ 0 ] );
  // 			vertexNormals.b.copy( face.vertexNormals[ 1 ] );
  // 			vertexNormals.c.copy( face.vertexNormals[ 2 ] );

  // 		}

  // 	}

  // 	// restore original normals

  // 	for ( var f = 0, fl = this.faces.length; f < fl; f ++ ) {

  // 		var face = this.faces[ f ];

  // 		face.normal = face.__originalFaceNormal;
  // 		face.vertexNormals = face.__originalVertexNormals;

  // 	}

  // }

  computeBoundingBox() {
    boundingBox ??= three.Box3(null, null);

    boundingBox!.setFromPoints(vertices);
  }

  computeBoundingSphere() {
    boundingSphere ??= three.Sphere(null, null);

    boundingSphere!.setFromPoints(vertices, null);
  }

  merge(geometry, matrix, {int materialIndexOffset = 0}) {
    if (!(geometry && geometry.isGeometry)) {
      print('THREE.Geometry.merge(): geometry not an instance of THREE.Geometry. $geometry');
      return;
    }

    var normalMatrix;
    var vertexOffset = vertices.length,
        vertices1 = vertices,
        vertices2 = geometry.vertices,
        faces1 = faces,
        faces2 = geometry.faces,
        colors1 = colors,
        colors2 = geometry.colors;

    if (matrix != null) {
      normalMatrix = three.Matrix3().getNormalMatrix(matrix);
    }

    // vertices

    for (var i = 0, il = vertices2.length; i < il; i++) {
      var vertex = vertices2[i];

      var vertexCopy = vertex.clone();

      if (matrix != null) vertexCopy.applyMatrix4(matrix);

      vertices1.add(vertexCopy);
    }

    // colors

    for (var i = 0, il = colors2.length; i < il; i++) {
      colors1.add(colors2[i].clone());
    }

    // faces

    for (var i = 0, il = faces2.length; i < il; i++) {
      var face = faces2[i];
      var normal, color;
      var faceVertexNormals = face.vertexNormals, faceVertexColors = face.vertexColors;

      var faceCopy = Face3(face.a + vertexOffset, face.b + vertexOffset, face.c + vertexOffset, null, null);
      faceCopy.normal.copy(face.normal);

      if (normalMatrix != null) {
        faceCopy.normal.applyMatrix3(normalMatrix).normalize();
      }

      for (var j = 0, jl = faceVertexNormals.length; j < jl; j++) {
        normal = faceVertexNormals[j].clone();

        if (normalMatrix != null) {
          normal.applyMatrix3(normalMatrix).normalize();
        }

        faceCopy.vertexNormals.add(normal);
      }

      faceCopy.color.copy(face.color);

      for (var j = 0, jl = faceVertexColors.length; j < jl; j++) {
        color = faceVertexColors[j];
        faceCopy.vertexColors.add(color.clone());
      }

      faceCopy.materialIndex = face.materialIndex + materialIndexOffset;

      faces1.add(faceCopy);
    }

    // uvs

    for (var i = 0, il = geometry.faceVertexUvs.length; i < il; i++) {
      var faceVertexUvs2 = geometry.faceVertexUvs[i];

      if (faceVertexUvs[i] == null) faceVertexUvs[i] = [];

      for (var j = 0, jl = faceVertexUvs2.length; j < jl; j++) {
        var uvs2 = faceVertexUvs2[j];
        List<three.Vector2> uvsCopy = [];

        for (var k = 0, kl = uvs2.length; k < kl; k++) {
          uvsCopy.add(uvs2[k].clone());
        }

        faceVertexUvs[i]?.add(uvsCopy);
      }
    }
  }

  mergeMesh(mesh) {
    if (!(mesh && mesh.isMesh)) {
      print('THREE.Geometry.mergeMesh(): mesh not an instance of THREE.Mesh. $mesh');
      return;
    }

    if (mesh.matrixAutoUpdate) mesh.updateMatrix();

    merge(mesh.geometry, mesh.matrix);
  }

  /*
	 * Checks for duplicate vertices with hashmap.
	 * Duplicated vertices are removed
	 * and faces' vertices are updated.
	 */

  mergeVertices({int precisionPoints = 4}) {
    var verticesMap = {}; // Hashmap for looking up vertices by position coordinates (and making sure they are unique)
    List<three.Vector3> unique = [];
    var changes = List.filled(vertices.length, 0);

    var precision = three.Math.pow(10, precisionPoints);

    for (var i = 0, il = vertices.length; i < il; i++) {
      var v = vertices[i];
      var key =
          '${three.Math.round(v.x * precision)}_${three.Math.round(v.y * precision)}_${three.Math.round(v.z * precision)}';

      if (verticesMap[key] == null) {
        verticesMap[key] = i;
        unique.add(vertices[i]);
        changes[i] = unique.length - 1;
      } else {
        //console.log('Duplicate vertex found. ', i, ' could be using ', verticesMap[key]);
        changes[i] = changes[verticesMap[key]];
      }
    }

    // if faces are completely degenerate after merging vertices, we
    // have to remove them from the geometry.
    var faceIndicesToRemove = [];

    for (var i = 0, il = faces.length; i < il; i++) {
      var face = faces[i];

      face.a = changes[face.a];
      face.b = changes[face.b];
      face.c = changes[face.c];

      var indices = [face.a, face.b, face.c];

      // if any duplicate vertices are found in a Face3
      // we have to remove the face as nothing can be saved
      for (var n = 0; n < 3; n++) {
        if (indices[n] == indices[(n + 1) % 3]) {
          faceIndicesToRemove.add(i);
          break;
        }
      }
    }

    for (var i = faceIndicesToRemove.length - 1; i >= 0; i--) {
      var idx = faceIndicesToRemove[i];

      faces.sublist(idx, idx + 1);

      for (var j = 0, jl = faceVertexUvs.length; j < jl; j++) {
        faceVertexUvs[j]?.sublist(idx, idx + 1);
      }
    }

    // Use unique set of vertices

    var diff = vertices.length - unique.length;
    vertices = unique;
    return diff;
  }

  setFromPoints(points) {
    vertices = [];

    for (var i = 0, l = points.length; i < l; i++) {
      var point = points[i];
      vertices.add(three.Vector3(point.x, point.y, point.z ?? 0));
    }

    return this;
  }

  // sortFacesByMaterialIndex() {

  // 	var faces = this.faces;
  // 	var length = faces.length;

  // 	// tag faces

  // 	for ( var i = 0; i < length; i ++ ) {

  // 		faces[ i ]._id = i;

  // 	}

  // 	// sort faces

  // 	materialIndexSort( a, b ) {

  // 		return a.materialIndex - b.materialIndex;

  // 	}

  // 	faces.sort( (a,b) => materialIndexSort(a,b) );

  // 	// sort uvs

  // 	var uvs1 = this.faceVertexUvs[ 0 ];
  // 	var uvs2 = this.faceVertexUvs[ 1 ];

  // 	var newUvs1, newUvs2;

  // 	if ( uvs1 != null && uvs1.length == length ) newUvs1 = [];
  // 	if ( uvs2 != null && uvs2.length == length ) newUvs2 = [];

  // 	for ( var i = 0; i < length; i ++ ) {

  // 		var id = faces[ i ]._id;

  // 		if ( newUvs1 ) newUvs1.push( uvs1[ id ] );
  // 		if ( newUvs2 ) newUvs2.push( uvs2[ id ] );

  // 	}

  // 	if ( newUvs1 ) this.faceVertexUvs[ 0 ] = newUvs1;
  // 	if ( newUvs2 ) this.faceVertexUvs[ 1 ] = newUvs2;

  // }

  toJSON() {
    Map<String, dynamic> data = {
      "metadata": {"version": 4.5, "type": 'Geometry', "generator": 'Geometry.toJSON'}
    };

    // standard Geometry serialization

    data["uuid"] = uuid;
    data["type"] = type;
    if (name != '') data["name"] = name;

    print(" Geometry tojson todo ");

    // if ( this.parameters != null ) {

    // 	var parameters = this.parameters;

    // 	for ( var key in parameters ) {

    // 		if ( parameters[ key ] != null ) data[ key ] = parameters[ key ];

    // 	}

    // 	return data;

    // }

    var vertices = [];

    for (var i = 0; i < this.vertices.length; i++) {
      var vertex = this.vertices[i];
      vertices.addAll([vertex.x, vertex.y, vertex.z]);
    }

    var faces = [];
    var normals = [];
    var normalsHash = {};
    var colors = [];
    var colorsHash = {};
    var uvs = [];
    var uvsHash = {};

    setBit(value, position, enabled) {
      return enabled ? value | (1 << position) : value & (~(1 << position));
    }

    getNormalIndex(normal) {
      var hash = normal.x.toString() + normal.y.toString() + normal.z.toString();

      if (normalsHash[hash] != null) {
        return normalsHash[hash];
      }

      normalsHash[hash] = normals.length / 3;
      normals.addAll([normal.x, normal.y, normal.z]);

      return normalsHash[hash];
    }

    getColorIndex(color) {
      var hash = color.r.toString() + color.g.toString() + color.b.toString();

      if (colorsHash[hash] != null) {
        return colorsHash[hash];
      }

      colorsHash[hash] = colors.length;
      colors.add(color.getHex());

      return colorsHash[hash];
    }

    getUvIndex(uv) {
      var hash = uv.x.toString() + uv.y.toString();

      if (uvsHash[hash] != null) {
        return uvsHash[hash];
      }

      uvsHash[hash] = uvs.length / 2;
      uvs.addAll([uv.x, uv.y]);

      return uvsHash[hash];
    }

    for (var i = 0; i < this.faces.length; i++) {
      var face = this.faces[i];

      var hasMaterial = true;
      var hasFaceUv = false; // deprecated
      var hasFaceVertexUv = faceVertexUvs[0]?[i] != null;
      var hasFaceNormal = face.normal.length() > 0;
      var hasFaceVertexNormal = face.vertexNormals.isNotEmpty;
      var hasFaceColor = face.color.r != 1 || face.color.g != 1 || face.color.b != 1;
      var hasFaceVertexColor = face.vertexColors.isNotEmpty;

      var faceType = 0;

      faceType = setBit(faceType, 0, 0); // isQuad
      faceType = setBit(faceType, 1, hasMaterial);
      faceType = setBit(faceType, 2, hasFaceUv);
      faceType = setBit(faceType, 3, hasFaceVertexUv);
      faceType = setBit(faceType, 4, hasFaceNormal);
      faceType = setBit(faceType, 5, hasFaceVertexNormal);
      faceType = setBit(faceType, 6, hasFaceColor);
      faceType = setBit(faceType, 7, hasFaceVertexColor);

      faces.add(faceType);
      faces.addAll([face.a, face.b, face.c]);
      faces.add(face.materialIndex);

      if (hasFaceVertexUv) {
        var faceVertexUvs = this.faceVertexUvs[0]![i];

        faces.addAll([getUvIndex(faceVertexUvs[0]), getUvIndex(faceVertexUvs[1]), getUvIndex(faceVertexUvs[2])]);
      }

      if (hasFaceNormal) {
        faces.add(getNormalIndex(face.normal));
      }

      if (hasFaceVertexNormal) {
        var vertexNormals = face.vertexNormals;

        faces.addAll(
            [getNormalIndex(vertexNormals[0]), getNormalIndex(vertexNormals[1]), getNormalIndex(vertexNormals[2])]);
      }

      if (hasFaceColor) {
        faces.add(getColorIndex(face.color));
      }

      if (hasFaceVertexColor) {
        var vertexColors = face.vertexColors;

        faces.addAll([getColorIndex(vertexColors[0]), getColorIndex(vertexColors[1]), getColorIndex(vertexColors[2])]);
      }
    }

    data["data"] = {};

    data["data"].vertices = vertices;
    data["data"].normals = normals;
    if (colors.isNotEmpty) data["data"].colors = colors;
    if (uvs.isNotEmpty) data["data"].uvs = [uvs]; // temporal backward compatibility
    data["data"].faces = faces;

    return data;
  }

  clone() {
    return Geometry().copy(this);
  }

  copy(source) {
    // reset

    this.vertices = [];
    this.colors = [];
    this.faces = [];
    faceVertexUvs = [[]];
    this.morphTargets = [];
    this.morphNormals = [];
    this.skinWeights = [];
    this.skinIndices = [];
    this.lineDistances = [];
    this.boundingBox = null;
    this.boundingSphere = null;

    // name

    name = source.name;

    // vertices

    var vertices = source.vertices;

    for (var i = 0, il = vertices.length; i < il; i++) {
      this.vertices.add(vertices[i].clone());
    }

    // colors

    var colors = source.colors;

    for (var i = 0, il = colors.length; i < il; i++) {
      this.colors.add(colors[i].clone());
    }

    // faces

    var faces = source.faces;

    for (var i = 0, il = faces.length; i < il; i++) {
      this.faces.add(faces[i].clone());
    }

    // face vertex uvs

    for (var i = 0, il = source.faceVertexUvs.length; i < il; i++) {
      var faceVertexUvs = source.faceVertexUvs[i];

      if (this.faceVertexUvs[i] == null) {
        this.faceVertexUvs[i] = [];
      }

      for (var j = 0, jl = faceVertexUvs.length; j < jl; j++) {
        List<three.Vector2> uvs = faceVertexUvs[j];
        List<three.Vector2> uvsCopy = [];

        for (var k = 0, kl = uvs.length; k < kl; k++) {
          var uv = uvs[k];

          uvsCopy.add(uv.clone());
        }

        this.faceVertexUvs[i]?.add(uvsCopy);
      }
    }

    // morph targets

    var morphTargets = source.morphTargets;

    for (var i = 0, il = morphTargets.length; i < il; i++) {
      var morphTarget = MorphTarget(null);
      morphTarget.name = morphTargets[i].name;

      // vertices

      if (morphTargets[i].vertices != null) {
        morphTarget.vertices = [];

        for (var j = 0, jl = morphTargets[i].vertices.length; j < jl; j++) {
          morphTarget.vertices.add(morphTargets[i].vertices[j].clone());
        }
      }

      // normals

      if (morphTargets[i].normals != null) {
        morphTarget.normals = [];

        for (var j = 0, jl = morphTargets[i].normals.length; j < jl; j++) {
          morphTarget.normals.add(morphTargets[i].normals[j].clone());
        }
      }

      this.morphTargets.add(morphTarget);
    }

    // morph normals

    var morphNormals = source.morphNormals;

    for (var i = 0, il = morphNormals.length; i < il; i++) {
      var morphNormal = MorphNormals();

      // vertex normals

      if (morphNormals[i].vertexNormals != null) {
        morphNormal.vertexNormals = [];

        for (var j = 0, jl = morphNormals[i].vertexNormals.length; j < jl; j++) {
          var srcVertexNormal = morphNormals[i].vertexNormals[j];

          Face3 destVertexNormal = Face3(0, 0, 0, null, null);

          destVertexNormal.a = srcVertexNormal.a.clone();
          destVertexNormal.b = srcVertexNormal.b.clone();
          destVertexNormal.c = srcVertexNormal.c.clone();

          morphNormal.vertexNormals.add(destVertexNormal);
        }
      }

      // face normals

      if (morphNormals[i].faceNormals != null) {
        morphNormal.faceNormals = [];

        for (var j = 0, jl = morphNormals[i].faceNormals.length; j < jl; j++) {
          morphNormal.faceNormals.add(morphNormals[i].faceNormals[j].clone());
        }
      }

      this.morphNormals.add(morphNormal);
    }

    // skin weights

    var skinWeights = source.skinWeights;

    for (var i = 0, il = skinWeights.length; i < il; i++) {
      this.skinWeights.add(skinWeights[i].clone());
    }

    // skin indices

    var skinIndices = source.skinIndices;

    for (var i = 0, il = skinIndices.length; i < il; i++) {
      this.skinIndices.add(skinIndices[i].clone());
    }

    // line distances

    var lineDistances = source.lineDistances;

    for (var i = 0, il = lineDistances.length; i < il; i++) {
      this.lineDistances.add(lineDistances[i]);
    }

    // bounding box

    var boundingBox = source.boundingBox;

    if (boundingBox != null) {
      this.boundingBox = boundingBox.clone();
    }

    // bounding sphere

    var boundingSphere = source.boundingSphere;

    if (boundingSphere != null) {
      this.boundingSphere = boundingSphere.clone();
    }

    // update flags

    elementsNeedUpdate = source.elementsNeedUpdate;
    verticesNeedUpdate = source.verticesNeedUpdate;
    uvsNeedUpdate = source.uvsNeedUpdate;
    normalsNeedUpdate = source.normalsNeedUpdate;
    colorsNeedUpdate = source.colorsNeedUpdate;
    lineDistancesNeedUpdate = source.lineDistancesNeedUpdate;
    groupsNeedUpdate = source.groupsNeedUpdate;

    return this;
  }

  dispose() {
    dispatchEvent(three.Event({"type": "dispose"}));
  }

  static createBufferGeometryFromObject(object) {
    var buffergeometry = three.BufferGeometry();

    var geometry = object.geometry;

    if (object.isPoints || object.isLine) {
      var positions = three.Float32BufferAttribute(geometry.vertices.length * 3, 3, false);
      var colors = three.Float32BufferAttribute(geometry.colors.length * 3, 3, false);

      buffergeometry.setAttribute('position', positions.copyVector3sArray(geometry.vertices));
      buffergeometry.setAttribute('color', colors.copyColorsArray(geometry.colors));

      if (geometry.lineDistances && geometry.lineDistances.length == geometry.vertices.length) {
        var lineDistances = three.Float32BufferAttribute(geometry.lineDistances.length, 1, false);

        buffergeometry.setAttribute('lineDistance', lineDistances.copyArray(geometry.lineDistances));
      }

      if (geometry.boundingSphere != null) {
        buffergeometry.boundingSphere = geometry.boundingSphere.clone();
      }

      if (geometry.boundingBox != null) {
        buffergeometry.boundingBox = geometry.boundingBox.clone();
      }
    } else if (object.isMesh) {
      buffergeometry = geometry.toBufferGeometry();
    }

    return buffergeometry;
  }
}

class MorphTarget {
  late String name;
  late List<three.Vector3> vertices;
  late List<three.Vector3> normals;

  MorphTarget(Map<String, dynamic>? json) {
    if (json != null) {
      if (json["name"] != null) name = json["name"];
      if (json["vertices"] != null) vertices = json["vertices"];
      if (json["normals"] != null) normals = json["normals"];
    }
  }
}

class MorphColor {
  late String name;
  late List<three.Color> colors;
}

class MorphNormals {
  late String name;
  late List<three.Vector3> normals;
  late List<Face3> vertexNormals;
  late List<three.Vector3> faceNormals;
}
