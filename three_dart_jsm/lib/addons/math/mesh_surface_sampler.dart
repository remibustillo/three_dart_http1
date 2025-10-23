import 'package:flutter/foundation.dart';

import 'package:three_dart/three_dart.dart' as three;
import '../../extra/console.dart';

/// Utility class for sampling weighted random points on the surface of a mesh.
///
/// Building the sampler is a one-time O(n) operation. Once built, any number of
/// random samples may be selected in O(logn) time. Memory usage is O(n).
///
/// References:
/// - http://www.joesfer.com/?p=84
/// - https://stackoverflow.com/a/4322940/1314762

var _face = three.Triangle();

var _color = three.Vector3();

class MeshSurfaceSampler {
  late three.BufferGeometry geometry;

  late three.Float32BufferAttribute positionAttribute;
  late three.Float32BufferAttribute colorAttribute;
  three.Float32BufferAttribute? weightAttribute;
  Float32List? distribution;
  late Function randomFunction;

  MeshSurfaceSampler(mesh) {
    var geometry = mesh.geometry;

    if (!geometry.isBufferGeometry || geometry.attributes.position.itemSize != 3) {
      throw ('THREE.MeshSurfaceSampler: Requires BufferGeometry triangle mesh.');
    }

    if (geometry.index) {
      console.warn('THREE.MeshSurfaceSampler: Converting geometry to non-indexed BufferGeometry.');
      geometry = geometry.toNonIndexed();
    }

    this.geometry = geometry;
    randomFunction = three.Math.random;
    positionAttribute = this.geometry.getAttribute('position');
    colorAttribute = this.geometry.getAttribute('color');
    weightAttribute = null;
    distribution = null;
  }

  setWeightAttribute(name) {
    weightAttribute = name ? geometry.getAttribute(name) : null;
    return this;
  }

  build() {
    var positionAttribute = this.positionAttribute;
    var weightAttribute = this.weightAttribute;
    var faceWeights = Float32List(positionAttribute.count ~/ 3); // Accumulate weights for each mesh face.

    for (int i = 0; i < positionAttribute.count; i += 3) {
      num faceWeight = 1.0;

      if (weightAttribute != null) {
        faceWeight = weightAttribute.getX(i)! + weightAttribute.getX(i + 1)! + weightAttribute.getX(i + 2)!;
      }

      if (i < positionAttribute.count) {
        _face.a.fromBufferAttribute(positionAttribute, i);
      }

      if (i + 1 < positionAttribute.count) {
        _face.b.fromBufferAttribute(positionAttribute, i + 1);
      }

      if (i + 2 < positionAttribute.count) {
        _face.c.fromBufferAttribute(positionAttribute, i + 2);
      }

      faceWeight *= _face.getArea();
      faceWeights[i ~/ 3] = faceWeight.toDouble();
    } // Store cumulative total face weights in an array, where weight index
    // corresponds to face index.

    distribution = Float32List(positionAttribute.count ~/ 3);
    num cumulativeTotal = 0;

    for (var i = 0; i < faceWeights.length; i++) {
      cumulativeTotal += faceWeights[i];
      distribution![i] = cumulativeTotal.toDouble();
    }

    return this;
  }

  setRandomGenerator(randomFunction) {
    this.randomFunction = randomFunction;
    return this;
  }

  sample(targetPosition, targetNormal, targetColor) {
    var cumulativeTotal = distribution![distribution!.length - 1];
    var faceIndex = binarySearch(randomFunction() * cumulativeTotal);
    return sampleFace(faceIndex, targetPosition, targetNormal, targetColor);
  }

  binarySearch(x) {
    var dist = distribution;
    var start = 0;
    var end = dist!.length - 1;
    var index = -1;

    while (start <= end) {
      var mid = three.Math.ceil((start + end) / 2);

      if (mid == 0 || dist[mid - 1] <= x && dist[mid] > x) {
        index = mid;
        break;
      } else if (x < dist[mid]) {
        end = mid - 1;
      } else {
        start = mid + 1;
      }
    }

    return index;
  }

  sampleFace(faceIndex, targetPosition, targetNormal, targetColor) {
    var u = randomFunction();
    var v = randomFunction();

    if (u + v > 1) {
      u = 1 - u;
      v = 1 - v;
    }

    _face.a.fromBufferAttribute(positionAttribute, faceIndex * 3);

    _face.b.fromBufferAttribute(positionAttribute, faceIndex * 3 + 1);

    _face.c.fromBufferAttribute(positionAttribute, faceIndex * 3 + 2);

    targetPosition
        .set(0, 0, 0)
        .addScaledVector(_face.a, u)
        .addScaledVector(_face.b, v)
        .addScaledVector(_face.c, 1 - (u + v));

    if (targetNormal != undefined) {
      _face.getNormal(targetNormal);
    }

    if (targetColor != undefined && colorAttribute != undefined) {
      _face.a.fromBufferAttribute(colorAttribute, faceIndex * 3);

      _face.b.fromBufferAttribute(colorAttribute, faceIndex * 3 + 1);

      _face.c.fromBufferAttribute(colorAttribute, faceIndex * 3 + 2);

      _color.set(0, 0, 0).addScaledVector(_face.a, u).addScaledVector(_face.b, v).addScaledVector(_face.c, 1 - (u + v));

      targetColor.r = _color.x;
      targetColor.g = _color.y;
      targetColor.b = _color.z;
    }

    return this;
  }
}
