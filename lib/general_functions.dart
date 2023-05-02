import 'dart:io' show Directory;

import 'package:diacritic/diacritic.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

String getBaseUrl(pUrl) {
  final parse = Uri.parse(pUrl);
  final uri = parse.query != '' ? parse.replace(query: '') : parse;
  String url = uri.toString();
  if (url.endsWith('?')) url = url.replaceAll('?', '');
  return url;
}

String getLocalCacheFilesRoute(String url, Directory dir) {
  String temporaryDirectoryPath = dir.path;
  url = removeDiacritics(Uri.decodeFull(url)).replaceAll(' ', '_');
  var baseUrl = getBaseUrl(url);
  String fileBaseName = path.basename(baseUrl);
  return path.join(temporaryDirectoryPath, 'Files', fileBaseName);
}

getCacheDirectory() async {
  // return await getTemporaryDirectory();
  return await getExternalStorageDirectory();
}