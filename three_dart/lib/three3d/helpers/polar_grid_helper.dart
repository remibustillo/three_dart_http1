import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three3d/core/buffer_attribute.dart';
import 'package:three_dart/three3d/core/buffer_geometry.dart';
import 'package:three_dart/three3d/materials/line_basic_material.dart';
import 'package:three_dart/three3d/math/index.dart';
import 'package:three_dart/three3d/objects/line_segments.dart';

class PolarGridHelper extends LineSegments {
  PolarGridHelper.create(geomertey, material) : super(geomertey, material);

  factory PolarGridHelper(
      [radius = 10, radials = 16, circles = 8, divisions = 64, color1 = 0x444444, color2 = 0x888888]) {
    color1 = Color(color1);
    color2 = Color(color2);

    List<double> vertices = [];
    List<double> colors = [];

    // create the radials

    for (var i = 0; i <= radials; i++) {
      var v = (i / radials) * (Math.pi * 2);

      var x = Math.sin(v) * radius;
      var z = Math.cos(v) * radius;

      vertices.addAll([0, 0, 0]);
      vertices.addAll([x, 0, z]);

      var color = ((i & 1) != 0) ? color1 : color2;

      colors.addAll([color.r, color.g, color.b]);
      colors.addAll([color.r, color.g, color.b]);
    }

    // create the circles

    for (var i = 0; i <= circles; i++) {
      var color = ((i & 1) != 0) ? color1 : color2;

      var r = radius - (radius / circles * i);

      for (var j = 0; j < divisions; j++) {
        // first vertex

        var v = (j / divisions) * (Math.pi * 2);

        var x = Math.sin(v) * r;
        var z = Math.cos(v) * r;

        vertices.addAll([x, 0, z]);
        colors.addAll([color.r, color.g, color.b]);

        // second vertex

        v = ((j + 1) / divisions) * (Math.pi * 2);

        x = Math.sin(v) * r;
        z = Math.cos(v) * r;

        vertices.addAll([x, 0, z]);
        colors.addAll([color.r, color.g, color.b]);
      }
    }

    var geometry = BufferGeometry();
    geometry.setAttribute('position', Float32BufferAttribute(Float32Array.from(vertices), 3));
    geometry.setAttribute('color', Float32BufferAttribute(Float32Array.from(colors), 3));

    var material = LineBasicMaterial({"vertexColors": true, "toneMapped": false});

    var pgh = PolarGridHelper.create(geometry, material);

    pgh.type = 'PolarGridHelper';
    return pgh;
  }
}
