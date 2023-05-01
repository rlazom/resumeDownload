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

  final double maxAvailableMemory = 0.5; // Max limit of available memory
  final availableCores = Platform.numberOfProcessors;

  String fileLocalRouteStr = '';
  Dio dio = Dio();
  Directory? dir;
  TextEditingController urlTextEditingCtrl = TextEditingController();
  CancelToken cancelToken = CancelToken();

  // final percentNotifier = ValueNotifier<double?>(null);
  final percentNotifier = ValueNotifier<List<double>?>(null);
  final multipartNotifier = ValueNotifier<bool>(false);
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
      localText +=
          '\n\nsize: ${filesize(sumSizes)}/${filesize(fileOriginSize)}';
      localText += '\nbytes: $sumSizes/$fileOriginSize';
      localText += '\n${(sumSizes / fileOriginSize * 100).toStringAsFixed(2)}%';
      fullFile = sumSizes == fileOriginSize;
    }
    double percent = sumSizes / fileOriginSize;
    localNotifier.value = localText;
    percentNotifier.value = fullFile
        ? 1
        : percent == 0
            ? null
            : percent;
  }

  _cancel() {
    cancelToken.cancel();
    percentNotifier.value = null;
    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
  }

  _onReceiveProgress(int received, int total, {index = 0}) {
    if (!cancelToken.isCancelled) {
      int sum = sizes.fold(0, (p, c) => p + c);
      received += sum;

      percentNotifier.value![index] = received / total;
      debugPrint(
          'percentNotifier: ${(percentNotifier.value![index] * 100).toStringAsFixed(2)}');
    } else {
      debugPrint(
          'percentNotifier [AFTER CANCELED]: ${(percentNotifier.value![index] * 100).toStringAsFixed(2)}');
    }
  }

  Future<int> _getOriginFileSize(String url) async {
    int fileOriginSize = 0;

    /// GET ORIGIN FILE SIZE - BEGIN
    Response response = await dio.head(url);
    fileOriginSize = int.parse(response.headers.value('content-length')!);

    /// ANOTHER WAY WITH HTTP
    // final httpClient = HttpClient();
    // final request = await httpClient.getUrl(Uri.parse(url));
    // final response2 = await request.close();
    // fileOriginSize = response2.contentLength;
    /// GET ORIGIN FILE SIZE - END

    return fileOriginSize;
  }

  Future<int> _getMaxMemoryUsage() async {
    final sysInfo = await Process.run('sysctl', ['-n', 'hw.memsize']);
    final memorySize = int.parse(sysInfo.stdout.toString().trim());
    final maxMemoryUsage = (memorySize * maxAvailableMemory).round();
    return maxMemoryUsage;
  }

  int _calculateOptimalMaxParallelDownloads(int fileSize, int maxMemoryUsage) {
    final maxParallelDownloads = (fileSize / maxMemoryUsage).ceil();
    return maxParallelDownloads > availableCores
        ? availableCores
        : maxParallelDownloads;
  }

  _download() async {
    localNotifier.value = null;
    percentNotifier.value = [0];
    fileUrl = urlTextEditingCtrl.text;

    fileLocalRouteStr = getLocalCacheFilesRoute(fileUrl, dir!);
    final File file = File(fileLocalRouteStr);

    final int fileOriginSize = await _getOriginFileSize(fileUrl);
    final int maxMemoryUsage = await _getMaxMemoryUsage();

    int optimalMaxParallelDownloads = 1;
    int chunkSize = fileOriginSize;
    if(multipartNotifier.value) {
      optimalMaxParallelDownloads = _calculateOptimalMaxParallelDownloads(fileOriginSize, maxMemoryUsage);
      chunkSize = (file.lengthSync() / optimalMaxParallelDownloads).ceil();
    }

    String tDir = path.dirname(fileLocalRouteStr);
    String tBasename = path.basenameWithoutExtension(fileLocalRouteStr);

    final tasks = <Future>[];
    for(int i = 0; i < optimalMaxParallelDownloads; i++) {
      final start = i * chunkSize;
      var end = (i + 1) * chunkSize - 1;
      if (end > file.lengthSync() - 1) {
        end = file.lengthSync() - 1;
      }

      String fileName = '$tDir/$tBasename' '_$i';
      final task = getChunkFileWithProgress(fileUrl: fileUrl, fileLocalRouteStr: fileName, fileOriginSize: fileOriginSize, start: start, end: end,);
      tasks.add(task);
    }
    final results = await Future.wait(tasks);

    /// WRITE BYTES
    for (File result in results) {
      file.writeAsBytesSync(result.readAsBytesSync(), mode: FileMode.writeOnlyAppend,);
    }
  }

  Future<File?> getChunkFileWithProgress({
    required String fileUrl,
    required String fileLocalRouteStr,
    required int fileOriginSize,
    int? start,
    int? end,
  }) async {
    debugPrint('getChunkFileWithProgress()...');

    File localFile = File(fileLocalRouteStr);
    String dir = path.dirname(fileLocalRouteStr);
    String basename = path.basenameWithoutExtension(fileLocalRouteStr);
    // String extension = path.extension(fileLocalRouteStr);

    String localRouteToSaveFileStr = fileLocalRouteStr;
    sizes.clear();

    // int fileOriginSize = await _getOriginFileSize(fileUrl);
    Options? options;
    bool existsSync = localFile.existsSync();
    if (existsSync) {
      int fileLocalSize = localFile.lengthSync();
      sizes.add(fileLocalSize);

      int i = 1;
      // localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
      localRouteToSaveFileStr = '$dir/$basename' '_$i.part';
      File f = File(localRouteToSaveFileStr);
      while (f.existsSync()) {
        sizes.add(f.lengthSync());
        i++;
        // localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
        localRouteToSaveFileStr = '$dir/$basename' '_$i.part';
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
      // String filePartLocalRouteStr = '$dir/$basename' '_$i$extension';
      String filePartLocalRouteStr = '$dir/$basename' '_$i.part';
      File f = File(filePartLocalRouteStr);
      while (f.existsSync()) {
        raf = await raf.writeFrom(await f.readAsBytes());
        await f.delete();

        i++;
        // filePartLocalRouteStr = '$dir/$basename' '_$i$extension';
        filePartLocalRouteStr = '$dir/$basename' '_$i.part';
        f = File(filePartLocalRouteStr);
      }
      await raf.close();
    }

    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
    return localFile;
  }

  @override
  Widget build(BuildContext context) {
    const SizedBox spaceWdt = SizedBox(
      height: 8.0,
    );

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
              spaceWdt,
              Switch(
                value: multipartNotifier.value,
                activeColor: Colors.green,
                onChanged: (bool value) {
                  multipartNotifier.value = value;
                },
              ),
              SwitchListTile(
                tileColor: Colors.green,
                title: const Text('Multipart Download'),
                value: multipartNotifier.value,
                onChanged:(bool? value) => multipartNotifier.value,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: multipartNotifier,
                builder: (context, isMultipart, _) {
                  return ValueListenableBuilder<List<double>?>(
                      valueListenable: percentNotifier,
                      builder: (context, percentList, _) {
                        if(isMultipart) {
                          return Container();
                        } else {
                          final double? percent = percentList?.first;
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
                        }
                      });
                }
              ),
              spaceWdt,
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
                                                spaceWdt,
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
      floatingActionButton: ValueListenableBuilder<List<double>?>(
          valueListenable: percentNotifier,
          builder: (context, percentList, _) {
            final double? percent = percentList?.fold(0, (p, c) => p! + c);

            return FloatingActionButton(
              onPressed: percent == 0 || percent == 1
                  ? null
                  : percent == null
                      ? _download
                      : localNotifier.value != null
                          ? _download
                          : _cancel,
              tooltip: percent == null ? 'Download' : 'Cancel',
              backgroundColor:
                  percent == 0 || percent == 1 ? Colors.grey : null,
              child: Icon(percent == 0
                  ? Icons.downloading
                  : percent == 1
                      ? Icons.download_done
                      : percent == null
                          ? Icons.download
                          : localNotifier.value != null
                              ? Icons.download
                              : Icons.close),
            );
          }),
    );
  }
}
