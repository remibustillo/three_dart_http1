import 'dart:convert' as convert;

class LoaderUtils {
  static decodeText(List<int> array) {
    var s = convert.Utf8Decoder().convert(array);
    return s;

    // if ( typeof TextDecoder !== 'undefined' ) {
    // 	return new TextDecoder().decode( array );
    // }

    // Avoid the String.fromCharCode.apply(null, array) shortcut, which
    // throws a "maximum call stack size exceeded" error for large arrays.

    // String s = '';
    // for ( var i = 0, il = array.length; i < il; i ++ ) {
    // 	// Implicitly assumes little-endian.
    // 	s += String.fromCharCode( array[ i ] );
    // }
    // return s;

    // try {

    // 	// merges multi-byte utf-8 characters.

    // 	return Uri.encodeComponent( RegExp.escape( s ) );

    // } catch ( e ) { // see #16358

    // 	return s;

    // }
  }

  static extractUrlBase(String url) {
    var index = url.lastIndexOf('/');

    if (index == -1) return './';

    return url.substring(0, index + 1);
  }

  /* UTILITY FUNCTIONS */
  static resolveURL(url, String path) {
    // Invalid URL
    // if ( typeof url != 'string' || url == '' ) return '';
    if (url is! String || url == '') return '';

    // Host Relative URL
    final reg1 = RegExp("^https?://", caseSensitive: false);
    if (reg1.hasMatch(path) && RegExp("^/", caseSensitive: false).hasMatch(url)) {
      final reg2 = RegExp("(^https?://[^/]+).*", caseSensitive: false);

      final matches = reg2.allMatches(path);

      for (var m in matches) {
        path = path.replaceFirst(m.group(0)!, m.group(1)!);
      }

      print("GLTFHelper.resolveURL todo debug  ");
      // path = path.replace( RegExp("(^https?:\/\/[^\/]+).*", caseSensitive: false), '$1' );

    }

    // Absolute URL http://,https://,//
    if (RegExp("^(https?:)?//", caseSensitive: false).hasMatch(url)) {
      return url;
    }

    // Data URI
    if (RegExp(r"^data:.*,.*$", caseSensitive: false).hasMatch(url)) return url;

    // Blob URL
    if (RegExp(r"^blob:.*$", caseSensitive: false).hasMatch(url)) return url;

    // Relative URL
    return path + url;
  }
}
