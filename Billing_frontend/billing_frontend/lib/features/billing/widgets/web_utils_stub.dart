// Stub for non-web platforms
// ignore_for_file: avoid_classes_with_only_static_members

class IFrameElement {
  String? src;
  final _Style style = _Style();
}

class _Style {
  String? border;
  String? width;
  String? height;
}

class Blob {
  Blob(List<dynamic> parts, [String? type]);
}

class Url {
  static String createObjectUrl(dynamic blob) => '';
}

class HttpRequest {
  static Future<_XhrResponse> request(String url,
      {String? method, String? responseType}) async {
    return _XhrResponse();
  }
}

class _XhrResponse {
  dynamic response;
}

// ignore: non_constant_identifier_names
final platformViewRegistry = _PlatformViewRegistry();

class _PlatformViewRegistry {
  void registerViewFactory(String id, dynamic Function(int) factory) {}
}
