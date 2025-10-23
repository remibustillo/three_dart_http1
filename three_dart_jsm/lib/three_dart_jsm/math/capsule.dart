import 'package:three_dart/three_dart.dart';

class Capsule {
  Capsule([Vector3? start, Vector3? end, double? radius]) {
    this.start = start ?? Vector3(0, 0, 0);
    this.end = end ?? Vector3(0, 1, 0);
    this.radius = radius ?? 1;
  }

  final Vector3 _v1 = Vector3();
  final Vector3 _v2 = Vector3();
  final Vector3 _v3 = Vector3();

  double eps = 1e-10;

  late Vector3 start;
  late Vector3 end;
  late double radius;

  Capsule clone() {
    return Capsule(start.clone(), end.clone(), radius);
  }

  void set(Vector3 start, Vector3 end, double radius) {
    this.start.copy(start);
    this.end.copy(end);
    this.radius = radius;
  }

  void copy(Capsule capsule) {
    start.copy(capsule.start);
    end.copy(capsule.end);
    radius = capsule.radius;
  }

  void translate(Vector3 v) {
    start.add(v);
    end.add(v);
  }

  bool checkAABBAxis(double p1x, double p1y, double p2x, double p2y, double minx, double maxx, double miny, double maxy,
      double radius) {
    return ((minx - p1x < radius || minx - p2x < radius) &&
        (p1x - maxx < radius || p2x - maxx < radius) &&
        (miny - p1y < radius || miny - p2y < radius) &&
        (p1y - maxy < radius || p2y - maxy < radius));
  }

  bool intersectsBox(Box3 box) {
    return (checkAABBAxis(start.x, start.y, end.x, end.y, box.min.x, box.max.x, box.min.y, box.max.y, radius) &&
        checkAABBAxis(start.x, start.z, end.x, end.z, box.min.x, box.max.x, box.min.z, box.max.z, radius) &&
        checkAABBAxis(start.y, start.z, end.y, end.z, box.min.y, box.max.y, box.min.z, box.max.z, radius));
  }

  Vector3 getCenter(Vector3 target) {
    return target.copy(end).add(start).multiplyScalar(0.5);
  }

  List<Vector3> lineLineMinimumPoints(line1, line2) {
    Vector3 r = _v1.copy(line1.end).sub(line1.start);
    Vector3 s = _v2.copy(line2.end).sub(line2.start);
    Vector3 w = _v3.copy(line2.start).sub(line1.start);

    num a = r.dot(s), b = r.dot(r), c = s.dot(s), d = s.dot(w), e = r.dot(w);

    double t1;
    double t2;
    num divisor = b * c - a * a;

    if (Math.abs(divisor) < eps) {
      double d1 = -d / c;
      double d2 = (a - d) / c;

      if (Math.abs(d1 - 0.5) < Math.abs(d2 - 0.5)) {
        t1 = 0;
        t2 = d1;
      } else {
        t1 = 1;
        t2 = d2;
      }
    } else {
      t1 = (d * a + e * c) / divisor;
      t2 = (t1 * a - d) / c;
    }

    t2 = Math.max(0, Math.min(1, t2));
    t1 = Math.max(0, Math.min(1, t1));

    Vector3 point1 = r.multiplyScalar(t1).add(line1.start);
    Vector3 point2 = s.multiplyScalar(t2).add(line2.start);

    return [point1, point2];
  }
}
