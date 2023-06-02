import 'dart:convert';
import 'dart:io' show File, Directory, Platform;

import 'package:crypto/crypto.dart';
import 'package:diacritic/diacritic.dart';
import 'package:path/path.dart' as path;
// import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'dart:html' as html;
// import 'package:universal_html/html.dart' as uhtml;

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

Future<html.Entry> getDirectoryWeb() async {
  // uhtml.InputElement uploadInput = uhtml.FileUploadInputElement();
  // uploadInput.click();
  // await uploadInput.onChange.first;
  // html.File file = uploadInput.files.first;
  html.DirectoryEntry root = (await html.window.requestFileSystem(100)) as html.DirectoryEntry;
  html.Entry dir = await root.createDirectory('myApp');
  // html.FileEntry fileEntry = await dir.createFile(file.name);
  // html.FileWriter writer = await fileEntry.createWriter();
  // writer.write(file);
  return dir;
}

getCacheDirectory() async {
  // return await getTemporaryDirectory();
  // return await getExternalStorageDirectory();
  if(kIsWeb) {
    html.Entry entry = await getDirectoryWeb();
    return Directory(entry.fullPath!);
  } else if(Platform.isAndroid) {
    return await getExternalStorageDirectory();
  } else {
    return await getDownloadsDirectory();
  }
}

String _localChecksumGeneration(Map map) {
  File localFile = map['file'];
  String crypt = map['crypt'];

  Digest? digest;
  String result = '-';
  final localBytes = localFile.readAsBytesSync();
  if(crypt == 'sha1') {
    digest =  sha1.convert(localBytes);
  } else if(crypt == 'sha256') {
    digest =  sha256.convert(localBytes);
  } else if(crypt == 'sha512') {
    digest =  sha512.convert(localBytes);
  } else if(crypt == 'md5') {
    digest = md5.convert(localBytes);
  } else if(crypt == 'size-date') {
    var size = localBytes.length;
    var lastModification = localFile.lastModifiedSync().millisecondsSinceEpoch;
    // result = '$size-$lastModification';
    digest = md5.convert(utf8.encode('$size'));
    result = digest.toString();
    digest = md5.convert(utf8.encode('$lastModification'));
    result = '$result-$digest';
    digest = null;
  } else {
    digest = md5.convert(localBytes);
  }

  if(digest != null) {
    result = digest.toString();
  }
  return result;
}

Future<String> isolatedChecksumGeneration(File localFile, {crypt = 'md5'}) async {
  return await compute(_localChecksumGeneration, {'file':localFile,'crypt':'$crypt'});
}