import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as three;

class WebGlLoaderSvg extends StatefulWidget {
  final String fileName;

  const WebGlLoaderSvg({Key? key, required this.fileName}) : super(key: key);

  @override
  State<WebGlLoaderSvg> createState() => _MyAppState();
}

class _MyAppState extends State<WebGlLoaderSvg> {
  late FlutterGlPlugin three3dRender;
  three.WebGLRenderer? renderer;

  int? fboId;
  late double width;
  late double height;

  Size? screenSize;

  late three.Scene scene;
  late three.Camera camera;
  late three.Mesh mesh;

  double dpr = 1.0;

  var amount = 4;

  bool verbose = true;
  bool disposed = false;

  late three.Object3D object;

  late three.Texture texture;

  late three.WebGLMultisampleRenderTarget renderTarget;

  dynamic sourceTexture;

  var guiData = {
    "currentURL": 'assets/models/svg/tiger.svg',
    // "currentURL": 'assets/models/svg/energy.svg',
    // "currentURL": 'assets/models/svg/hexagon.svg',
    // "currentURL": 'assets/models/svg/lineJoinsAndCaps.svg',
    // "currentURL": 'assets/models/svg/multiple-css-classes.svg',
    // "currentURL": 'assets/models/svg/threejs.svg',
    // "currentURL": 'assets/models/svg/zero-radius.svg',
    "drawFillShapes": true,
    "drawStrokes": true,
    "fillShapesWireframe": false,
    "strokesWireframe": false
  };

  @override
  void initState() {
    super.initState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    width = screenSize!.width;
    height = screenSize!.height;

    three3dRender = FlutterGlPlugin();

    Map<String, dynamic> options = {
      "antialias": true,
      "alpha": false,
      "width": width.toInt(),
      "height": height.toInt(),
      "dpr": dpr
    };

    await three3dRender.initialize(options: options);

    setState(() {});

    // Wait for web
    Future.delayed(const Duration(milliseconds: 100), () async {
      await three3dRender.prepareContext();

      initScene();
    });
  }

  initSize(BuildContext context) {
    if (screenSize != null) {
      return;
    }

    final mqd = MediaQuery.of(context);

    screenSize = mqd.size;
    dpr = mqd.devicePixelRatio;

    initPlatformState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
      ),
      body: Builder(
        builder: (BuildContext context) {
          initSize(context);
          return SingleChildScrollView(child: _build(context));
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Text("render"),
        onPressed: () {
          render();
        },
      ),
    );
  }

  Widget _build(BuildContext context) {
    return Column(
      children: [
        Stack(
          children: [
            Container(
                width: width,
                height: height,
                color: Colors.black,
                child: Builder(builder: (BuildContext context) {
                  if (kIsWeb) {
                    return three3dRender.isInitialized
                        ? HtmlElementView(viewType: three3dRender.textureId!.toString())
                        : Container();
                  } else {
                    return three3dRender.isInitialized ? Texture(textureId: three3dRender.textureId!) : Container();
                  }
                })),
          ],
        ),
      ],
    );
  }

  render() {
    int t = DateTime.now().millisecondsSinceEpoch;

    final gl = three3dRender.gl;

    renderer!.render(scene, camera);

    int t1 = DateTime.now().millisecondsSinceEpoch;

    if (verbose) {
      print("render cost: ${t1 - t} ");
      print(renderer!.info.memory);
      print(renderer!.info.render);
    }

    // 重要 更新纹理之前一定要调用 确保gl程序执行完毕
    gl.flush();

    if (verbose) print(" render: sourceTexture: $sourceTexture ");

    if (!kIsWeb) {
      three3dRender.updateTexture(sourceTexture);
    }
  }

  initRenderer() {
    Map<String, dynamic> options = {
      "width": width,
      "height": height,
      "gl": three3dRender.gl,
      "antialias": true,
      "canvas": three3dRender.element
    };
    renderer = three.WebGLRenderer(options);
    renderer!.setPixelRatio(dpr);
    renderer!.setSize(width, height, false);
    renderer!.shadowMap.enabled = false;

    if (!kIsWeb) {
      var pars = three.WebGLRenderTargetOptions({"format": three.RGBAFormat});
      renderTarget = three.WebGLMultisampleRenderTarget((width * dpr).toInt(), (height * dpr).toInt(), pars);
      renderTarget.samples = 4;
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget);
    }
  }

  initScene() {
    initRenderer();
    initPage();
  }

  initPage() async {
    camera = three.PerspectiveCamera(50, width / height, 1, 1000);
    camera.position.set(0, 0, 200);

    loadSVG(guiData["currentURL"]);

    animate();
  }

  loadSVG(url) {
    //

    scene = three.Scene();
    scene.background = three.Color(0xb0b0b0);

    //

    var helper = three.GridHelper(160, 10);
    helper.rotation.x = three.Math.pi / 2;
    scene.add(helper);

    //

    var loader = three.SVGLoader(null);

    loader.load(url, (data) {
      var paths = data["paths"];

      var group = three.Group();
      group.scale.multiplyScalar(0.25);
      group.position.x = -70;
      group.position.y = 70;
      group.scale.y *= -1;

      for (var i = 0; i < paths.length; i++) {
        var path = paths[i];

        var fillColor = path.userData["style"]["fill"];
        if (guiData["drawFillShapes"] == true && fillColor != null && fillColor != 'none') {
          var material = three.MeshBasicMaterial({
            "color": three.Color().setStyle(fillColor).convertSRGBToLinear(),
            "opacity": path.userData["style"]["fillOpacity"],
            "transparent": true,
            "side": three.DoubleSide,
            "depthWrite": false,
            "wireframe": guiData["fillShapesWireframe"]
          });

          var shapes = three.SVGLoader.createShapes(path);

          for (var j = 0; j < shapes.length; j++) {
            var shape = shapes[j];

            var geometry = three.ShapeGeometry(shape);
            var mesh = three.Mesh(geometry, material);

            group.add(mesh);
          }
        }

        var strokeColor = path.userData["style"]["stroke"];

        if (guiData["drawStrokes"] == true && strokeColor != null && strokeColor != 'none') {
          var material = three.MeshBasicMaterial({
            "color": three.Color().setStyle(strokeColor).convertSRGBToLinear(),
            "opacity": path.userData["style"]["strokeOpacity"],
            "transparent": true,
            "side": three.DoubleSide,
            "depthWrite": false,
            "wireframe": guiData["strokesWireframe"]
          });

          for (var j = 0, jl = path.subPaths.length; j < jl; j++) {
            var subPath = path.subPaths[j];

            var geometry = three.SVGLoader.pointsToStroke(subPath.getPoints(), path.userData["style"]);

            if (geometry != null) {
              var mesh = three.Mesh(geometry, material);

              group.add(mesh);
            }
          }
        }
      }

      scene.add(group);

      render();
    });
  }

  animate() {
    if (!mounted || disposed) {
      return;
    }

    render();

    // Future.delayed(Duration(milliseconds: 40), () {
    //   animate();
    // });
  }

  @override
  void dispose() {
    print(" dispose ............. ");
    disposed = true;
    three3dRender.dispose();

    super.dispose();
  }
}
