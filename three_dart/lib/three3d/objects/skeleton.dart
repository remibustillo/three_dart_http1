import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three3d/constants.dart';
import 'package:three_dart/three3d/math/index.dart';
import 'package:three_dart/three3d/objects/bone.dart';
import 'package:three_dart/three3d/textures/data_texture.dart';

var _offsetMatrix = Matrix4();

class Skeleton {
  String uuid = MathUtils.generateUUID();
  late List<Bone> bones;
  late List<Matrix4> boneInverses;
  late Float32Array boneMatrices;
  DataTexture? boneTexture;
  late int boneTextureSize;
  num frame = -1;

  Skeleton([List<Bone> bones = const [], List<Matrix4>? boneInverses]) {
    this.bones = bones.sublist(0);
    this.boneInverses = boneInverses ?? [];

    init();
  }

  void init() {
    var bones = this.bones;
    var boneInverses = this.boneInverses;

    // layout (1 matrix = 4 pixels)
    //      RGBA RGBA RGBA RGBA (=> column1, column2, column3, column4)
    //  with  8x8  pixel texture max   16 bones * 4 pixels =  (8 * 8)
    //       16x16 pixel texture max   64 bones * 4 pixels = (16 * 16)
    //       32x32 pixel texture max  256 bones * 4 pixels = (32 * 32)
    //       64x64 pixel texture max 1024 bones * 4 pixels = (64 * 64)

    double s = Math.sqrt(bones.length * 4); // 4 pixels needed for 1 matrix
    s = MathUtils.ceilPowerOfTwo(s).toDouble();
    s = Math.max(s, 4);

    int size = s.toInt();

    boneTextureSize = size;

    boneMatrices = Float32Array(size * size * 4);

    // calculate inverse bone matrices if necessary

    if (boneInverses.isEmpty) {
      calculateInverses();
    } else {
      // handle special case

      if (bones.length != boneInverses.length) {
        print('three.Skeleton: Number of inverse bone matrices does not match amount of bones.');

        this.boneInverses = [];

        for (var i = 0, il = this.bones.length; i < il; i++) {
          this.boneInverses.add(Matrix4());
        }
      }
    }
  }

  void calculateInverses() {
    boneInverses.length = 0;
    boneInverses.clear();

    for (var i = 0, il = bones.length; i < il; i++) {
      var inverse = Matrix4();

      inverse.copy(bones[i].matrixWorld).invert();
      boneInverses.add(inverse);
    }
  }

  void pose() {
    // recover the bind-time world matrices

    for (var i = 0, il = bones.length; i < il; i++) {
      var bone = bones[i];

      bone.matrixWorld.copy(boneInverses[i]).invert();
    }

    // compute the local matrices, positions, rotations and scales

    for (var i = 0, il = bones.length; i < il; i++) {
      var bone = bones[i];

      if (bone.parent != null && bone.parent is Bone) {
        bone.matrix.copy(bone.parent!.matrixWorld).invert();
        bone.matrix.multiply(bone.matrixWorld);
      } else {
        bone.matrix.copy(bone.matrixWorld);
      }

      bone.matrix.decompose(bone.position, bone.quaternion, bone.scale);
    }
  }

  void update() {
    var bones = this.bones;
    var boneInverses = this.boneInverses;
    var boneMatrices = this.boneMatrices;
    var boneTexture = this.boneTexture;

    // flatten bone matrices to array
    int il = bones.length;
    for (var i = 0; i < il; i++) {
      // compute the offset between the current and the original transform

      var matrix = bones[i].matrixWorld;

      _offsetMatrix.multiplyMatrices(matrix, boneInverses[i]);
      _offsetMatrix.toArray(boneMatrices, i * 16);
    }

    if (boneTexture != null) {
      boneTexture.needsUpdate = true;
    }
  }

  Skeleton clone() {
    return Skeleton(bones, boneInverses);
  }

  Skeleton computeBoneTexture() {
    boneTexture = DataTexture(boneMatrices, boneTextureSize, boneTextureSize, RGBAFormat, FloatType);

    boneTexture!.name = "DataTexture from Skeleton.computeBoneTexture";
    boneTexture!.needsUpdate = true;

    // Android Float Texture need NearestFilter
    boneTexture!.magFilter = NearestFilter;
    boneTexture!.minFilter = NearestFilter;

    return this;
  }

  Bone? getBoneByName(name) {
    for (var i = 0, il = bones.length; i < il; i++) {
      var bone = bones[i];

      if (bone.name == name) {
        return bone;
      }
    }

    return null;
  }

  void dispose() {
    if (boneTexture != null) {
      boneTexture!.dispose();

      boneTexture = null;
    }
  }

  fromJSON(json, bones) {
    uuid = json.uuid;

    for (var i = 0, l = json.bones.length; i < l; i++) {
      var uuid = json.bones[i];
      var bone = bones[uuid];

      if (bone == null) {
        print('three.Skeleton: No bone found with UUID: $uuid');
        bone = Bone();
      }

      this.bones.add(bone);
      boneInverses.add(Matrix4().fromArray(json.boneInverses[i]));
    }

    init();

    return this;
  }

  Map<String, dynamic> toJSON() {
    Map<String, dynamic> data = {
      "metadata": {"version": 4.5, "type": 'Skeleton', "generator": 'Skeleton.toJSON'},
      "bones": [],
      "boneInverses": []
    };

    data["uuid"] = uuid;

    var bones = this.bones;
    var boneInverses = this.boneInverses;

    for (var i = 0, l = bones.length; i < l; i++) {
      var bone = bones[i];
      data["bones"].add(bone.uuid);

      var boneInverse = boneInverses[i];
      data["boneInverses"].add(boneInverse.toJSON());
    }

    return data;
  }

  getValue(String name) {
    if (name == "boneMatrices") {
      return boneMatrices;
    } else {
      throw ("Skeleton getValue name: $name is not support  ");
    }
  }
}
