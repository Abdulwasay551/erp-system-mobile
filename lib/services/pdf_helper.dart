import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'api_client.dart';

/// Downloads a PDF from [path] via [api] and opens it with the device's PDF viewer.
/// Throws [ApiException] on a failed fetch; rethrows any open_file failure as an
/// [Exception] with a readable message.
Future<void> downloadAndOpenPdf(ApiClient api, String path, String filename) async {
  final bytes = await api.requestBytes(path);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFile.open(file.path, type: 'application/pdf');
  if (result.type != ResultType.done) {
    throw Exception(result.message.isNotEmpty ? result.message : 'No PDF viewer app found.');
  }
}
