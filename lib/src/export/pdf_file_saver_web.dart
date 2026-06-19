import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> savePdfFile({
  required Uint8List bytes,
  required String filename,
}) async {
  final Uint8List downloadBytes = Uint8List.fromList(bytes);
  final web.Blob blob = web.Blob(
    <JSUint8Array>[downloadBytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = filename
        ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
  return filename;
}
