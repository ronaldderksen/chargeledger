import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class PdfPreviewPane extends StatefulWidget {
  const PdfPreviewPane({
    super.key,
    required this.bytes,
    required this.filename,
  });

  final Uint8List bytes;
  final String filename;

  @override
  State<PdfPreviewPane> createState() => _PdfPreviewPaneState();
}

class _PdfPreviewPaneState extends State<PdfPreviewPane> {
  static int _nextViewId = 0;

  late final String _viewType = 'chargeledger-pdf-preview-${_nextViewId++}';
  String? _url;

  @override
  void initState() {
    super.initState();
    _registerView();
  }

  @override
  void dispose() {
    _revokeUrl();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  void _registerView() {
    final Uint8List previewBytes = Uint8List.fromList(widget.bytes);
    final web.Blob blob = web.Blob(
      <JSUint8Array>[previewBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    _url = web.URL.createObjectURL(blob);

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final web.HTMLIFrameElement frame = web.HTMLIFrameElement()
        ..src = _url!
        ..title = widget.filename
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return frame;
    });
  }

  void _revokeUrl() {
    final String? url = _url;
    if (url == null) {
      return;
    }
    web.URL.revokeObjectURL(url);
    _url = null;
  }
}
