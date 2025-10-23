import 'package:three_dart/three_dart.dart';

/// A Track of Boolean keyframe values.

class BooleanKeyframeTrack extends KeyframeTrack {
  // Note: Actually this track could have a optimized / compressed
  // representation of a single value and a custom interpolant that
  // computes "firstValue ^ isOdd( index )".

  BooleanKeyframeTrack(name, times, values, interpolation) : super(name, times, values, null) {
    valueTypeName = 'bool';
    defaultInterpolation = InterpolateDiscrete;
    valueBufferType = "Array";
  }

  @override
  Interpolant? interpolantFactoryMethodLinear(result) {
    return null;
  }

  @override
  Interpolant? interpolantFactoryMethodSmooth(result) {
    return null;
  }
}
