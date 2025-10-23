import 'package:three_dart/three3d/materials/material.dart';
import 'package:three_dart/three3d/math/vector3.dart';

class MeshDistanceMaterial extends Material {
  late Vector3 referencePosition;
  late num nearDistance;
  late num farDistance;

  MeshDistanceMaterial(Map<String, dynamic>? parameters) : super() {
    type = 'MeshDistanceMaterial';

    referencePosition = Vector3.init();
    nearDistance = 1;
    farDistance = 1000;

    map = null;

    alphaMap = null;

    displacementMap = null;
    displacementScale = 1;
    displacementBias = 0;

    setValues(parameters);
  }

  @override
  MeshDistanceMaterial copy(Material source) {
    super.copy(source);

    if (source is MeshDistanceMaterial) {
      referencePosition.copy(source.referencePosition);
      nearDistance = source.nearDistance;
      farDistance = source.farDistance;
    }

    map = source.map;

    alphaMap = source.alphaMap;

    displacementMap = source.displacementMap;
    displacementScale = source.displacementScale;
    displacementBias = source.displacementBias;

    return this;
  }
}
