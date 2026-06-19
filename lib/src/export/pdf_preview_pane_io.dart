import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:printing/printing.dart';

class PdfPreviewPane extends StatelessWidget {
  const PdfPreviewPane({
    super.key,
    required this.bytes,
    required this.filename,
  });

  final Uint8List bytes;
  final String filename;

  @override
  Widget build(BuildContext context) {
    return PdfPreview(
      build: (_) async => Uint8List.fromList(bytes),
      pdfFileName: filename,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      useActions: false,
    );
  }
}
