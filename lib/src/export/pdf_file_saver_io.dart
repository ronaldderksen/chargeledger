import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:printing/printing.dart';

Future<String?> savePdfFile({
  required Uint8List bytes,
  required String filename,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    return filename;
  }

  final FileSaveLocation? location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
    ],
  );
  if (location == null) {
    return null;
  }
  final File file = File(location.path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
