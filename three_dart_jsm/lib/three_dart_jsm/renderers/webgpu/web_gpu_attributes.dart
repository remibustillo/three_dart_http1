import 'package:three_dart/extra/console.dart';
import 'package:three_dart/three_dart.dart';

class WebGPUAttributes {
  late WeakMap buffers;

  // TODO (WebGPU): implement

  // late GPUDevice device;

  WebGPUAttributes(device) {
    buffers = WeakMap();
    // this.device = device;
  }

  get(attribute) {
    if (attribute is InterleavedBufferAttribute) attribute = attribute.data;

    return buffers.get(attribute);
  }

  remove(attribute) {
    if (attribute is InterleavedBufferAttribute) attribute = attribute.data;

    var data = buffers.get(attribute);

    if (data != null) {
      data.buffer.destroy();

      buffers.delete(attribute);
    }
  }

  update(attribute, [isIndex = false, usage]) {
    if (attribute is InterleavedBufferAttribute) attribute = attribute.data;

    var data = buffers.get(attribute);

    if (data == undefined) {
      if (usage == null) {
        // usage = (isIndex == true) ? GPUBufferUsage.Index : GPUBufferUsage.Vertex;
      }

      data = _createBuffer(attribute, usage);

      buffers.set(attribute, data);
    } else if (usage != null && usage != data.usage) {
      data.buffer.destroy();

      data = _createBuffer(attribute, usage);

      buffers.set(attribute, data);
    } else if (data["version"] < attribute.version) {
      _writeBuffer(data["buffer"], attribute);

      data["version"] = attribute.version;
    }
  }

  Map _createBuffer(attribute, usage) {
    // var array = attribute.array;
    // var size = array.byteLength + ((4 - (array.byteLength % 4)) % 4); // ensure 4 byte alignment, see #20441

    // var buffer = this
    // .device
    // .createBuffer(GPUBufferDescriptor(size: size, usage: usage | GPUBufferUsage.CopyDst, mappedAtCreation: true));

    // if (array is Float32Array) {
    //   var pointer = buffer.getMappedRange(size: array.lengthInBytes);
    //   Float32List _list = (pointer.cast<Float>()).asTypedList(array.length);

    //   for (var i = 0; i < array.length; i++) {
    //     _list[i] = array[i];
    //   }
    // } else if (array is Uint16Array) {
    //   Pointer<Int16> p = buffer.getMappedRange(size: array.lengthInBytes).cast();

    //   for (var i = 0; i < array.len; i++) {
    //     p[i] = array[i];
    //   }
    // } else {
    //   throw ("WebGPUAttributes attribute upload buffer $array is not support ");
    // }

    // buffer.unmap();

    // // TODO
    // // attribute.onUploadCallback();

    // return {"version": attribute.version, "buffer": buffer, "usage": usage};
    return {};
  }

  _writeBuffer(buffer, attribute) {
    // var array = attribute.array;
    var updateRange = attribute.updateRange;

    if (updateRange.count == -1) {
      // Not using update ranges

      // this.device.queue.writeBuffer(buffer, 0, array, 0);
    } else {
      // this.device.queue.writeBuffer(buffer, 0, array, updateRange.count * array.BYTES_PER_ELEMENT);

      updateRange.count = -1; // reset range

    }
  }
}
