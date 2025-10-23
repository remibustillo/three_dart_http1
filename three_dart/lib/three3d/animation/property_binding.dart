// Characters [].:/ are reserved for track binding syntax.
import 'package:three_dart/three3d/animation/animation_object_group.dart';
import 'package:three_dart/three3d/core/index.dart';
import 'package:three_dart/three3d/materials/index.dart';
import 'package:three_dart/three3d/math/index.dart';

var _reservedCharsRe = '\\[\\]\\.:\\/';
var _reservedRe = RegExp("[$_reservedCharsRe]");

// Attempts to allow node names from any language. ES5's `\w` regexp matches
// only latin characters, and the unicode \p{L} is not yet supported. So
// instead, we exclude reserved characters and match everything else.
var _wordChar = '[^$_reservedCharsRe]';
var _wordCharOrDot = '[^${_reservedCharsRe.replaceAll('\\.', '')}]';

// Parent directories, delimited by '/' or ':'. Currently unused, but must
// be matched to parse the rest of the track name.
var _directoryRe = RegExp(r"((?:WC+[\/:])*)").pattern.replaceAll('WC', _wordChar);

// Target node. May contain word characters (a-zA-Z0-9_) and '.' or '-'.
var _nodeRe = RegExp(r"(WCOD+)?").pattern.replaceAll('WCOD', _wordCharOrDot);

// Object on target node, and accessor. May not contain reserved
// characters. Accessor may contain any character except closing bracket.
var _objectRe = RegExp(r"(?:\.(WC+)(?:\[(.+)\])?)?").pattern.replaceAll('WC', _wordChar);

// Property and accessor. May not contain reserved characters. Accessor may
// contain any non-bracket characters.
var _propertyRe = RegExp(r"\.(WC+)(?:\[(.+)\])?").pattern.replaceAll('WC', _wordChar);

String _ts = "^$_directoryRe$_nodeRe$_objectRe$_propertyRe\$";
var _trackRe = RegExp(_ts);

var _supportedObjectNames = ['material', 'materials', 'bones'];

class Composite {
  late dynamic _targetGroup;
  late dynamic _bindings;

  Composite(targetGroup, path, optionalParsedPath) {
    var parsedPath = optionalParsedPath ?? PropertyBinding.parseTrackName(path);

    _targetGroup = targetGroup;
    _bindings = targetGroup.subscribe_(path, parsedPath);
  }

  getValue(array, offset) {
    bind(); // bind all binding

    var firstValidIndex = _targetGroup.nCachedObjects_, binding = _bindings[firstValidIndex];

    // and only call .getValue on the first
    if (binding != null) binding.getValue(array, offset);
  }

  setValue(array, offset) {
    var bindings = _bindings;

    for (var i = _targetGroup.nCachedObjects_, n = bindings.length; i != n; ++i) {
      bindings[i].setValue(array, offset);
    }
  }

  bind() {
    var bindings = _bindings;

    for (var i = _targetGroup.nCachedObjects_, n = bindings.length; i != n; ++i) {
      bindings[i].bind();
    }
  }

  unbind() {
    var bindings = _bindings;

    for (var i = _targetGroup.nCachedObjects_, n = bindings.length; i != n; ++i) {
      bindings[i].unbind();
    }
  }
}

class PropertyBinding {
  late String path;
  late Map<String, dynamic> parsedPath;
  late dynamic node;
  late dynamic rootNode;

  late String propertyName;
  late dynamic resolvedProperty;

  late dynamic targetObject;
  late Function getValue;
  late Function setValue;
  late dynamic propertyIndex;

  var bindingTypeObject = {"Direct": 0, "EntireArray": 1, "ArrayElement": 2, "HasFromToArray": 3};

  var versioningObject = {"None": 0, "NeedsUpdate": 1, "MatrixWorldNeedsUpdate": 2};

  PropertyBinding(this.rootNode, this.path, [Map<String, String?>? parsedPath]) {
    this.parsedPath = parsedPath ?? PropertyBinding.parseTrackName(path);

    node = PropertyBinding.findNode(rootNode, this.parsedPath["nodeName"]) ?? rootNode;

    getValue = getValueUnbound;
    setValue = setValueUnbound;
  }

  static create(root, path, parsedPath) {
    if (!(root != null && root is AnimationObjectGroup)) {
      return PropertyBinding(root, path, parsedPath);
    } else {
      return Composite(root, path, parsedPath);
    }
  }

  /// Replaces spaces with underscores and removes unsupported characters from
  /// node names, to ensure compatibility with parseTrackName().
  static String sanitizeNodeName(String input) {
    final reg = RegExp(r"\s");

    String name = input.replaceAll(reg, '_');
    name = name.replaceAll(_reservedRe, '');

    return name;
  }

  static Map<String, String?> parseTrackName(trackName) {
    var matches = _trackRe.firstMatch(trackName);

    if (matches == null) {
      throw ('PropertyBinding: Cannot parse trackName: $trackName');
    }

    // var results = {
    // 	// directoryName: matches[ 1 ], // (tschw) currently unused
    // 	"nodeName": matches[ 2 ],
    // 	"objectName": matches[ 3 ],
    // 	"objectIndex": matches[ 4 ],
    // 	"propertyName": matches[ 5 ], // required
    // 	"propertyIndex": matches[ 6 ]
    // };

    var results = <String, String?>{
      // directoryName: matches[ 1 ], // (tschw) currently unused
      "nodeName": matches.group(2),
      "objectName": matches.group(3),
      "objectIndex": matches.group(4),
      "propertyName": matches.group(5), // required
      "propertyIndex": matches.group(6)
    };

    String? nodeName = results["nodeName"];

    int? lastDot;

    if (nodeName != null) {
      lastDot = nodeName.lastIndexOf('.');
    }

    if (lastDot != null && lastDot != -1) {
      var objectName = results["nodeName"]!.substring(lastDot + 1);

      // Object names must be checked against an allowlist. Otherwise, there
      // is no way to parse 'foo.bar.baz': 'baz' must be a property, but
      // 'bar' could be the objectName, or part of a nodeName (which can
      // include '.' characters).
      if (_supportedObjectNames.contains(objectName)) {
        results["nodeName"] = results["nodeName"]!.substring(0, lastDot);
        results["objectName"] = objectName;
      }
    }

    if (results["propertyName"] == null || results["propertyName"]!.isEmpty) {
      throw ('PropertyBinding: can not parse propertyName from trackName: $trackName');
    }

    return results;
  }

  static searchNodeSubtree(children, nodeName) {
    for (var i = 0; i < children.length; i++) {
      var childNode = children[i];

      if (childNode.name == nodeName || childNode.uuid == nodeName) {
        return childNode;
      }

      var result = searchNodeSubtree(childNode.children, nodeName);

      if (result != null) return result;
    }

    return null;
  }

  static findNode(root, nodeName) {
    if (nodeName == null ||
        nodeName == '' ||
        nodeName == '.' ||
        nodeName == -1 ||
        nodeName == root.name ||
        nodeName == root.uuid) {
      return root;
    }

    // search into skeleton bones.
    if (root.skeleton != null) {
      var bone = root.skeleton.getBoneByName(nodeName);

      if (bone != null) {
        return bone;
      }
    }

    // search into node subtree.
    if (root.children != null) {
      var subTreeNode = searchNodeSubtree(root.children, nodeName);

      if (subTreeNode != null) {
        return subTreeNode;
      }
    }

    return null;
  }

  // these are used to "bind" a nonexistent property
  _getValueUnavailable() {}
  _setValueUnavailable() {}

  void Function(List<int>, int) getterByBindingType(int idx) {
    if (idx == 0) {
      return getValueDirect;
    } else if (idx == 1) {
      return getValueArray;
    } else if (idx == 2) {
      return getValueArrayElement;
    } else if (idx == 3) {
      return getValueToArray;
    } else {
      throw ("PropertyBinding.getterByBindingType idx: $idx is not support ");
    }
  }

  // 0
  void getValueDirect(List<int> buffer, int offset) {
    var v = targetObject.getProperty(propertyName);
    buffer[offset] = v;
  }

  // 1
  void getValueArray(List<int> buffer, int offset) {
    var source = resolvedProperty;
    for (var i = 0, n = source.length; i != n; ++i) {
      buffer[offset++] = source[i];
    }
  }

  // 2
  void getValueArrayElement(List<int> buffer, int offset) {
    buffer[offset] = resolvedProperty[propertyIndex];
  }

  // 3
  void getValueToArray(List<int> buffer, int offset) {
    resolvedProperty.toArray(buffer, offset);
  }

  setterByBindingTypeAndVersioning(bindingType, versioning) {
    // var fns = [
    // 	[
    // 		// Direct
    //     setValue_direct,
    // 		setValue_direct_setNeedsUpdate,
    // 		setValue_direct_setMatrixWorldNeedsUpdate
    // 	], [
    // 		// EntireArray
    //     setValue_array,
    // 		setValue_array_setNeedsUpdate,
    // 		setValue_array_setMatrixWorldNeedsUpdate
    // 	], [
    // 		// ArrayElement
    // 		setValue_arrayElement,
    // 		setValue_arrayElement_setNeedsUpdate,
    // 		setValue_arrayElement_setMatrixWorldNeedsUpdate
    // 	], [
    // 		// HasToFromArray
    //     setValue_fromArray,
    // 		setValue_fromArray_setNeedsUpdate,
    // 		setValue_fromArray_setMatrixWorldNeedsUpdate
    // 	]
    // ];

    if (bindingType == 0) {
      if (versioning == 0) {
        return setValueDirect;
      } else if (versioning == 1) {
        return setValueDirectSetNeedsUpdate;
      } else if (versioning == 2) {
        return setValueDirectSetMatrixWorldNeedsUpdate;
      }
    } else if (bindingType == 1) {
      if (versioning == 0) {
        return setValueArray;
      } else if (versioning == 1) {
        return setValueArraySetNeedsUpdate;
      } else if (versioning == 2) {
        return setValueArraySetMatrixWorldNeedsUpdate;
      }
    } else if (bindingType == 2) {
      if (versioning == 0) {
        return setValueArrayElement;
      } else if (versioning == 1) {
        return setValueArrayElementSetNeedsUpdate;
      } else if (versioning == 2) {
        return setValueArrayElementSetMatrixWorldNeedsUpdate;
      }
    } else if (bindingType == 3) {
      if (versioning == 0) {
        return setValueFromArray;
      } else if (versioning == 1) {
        return setValueFromArraySetNeedsUpdate;
      } else if (versioning == 2) {
        return setValueFromArraySetMatrixWorldNeedsUpdate;
      }
    }
  }

  setValueDirect(buffer, offset) {
    // this.targetObject[ this.propertyName ] = buffer[ offset ];
    targetObject.setProperty(propertyName, buffer[offset]);
  }

  setValueDirectSetNeedsUpdate(buffer, offset) {
    // this.targetObject[ this.propertyName ] = buffer[ offset ];
    targetObject.setProperty(propertyName, buffer[offset]);
    targetObject.needsUpdate = true;
  }

  setValueDirectSetMatrixWorldNeedsUpdate(buffer, offset) {
    // this.targetObject[ this.propertyName ] = buffer[ offset ];
    targetObject.setProperty(propertyName, buffer[offset]);
    targetObject.matrixWorldNeedsUpdate = true;
  }

  setValueArray(buffer, offset) {
    var dest = resolvedProperty;
    for (var i = 0, n = dest.length; i != n; ++i) {
      dest[i] = buffer[offset++];
    }
  }

  setValueArraySetNeedsUpdate(buffer, offset) {
    var dest = resolvedProperty;
    for (var i = 0, n = dest.length; i != n; ++i) {
      dest[i] = buffer[offset++];
    }
    targetObject.needsUpdate = true;
  }

  setValueArraySetMatrixWorldNeedsUpdate(buffer, offset) {
    var dest = resolvedProperty;
    for (var i = 0, n = dest.length; i != n; ++i) {
      dest[i] = buffer[offset++];
    }
    targetObject.matrixWorldNeedsUpdate = true;
  }

  setValueArrayElement(buffer, offset) {
    resolvedProperty[propertyIndex] = buffer[offset];
  }

  setValueArrayElementSetNeedsUpdate(buffer, offset) {
    resolvedProperty[propertyIndex] = buffer[offset];
    targetObject.needsUpdate = true;
  }

  setValueArrayElementSetMatrixWorldNeedsUpdate(buffer, offset) {
    resolvedProperty[propertyIndex] = buffer[offset];
    targetObject.matrixWorldNeedsUpdate = true;
  }

  setValueFromArray(buffer, offset) {
    resolvedProperty.fromArray(buffer, offset);
  }

  setValueFromArraySetNeedsUpdate(buffer, offset) {
    resolvedProperty.fromArray(List<double>.from(buffer.map((e) => e.toDouble())), offset);
    targetObject.needsUpdate = true;
  }

  setValueFromArraySetMatrixWorldNeedsUpdate(buffer, offset) {
    resolvedProperty.fromArray(buffer, offset);
    targetObject.matrixWorldNeedsUpdate = true;
  }

  getValueUnbound(targetArray, offset) {
    bind();
    getValue(targetArray, offset);

    // Note: This class uses a State pattern on a per-method basis:
    // 'bind' sets 'this.getValue' / 'setValue' and shadows the
    // prototype version of these methods with one that represents
    // the bound state. When the property is not found, the methods
    // become no-ops.
  }

  setValueUnbound(sourceArray, offset) {
    bind();
    setValue(sourceArray, offset);
  }

  // create getter / setter pair for a property in the scene graph
  bind() {
    var targetObject = node;
    var parsedPath = this.parsedPath;

    var objectName = parsedPath["objectName"];
    propertyName = parsedPath["propertyName"];
    var propertyIndex = parsedPath["propertyIndex"];

    if (targetObject == null) {
      targetObject = PropertyBinding.findNode(rootNode, parsedPath["nodeName"]) || rootNode;

      node = targetObject;
    }

    // set fail state so we can just 'return' on error
    getValue = _getValueUnavailable;
    setValue = _setValueUnavailable;

    // ensure there is a value node
    if (targetObject == null) {
      print('three.PropertyBinding: Trying to update node for track: $path but it wasn\'t found.');
      return;
    }

    if (objectName != null) {
      var objectIndex = parsedPath["objectIndex"];

      // special cases were we need to reach deeper into the hierarchy to get the face materials....
      switch (objectName) {
        case 'materials':
          if (!targetObject.material) {
            print('three.PropertyBinding: Can not bind to material as node does not have a material. ${this}');
            return;
          }

          if (!targetObject.material.materials) {
            print(
                'three.PropertyBinding: Can not bind to material.materials as node.material does not have a materials array. ${this}');
            return;
          }

          targetObject = targetObject.material.materials;

          break;

        case 'bones':
          if (!targetObject.skeleton) {
            print('three.PropertyBinding: Can not bind to bones as node does not have a skeleton. ${this}');
            return;
          }

          // potential future optimization: skip this if propertyIndex is already an integer
          // and convert the integer string to a true integer.

          targetObject = targetObject.skeleton.bones;

          // support resolving morphTarget names into indices.
          for (var i = 0; i < targetObject.length; i++) {
            if (targetObject[i].name == objectIndex) {
              objectIndex = i;
              break;
            }
          }

          break;

        default:
          if (targetObject.getProperty(objectName) == null) {
            print('three.PropertyBinding: Can not bind to objectName of node null. ${this}');
            return;
          }

          // targetObject = targetObject[ objectName ];
          targetObject = targetObject.getProperty(objectName);
      }

      if (objectIndex != null) {
        if (targetObject[objectIndex] == null) {
          print(
              'three.PropertyBinding: Trying to bind to objectIndex of objectName, but is null.${this} $targetObject');
          return;
        }

        targetObject = targetObject[objectIndex];
      }
    }

    // resolve property
    var nodeProperty = targetObject.getProperty(propertyName);

    if (nodeProperty == null) {
      var nodeName = parsedPath["nodeName"];

      print(
          'three.PropertyBinding: Trying to update property for track: $nodeName $propertyName  but it wasn\'t found. $targetObject');
      return;
    }

    // determine versioning scheme
    var versioning = versioningObject["None"];

    this.targetObject = targetObject;

    if (targetObject is Material) {
      // material
      versioning = versioningObject["NeedsUpdate"];
    } else if (targetObject is Object3D) {
      // node transform

      versioning = versioningObject["MatrixWorldNeedsUpdate"];
    }

    // determine how the property gets bound
    var bindingType = bindingTypeObject["Direct"];

    if (propertyIndex != null) {
      // access a sub element of the property array (only primitives are supported right now)

      if (propertyName == 'morphTargetInfluences') {
        // potential optimization, skip this if propertyIndex is already an integer, and convert the integer string to a true integer.

        // support resolving morphTarget names into indices.
        if (!targetObject.geometry) {
          print(
              'three.PropertyBinding: Can not bind to morphTargetInfluences because node does not have a geometry. ${this}');
          return;
        }

        if (targetObject.geometry is BufferGeometry) {
          if (!targetObject.geometry.morphAttributes) {
            print(
                'three.PropertyBinding: Can not bind to morphTargetInfluences because node does not have a geometry.morphAttributes. ${this}');
            return;
          }

          if (targetObject.morphTargetDictionary[propertyIndex] != null) {
            propertyIndex = targetObject.morphTargetDictionary[propertyIndex];
          }
        } else {
          print(
              'three.PropertyBinding: Can not bind to morphTargetInfluences on three.Geometry. Use three.BufferGeometry instead. ${this}');
          return;
        }
      }

      bindingType = bindingTypeObject["ArrayElement"];

      resolvedProperty = nodeProperty;
      this.propertyIndex = propertyIndex;
    } else if (nodeProperty is Color || nodeProperty is Vector3 || nodeProperty is Quaternion) {
      // must use copy for Object3D.Euler/Quaternion

      bindingType = bindingTypeObject["HasFromToArray"];

      resolvedProperty = nodeProperty;
    } else if (nodeProperty is List) {
      bindingType = bindingTypeObject["EntireArray"];

      resolvedProperty = nodeProperty;
    } else {
      propertyName = propertyName;
    }

    // select getter / setter
    getValue = getterByBindingType(bindingType!);
    setValue = setterByBindingTypeAndVersioning(bindingType, versioning);
  }

  unbind() {
    node = null;

    // back to the prototype version of getValue / setValue
    // note: avoiding to mutate the shape of 'this' via 'delete'
    getValue = _getValueUnbound;
    setValue = _setValueUnbound;
  }

  _getValueUnbound() {
    return getValue();
  }

  _setValueUnbound() {
    return setValue();
  }
}

// DECLARE ALIAS AFTER assign prototype
// Object.assign( PropertyBinding.prototype, {

// 	// initial state of these methods that calls 'bind'
// 	_getValue_unbound: PropertyBinding.prototype.getValue,
// 	_setValue_unbound: PropertyBinding.prototype.setValue,

// } );
