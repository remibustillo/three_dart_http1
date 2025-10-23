import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as three;

class WebGlDebug4 extends StatefulWidget {
  final String fileName;

  const WebGlDebug4({Key? key, required this.fileName}) : super(key: key);

  @override
  State<WebGlDebug4> createState() => _State();
}

class _State extends State<WebGlDebug4> {
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

  late three.WebGLRenderTarget renderTarget;

  dynamic sourceTexture;

  bool loaded = false;

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
          clickRender();
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

    if (verbose) print(" render: sourceTexture: $sourceTexture three3dRender.textureId! ${three3dRender.textureId!} ");

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
      renderTarget = three.WebGLRenderTarget((width * dpr).toInt(), (height * dpr).toInt(), pars);
      renderTarget.samples = 4;
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget);
    }
  }

  initScene() {
    initRenderer();
    initPage();
  }

  initPage() {
    camera = three.PerspectiveCamera(45, width / height, 1, 100);
    camera.position.z = 100;

    var segmentHeight = 8;
    var segmentCount = 4;
    var height2 = segmentHeight * segmentCount;
    var halfHeight = height2 * 0.5;

    Map<String, int> sizing = {
      "segmentHeight": segmentHeight,
      "segmentCount": segmentCount,
      "height": height2,
      "halfHeight": halfHeight.toInt()
    };

    scene = three.Scene();

    var ambientLight = three.AmbientLight(0xcccccc, 0.4);
    scene.add(ambientLight);

    camera.lookAt(scene.position);

    var geometry = three.CylinderGeometry(5, 5, 5, 5, 15, false, 5, 360);

    // create the skin indices and skin weights manually
    // (typically a loader would read this data from a 3D model for you)

    var position = geometry.attributes["position"];

    var vertex = three.Vector3();

    List<int> skinIndices = [];
    List<double> skinWeights = [];

    for (var i = 0; i < position.count; i++) {
      vertex.fromBufferAttribute(position, i);

      // compute skinIndex and skinWeight based on some configuration data

      var y = (vertex.y + sizing["halfHeight"]!);

      var skinIndex = three.Math.floor(y / sizing["segmentHeight"]!);
      var skinWeight = (y % sizing["segmentHeight"]!) / sizing["segmentHeight"]!;

      skinIndices.addAll([skinIndex, skinIndex + 1, 0, 0]);
      skinWeights.addAll([1 - skinWeight, skinWeight, 0, 0]);
    }

    geometry.setAttribute('skinIndex', three.Uint16BufferAttribute(Uint16Array.fromList(skinIndices), 4));
    geometry.setAttribute('skinWeight', three.Float32BufferAttribute(Float32Array.fromList(skinWeights), 4));

    // create skinned mesh and skeleton

    var material = three.MeshBasicMaterial({"color": 0x156289, "side": three.DoubleSide, "flatShading": true});

    List<three.Bone> bones = [];
    var prevBone = three.Bone();
    bones.add(prevBone);
    prevBone.position.y = -sizing["halfHeight"]!.toDouble();

    for (var i = 0; i < sizing["segmentCount"]!; i++) {
      var bone = three.Bone();
      bone.position.y = sizing["segmentHeight"]!.toDouble();
      bones.add(bone);
      prevBone.add(bone);
      prevBone = bone;
    }

    var mesh = three.SkinnedMesh(geometry, material);
    var skeleton = three.Skeleton(bones);

    var rootBone = skeleton.bones[0];
    mesh.add(rootBone);
    mesh.bind(skeleton);
    skeleton.bones[0].rotation.x = -0.1;
    skeleton.bones[1].rotation.x = 0.2;

    scene.add(mesh);

    loaded = true;

    animate();
  }

  clickRender() {
    print("clickRender..... ");
    animate();
  }

  animate() {
    if (!mounted || disposed) {
      return;
    }

    if (!loaded) {
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
