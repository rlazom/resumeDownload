import 'dart:io';

import 'package:dio/dio.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'general_functions.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resume Download Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Resume Download Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String fileUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
  String fileLocalRouteStr = '';
  Dio dio = Dio();
  Directory? dir;
  TextEditingController urlTextEditingCtrl = TextEditingController();
  CancelToken cancelToken = CancelToken();
  final percentNotifier = ValueNotifier<double?>(null);
  final localNotifier = ValueNotifier<String?>(null);
  List<int> sizes = [];

  @override
  void initState() {
    super.initState();
    urlTextEditingCtrl.text = fileUrl;
    initializeLocalStorageRoute();
  }

  initializeLocalStorageRoute() async {
    dir = await getCacheDirectory();
  }

  _deleteLocal() {
    localNotifier.value = null;
    percentNotifier.value = null;
    dir!.deleteSync(recursive: true);
  }

  _checkOnLocal({
    required String fileUrl,
    required String fileLocalRouteStr,
  }) async {
    debugPrint('_checkOnLocal()...');
    localNotifier.value = '';
    File localFile = File(fileLocalRouteStr);
    String dir = path.dirname(fileLocalRouteStr);
    String basename = path.basenameWithoutExtension(fileLocalRouteStr);
    String extension = path.extension(fileLocalRouteStr);

    String localRouteToSaveFileStr = fileLocalRouteStr;
    // List<int> sizes = [];
    sizes.clear();
    int sumSizes = 0;
    int fileOriginSize = 0;
    bool fullFile = false;

    Response response = await dio.head(fileUrl);
    fileOriginSize = int.parse(response.headers.value('content-length')!);
    String localText = 'fileOriginSize: ${filesize(fileOriginSize)}\n\n';

    bool existsSync = localFile.existsSync();
    if (!existsSync) {
      localText += 'File "$basename$extension" does not exist \nin: "$dir"';
    } else {
      int fileLocalSize = localFile.lengthSync();
      sizes.add(fileLocalSize);
      localText +=
          'localFile: "$basename$extension", fileLocalSize: ${filesize(fileLocalSize)}';

      int i = 1;
      localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
      File f = File(localRouteToSaveFileStr);
      while (f.existsSync()) {
        int tSize = f.lengthSync();
        sizes.add(tSize);
        localText += '\nchunk: "$basename'
            '_$i$extension", fileLocalSize: ${filesize(tSize)}';
        i++;
        localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
        f = File(localRouteToSaveFileStr);
      }

      sumSizes = sizes.fold(0, (p, c) => p + c);

      print('sumSizes: "$sumSizes", sizes: "$sizes"');

      localText +=
          '\n\nsize: ${filesize(sumSizes)}/${filesize(fileOriginSize)}';
      localText += '\nbytes: $sumSizes/$fileOriginSize';
      localText += '\n${(sumSizes / fileOriginSize * 100).toStringAsFixed(2)}%';
      fullFile = sumSizes == fileOriginSize;
    }
    localNotifier.value = localText;
    percentNotifier.value = fullFile ? 1 : sumSizes / fileOriginSize;
  }

  _cancel() {
    cancelToken.cancel();
    percentNotifier.value = null;
    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
  }

  _onReceiveProgress(int received, int total) {
    if (!cancelToken.isCancelled) {
      int sum = sizes.fold(0, (p, c) => p + c);
      received += sum;

      percentNotifier.value = received / total;
      debugPrint(
          'percentNotifier: ${(percentNotifier.value! * 100).toStringAsFixed(2)}');
    } else {
      debugPrint(
          'percentNotifier [AFTER CANCELED]: ${(percentNotifier.value! * 100).toStringAsFixed(2)}');
    }
  }

  _download() {
    localNotifier.value = null;
    percentNotifier.value = 0;
    fileUrl = urlTextEditingCtrl.text;
    fileLocalRouteStr = getLocalCacheFilesRoute(fileUrl, dir!);

    getItemFileWithProgress(
        fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
  }

  Future<File?> getItemFileWithProgress({
    required String fileUrl,
    required String fileLocalRouteStr,
  }) async {
    debugPrint('getItemFileWithProgress()...');

    File localFile = File(fileLocalRouteStr);
    String dir = path.dirname(fileLocalRouteStr);
    String basename = path.basenameWithoutExtension(fileLocalRouteStr);
    String extension = path.extension(fileLocalRouteStr);

    String localRouteToSaveFileStr = fileLocalRouteStr;
    sizes.clear();
    int fileOriginSize = 0;
    Options? options;

    bool existsSync = localFile.existsSync();
    if (existsSync) {
      Response response = await dio.head(fileUrl);
      fileOriginSize = int.parse(response.headers.value('content-length')!);

      int fileLocalSize = localFile.lengthSync();
      sizes.add(fileLocalSize);

      int i = 1;
      localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
      File f = File(localRouteToSaveFileStr);
      while (f.existsSync()) {
        sizes.add(f.lengthSync());
        i++;
        localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
        f = File(localRouteToSaveFileStr);
      }

      int sumSizes = sizes.fold(0, (p, c) => p + c);
      if (sumSizes < fileOriginSize) {
        options = Options(
          headers: {'Range': 'bytes=$sumSizes-'},
        );
      } else {
        percentNotifier.value = 1;

        debugPrint(
            'percentNotifier [ALREADY DOWNLOADED]: ${(percentNotifier.value! * 100).toStringAsFixed(2)}');
        if (sizes.length == 1) {
          debugPrint('percentNotifier [ALREADY DOWNLOADED - ONE FILE]');
          _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
          return localFile;
        }
      }
    }

    if ((percentNotifier.value ?? 0) < 1) {
      if (cancelToken.isCancelled) {
        cancelToken = CancelToken();
      }

      try {
        await dio.download(fileUrl, localRouteToSaveFileStr,
            options: options,
            cancelToken: cancelToken,
            deleteOnError: false,
            onReceiveProgress: (int received, int total) =>
                _onReceiveProgress(received, fileOriginSize));
      } catch (e) {
        debugPrint('..dio.download()...ERROR: "${e.toString()}"');
        return null;
      }
    }

    if (existsSync) {
      debugPrint('[ALREADY DOWNLOADED - MERGING FILES]');
      var raf = await localFile.open(mode: FileMode.writeOnlyAppend);

      int i = 1;
      String filePartLocalRouteStr = '$dir/$basename' '_$i$extension';
      File f = File(filePartLocalRouteStr);
      while (f.existsSync()) {
        raf = await raf.writeFrom(await f.readAsBytes());
        await f.delete();

        i++;
        filePartLocalRouteStr = '$dir/$basename' '_$i$extension';
        f = File(filePartLocalRouteStr);
      }
      await raf.close();
    }

    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
    return localFile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('URL to download'),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
                child: TextField(
                  controller: urlTextEditingCtrl,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  fileUrl = urlTextEditingCtrl.text;
                  fileLocalRouteStr = getLocalCacheFilesRoute(fileUrl, dir!);
                  _checkOnLocal(
                      fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
                },
                child: const Text('Check URL on Local Storage'),
              ),
              const SizedBox(
                height: 8.0,
              ),
              ValueListenableBuilder<double?>(
                  valueListenable: percentNotifier,
                  builder: (context, percent, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: CircularProgressIndicator(
                            value: percent == 0 ? null : percent ?? 100,
                            color: percent != null ? null : Colors.grey,
                          ),
                        ),
                        Text(((percent ?? 0) * 100).toStringAsFixed(2)),
                      ],
                    );
                  }),
              const SizedBox(
                height: 8.0,
              ),
              ValueListenableBuilder<String?>(
                  valueListenable: localNotifier,
                  builder: (context, localData, _) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      color: localData == null ? null : Colors.grey,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: localData == null
                            ? const SizedBox.shrink()
                            : localData.isEmpty
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Column(
                                    children: [
                                      Text(
                                        localData,
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!localData.toLowerCase().contains(
                                              'Does not exist'.toLowerCase()))
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ElevatedButton(
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red),
                                                  onPressed: _deleteLocal,
                                                  child: Row(
                                                    children: const [
                                                      Icon(
                                                          Icons.delete_forever),
                                                      Text('Delete'),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 8.0,
                                                ),
                                              ],
                                            ),
                                          ElevatedButton(
                                            onPressed: () {
                                              localNotifier.value = null;
                                              percentNotifier.value = null;
                                            },
                                            child: Row(
                                              children: const [
                                                Icon(Icons.clear_all),
                                                Text('Clear'),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                      ),
                    );
                  }),
            ],
          ),
        ),
      ),
      floatingActionButton: ValueListenableBuilder<double?>(
          valueListenable: percentNotifier,
          builder: (context, percent, _) {
            return FloatingActionButton(
              onPressed: percent == 0 || percent == 1
                  ? null
                  : percent == null
                      ? _download
                      : localNotifier.value != null ? _download : _cancel,
              tooltip: percent == null ? 'Download' : 'Cancel',
              backgroundColor:
                  percent == 0 || percent == 1 ? Colors.grey : null,
              child: Icon(percent == 0
                  ? Icons.downloading
                  : percent == 1
                      ? Icons.download_done
                      : percent == null
                          ? Icons.download
                          : localNotifier.value != null ? Icons.download : Icons.close),
            );
          }),
    );
  }
}
