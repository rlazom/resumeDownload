import 'dart:io';

import 'package:dio/dio.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:system_info2/system_info2.dart';

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

  // final double maxAvailableMemory = 0.5; // Max limit of available memory
  final double maxAvailableMemory = 0.80; // Max limit of available memory
  final availableCores = Platform.numberOfProcessors;

  int? minSpeed;
  int? maxSpeed;
  List<int> aveSpeedList = [];
  String fileLocalRouteStr = '';
  Dio dio = Dio();
  Directory? dir;
  TextEditingController urlTextEditingCtrl = TextEditingController();

  List<CancelToken> cancelTokenList = [];
  List<DateTime> percentUpdate = [];

  final percentNotifier = ValueNotifier<List<double>?>(null);
  final multipartNotifier = ValueNotifier<bool>(false);
  final localNotifier = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    urlTextEditingCtrl.text = fileUrl;

    initializeLocalStorageRoute();
  }

  initializeLocalStorageRoute() async {
    dir = await getCacheDirectory();
    debugPrint('initState() - dir: "${dir?.path}"');
  }

  _deleteLocal() {
    localNotifier.value = null;
    percentNotifier.value = null;
    dir!.deleteSync(recursive: true);
  }

  _checkOnLocal({
    required String fileUrl,
    required String fileLocalRouteStr,
  }) async {}

  // }) async {
  //   debugPrint('_checkOnLocal()...');
  //   localNotifier.value = '';
  //   File localFile = File(fileLocalRouteStr);
  //   String dir = path.dirname(fileLocalRouteStr);
  //   String basename = path.basenameWithoutExtension(fileLocalRouteStr);
  //   String extension = path.extension(fileLocalRouteStr);
  //
  //   String localRouteToSaveFileStr = fileLocalRouteStr;
  //   sizes.clear();
  //   int sumSizes = 0;
  //   int fileOriginSize = 0;
  //   bool fullFile = false;
  //
  //   Response response = await dio.head(fileUrl);
  //   fileOriginSize = int.parse(response.headers.value('content-length')!);
  //   String localText = 'fileOriginSize: ${filesize(fileOriginSize)}\n\n';
  //
  //   bool existsSync = localFile.existsSync();
  //   if (!existsSync) {
  //     localText += 'File "$basename$extension" does not exist \nin: "$dir"';
  //   } else {
  //     int fileLocalSize = localFile.lengthSync();
  //     sizes.add(fileLocalSize);
  //     localText +=
  //         'localFile: "$basename$extension", fileLocalSize: ${filesize(fileLocalSize)}';
  //
  //     int i = 1;
  //     localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
  //     File f = File(localRouteToSaveFileStr);
  //     while (f.existsSync()) {
  //       int tSize = f.lengthSync();
  //       sizes.add(tSize);
  //       localText += '\nchunk: "$basename'
  //           '_$i$extension", fileLocalSize: ${filesize(tSize)}';
  //       i++;
  //       localRouteToSaveFileStr = '$dir/$basename' '_$i$extension';
  //       f = File(localRouteToSaveFileStr);
  //     }
  //
  //     sumSizes = sizes.fold(0, (p, c) => p + c);
  //     localText +=
  //         '\n\nsize: ${filesize(sumSizes)}/${filesize(fileOriginSize)}';
  //     localText += '\nbytes: $sumSizes/$fileOriginSize';
  //     localText += '\n${(sumSizes / fileOriginSize * 100).toStringAsFixed(2)}%';
  //     fullFile = sumSizes == fileOriginSize;
  //   }
  //   double percent = sumSizes / fileOriginSize;
  //   localNotifier.value = localText;
  //   percentNotifier.value = fullFile
  //       ? 1
  //       : percent == 0
  //           ? null
  //           : percent;
  // }

  _cancel() {
    for (CancelToken cancelToken in cancelTokenList) {
      cancelToken.cancel();
    }

    percentNotifier.value = null;
    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
  }

  _onReceiveProgress(int received, int total, index, sizes) {
    var cancelToken = cancelTokenList.elementAt(index);
    if (!cancelToken.isCancelled) {
      int sum = sizes.fold(0, (p, c) => p + c);
      received += sum;

      var valueOld = total * percentNotifier.value![index];
      DateTime timeOld = percentUpdate[index];

      var valueNew = received / total;
      percentNotifier.value![index] = valueNew;
      DateTime timeNew = DateTime.now();

      final timeDifference = timeNew.difference(timeOld).inMilliseconds / 1000;
      final downloadedSize = received - valueOld;

      percentUpdate[index] = timeNew;
      percentNotifier.notifyListeners();

      if(timeDifference == 0) {
        return;
      }

      String percent = (valueNew * 100).toStringAsFixed(2);
      double speedBytes = downloadedSize / timeDifference;
      int speed = speedBytes.ceil();
      // String speedStr = speed.toStringAsFixed(2);

      aveSpeedList.add(speed);
      if(minSpeed == null || (minSpeed ?? 99999) > speed) {
        minSpeed = speed;
      }
      if(maxSpeed == null || (maxSpeed ?? -1) < speed) {
        maxSpeed = speed;
      }

      debugPrint('_onReceiveProgress(index: "$index")...'
          'percent: "$percent", '
          'speed: "${filesize(speed)} / second"');
    } else {
      debugPrint('_onReceiveProgress(index: "$index")...percentNotifier [AFTER CANCELED]: ${(percentNotifier.value![index] * 100).toStringAsFixed(2)}');
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
    // debugPrint('_getMaxMemoryUsage()...');

    // final totalPhysicalMemory = SysInfo.getTotalPhysicalMemory();
    final freePhysicalMemory = SysInfo.getFreePhysicalMemory();

    // debugPrint('_getMaxMemoryUsage() - totalPhysicalMemory: "$totalPhysicalMemory" - ${filesize(totalPhysicalMemory)}');
    // debugPrint('_getMaxMemoryUsage() - freePhysicalMemory: "$freePhysicalMemory" - ${filesize(freePhysicalMemory)}');

    final maxMemoryUsage = (freePhysicalMemory * maxAvailableMemory).round();
    return maxMemoryUsage;
  }

  int _calculateOptimalMaxParallelDownloads(int fileSize, int maxMemoryUsage) {
    // debugPrint('_calculateOptimalMaxParallelDownloads()...');

    // final maxParallelDownloads = (fileSize / maxMemoryUsage).ceil();
    // final maxParallelDownloads = (maxMemoryUsage / fileSize).ceil();

    // final maxParallelDownloads = (fileSize / maxMemoryUsage).ceil();

    final maxPartSize = (maxMemoryUsage / availableCores).floor();
    final maxParallelDownloads = (fileSize / maxPartSize).ceil();

    final result = maxParallelDownloads > availableCores
        ? availableCores
        : ((maxParallelDownloads + availableCores) / 2).ceil();
        // : ((maxParallelDownloads + availableCores) / 2).floor();

    debugPrint('..maxParallelDownloads: $maxParallelDownloads');
    debugPrint('..availableCores: $availableCores');
    debugPrint('..result: $result');

    return result;
  }

  _download() async {
    DateTime before = DateTime.now();
    debugPrint('_download()...');
    localNotifier.value = null;
    percentNotifier.value = [];
    percentUpdate = [];
    cancelTokenList.clear();
    minSpeed = null;
    maxSpeed = null;
    aveSpeedList.clear();
    fileUrl = urlTextEditingCtrl.text;

    fileLocalRouteStr = getLocalCacheFilesRoute(fileUrl, dir!);
    final File file = File(fileLocalRouteStr);

    final bool fileLocalExists = file.existsSync();
    final int fileLocalSize = fileLocalExists ? file.lengthSync() : 0;
    final int fileOriginSize = await _getOriginFileSize(fileUrl);
    final int maxMemoryUsage = await _getMaxMemoryUsage();

    int optimalMaxParallelDownloads = 1;
    int chunkSize = fileOriginSize;
    if (multipartNotifier.value) {
      optimalMaxParallelDownloads = _calculateOptimalMaxParallelDownloads(fileOriginSize, maxMemoryUsage);
      chunkSize = (chunkSize / optimalMaxParallelDownloads).ceil();
    }
    debugPrint('_download() - fileLocalExists: "$fileLocalExists"');
    debugPrint('_download() - fileLocalSize: "$fileLocalSize" - ${filesize(fileLocalSize)}');
    debugPrint('_download() - fileOriginSize: "$fileOriginSize" - ${filesize(fileOriginSize)}');
    debugPrint('_download() - multipart: "${multipartNotifier.value}"');
    debugPrint('_download() - maxMemoryUsage: "$maxMemoryUsage" - ${filesize(maxMemoryUsage)}');
    debugPrint('_download() - optimalMaxParallelDownloads: "$optimalMaxParallelDownloads"');
    debugPrint('_download() - chunkSize: "$chunkSize" - ${filesize(chunkSize)}');

    if (fileLocalSize < fileOriginSize) {
      String tDir = path.dirname(fileLocalRouteStr);
      String tBasename = path.basenameWithoutExtension(fileLocalRouteStr);

      final tasks = <Future>[];
      List<double> tempNotifier = [];
      for (int i = 0; i < optimalMaxParallelDownloads; i++) {
        tempNotifier.add(0);
        percentNotifier.value = List.from(tempNotifier);
        cancelTokenList.add(CancelToken());
        percentUpdate.add(DateTime.now());
        final start = i * chunkSize;
        var end = (i + 1) * chunkSize - 1;
        if (fileLocalExists && end > fileLocalSize - 1) {
          end = fileLocalSize - 1;
        }

        String fileName = '$tDir/$tBasename' '_$i';
        debugPrint('_download() - fileName: "$fileName", fileOriginChunkSize: "${end - start}", start: "$start", end: "$end", index: "$i"');
        final task = getChunkFileWithProgress(fileUrl: fileUrl, fileLocalRouteStr: fileName, fileOriginChunkSize: end - start, start: start, end: end, index: i);
        tasks.add(task);
      }

      List? results;
      try {
        debugPrint('_download() - TRY await Future.wait(tasks)...');
        results = await Future.wait(tasks);
      } catch (e) {
        debugPrint(
            '_download() - TRY await Future.wait(tasks) - ERROR: "${e.toString()}"');
        return;
      }

      /// WRITE BYTES
      if (results.isNotEmpty) {
        debugPrint('_download() - MERGING...');
        for (File result in results) {
          file.writeAsBytesSync(
            result.readAsBytesSync(),
            mode: FileMode.writeOnlyAppend,
          );
          result.delete();
        }
      }
    } else {
      percentNotifier.value = List.from([1.0]);

      debugPrint('_download() - [ALREADY DOWNLOADED]');
      // if (sizes.length == 1) {
      //   debugPrint('percentNotifier [ALREADY DOWNLOADED - ONE FILE]');
      _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
      // return localFile;
      // }
    }

    if (File(fileLocalRouteStr).existsSync()) {
      debugPrint('_download() - DONE - fileLocalRouteStr: "$fileLocalRouteStr"');
    } else {
      debugPrint('_download() - DONE - NO FILE');
    }
    DateTime after = DateTime.now();
    Duration diff = after.difference(before);
    debugPrint('_download()... DURATION: [${diff.inMilliseconds} milliseconds | ${diff.inSeconds} seconds]');

    int aveSpeed = aveSpeedList.fold(0, (p, c) => p + c);
    if(aveSpeedList.isNotEmpty) {
      aveSpeed = (aveSpeed / aveSpeedList.length).ceil();
      debugPrint('_download()... SPEED: '
          'min: "${filesize(minSpeed)} / second", '
          'max: "${filesize(maxSpeed)} / second", '
          'ave: "${filesize(aveSpeed)} / second"');
    }
  }

  Future<File?> getChunkFileWithProgress({
    required String fileUrl,
    required String fileLocalRouteStr,
    required int fileOriginChunkSize,
    int start = 0,
    int? end,
    int index = 0,
  }) async {
    // debugPrint('getChunkFileWithProgress(index: "$index")...');

    File localFile = File(fileLocalRouteStr);
    String dir = path.dirname(fileLocalRouteStr);
    String basename = path.basenameWithoutExtension(fileLocalRouteStr);
    // String extension = path.extension(fileLocalRouteStr);

    debugPrint(
        'getChunkFileWithProgress(index: "$index") - basename: "$basename"...');
    String localRouteToSaveFileStr = fileLocalRouteStr;
    List<int> sizes = [];

    // int fileOriginSize = await _getOriginFileSize(fileUrl);
    // Options? options;
    Options options = Options(
      headers: {'Range': 'bytes=$start-$end'},
    );

    bool existsSync = localFile.existsSync();
    // int chunkSize = ;

    debugPrint(
        'getChunkFileWithProgress(index: "$index") - existsChunk: "$existsSync');
    if (existsSync) {
      int fileLocalSize = localFile.lengthSync();
      debugPrint(
          'getChunkFileWithProgress(index: "$index") - existsChunk: "$basename'
          '_0.part", fileLocalSize: "$fileLocalSize" - ${filesize(fileLocalSize)}');
      sizes.add(fileLocalSize);

      int i = 1;
      localRouteToSaveFileStr = '$dir/$basename' '_$i.part';
      File f = File(localRouteToSaveFileStr);
      while (f.existsSync()) {
        int chunkSize = f.lengthSync();
        debugPrint(
            'getChunkFileWithProgress(index: "$index") - existsChunk: "$basename'
            '_$i.part", chunkSize: "$chunkSize" - ${filesize(chunkSize)}');
        sizes.add(chunkSize);
        i++;
        localRouteToSaveFileStr = '$dir/$basename' '_$i.part';
        f = File(localRouteToSaveFileStr);
      }

      debugPrint(
          'getChunkFileWithProgress(index: "$index") - CREATING Chunk: "$basename'
          '_$i.part"');
      int sumSizes = sizes.fold(0, (p, c) => p + c);
      if (sumSizes < fileOriginChunkSize) {
        int starBytes = start + sumSizes;
        debugPrint(
            'getChunkFileWithProgress(index: "$index") - FETCH Options: sumSizes: "$sumSizes", start: "$start", end: "$end"');
        debugPrint(
            'getChunkFileWithProgress(index: "$index") - FETCH Options: "bytes=$starBytes-$end"');
        options = Options(
          // headers: {'Range': 'bytes=$sumSizes-'},
          headers: {'Range': 'bytes=${start + sumSizes}-$end'},
        );
      } else {
        percentNotifier.value![index] = 1;

        debugPrint(
            'percentNotifier [ALREADY DOWNLOADED]: ${(percentNotifier.value![index] * 100).toStringAsFixed(2)}');
        if (sizes.length == 1) {
          debugPrint('percentNotifier [ALREADY DOWNLOADED - ONE FILE]');
          _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
          return localFile;
        }
      }
    }

    if ((percentNotifier.value?[index] ?? 0) < 1) {
      CancelToken cancelToken = cancelTokenList.elementAt(index);
      if (cancelToken.isCancelled) {
        cancelToken = CancelToken();
      }

      try {
        debugPrint(
            'getChunkFileWithProgress(index: "$index") - TRY dio.download()...');
        await dio.download(fileUrl, localRouteToSaveFileStr,
            options: options,
            cancelToken: cancelToken,
            deleteOnError: false,
            onReceiveProgress: (int received, int total) => _onReceiveProgress(
                received, fileOriginChunkSize, index, sizes));
      } catch (e) {
        debugPrint(
            'getChunkFileWithProgress(index: "$index") - TRY dio.download() - ERROR: "${e.toString()}"');
        // return null;
        rethrow;
      }
    }

    if (existsSync) {
      debugPrint(
          'getChunkFileWithProgress(index: "$index") - [CHUNKS DOWNLOADED - MERGING FILES]');
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
    debugPrint('getChunkFileWithProgress(index: "$index") - RETURN FILE: "$basename"');
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
              ValueListenableBuilder<bool>(
                  valueListenable: multipartNotifier,
                  builder: (context, isMultipart, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Multipart Download'),
                        Switch(
                          value: isMultipart,
                          activeColor: Colors.green,
                          onChanged: (bool value) {
                            multipartNotifier.value = value;
                          },
                        ),
                      ],
                    );
                  }),
              spaceWdt,
              ValueListenableBuilder<bool>(
                  valueListenable: multipartNotifier,
                  builder: (context, isMultipart, _) {
                    return ValueListenableBuilder<List<double>?>(
                        valueListenable: percentNotifier,
                        builder: (context, percentList, _) {
                          double? totalPercent =
                              percentList?.fold(0, (p, c) => p! + c);
                          totalPercent = totalPercent ?? 0;
                          totalPercent =
                              totalPercent > 1.0 ? 1.0 : totalPercent;

                          if (isMultipart) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$totalPercent'),
                                  spaceWdt,
                                  Row(
                                    children: percentList
                                            ?.map(
                                              (e) => Expanded(
                                                child: Column(
                                                  children: [
                                                    LinearProgressIndicator(value: e),
                                                    Text(e.toStringAsFixed(2)),
                                                  ],
                                                ),
                                              ),
                                            )
                                            .toList() ??
                                        [
                                          const Expanded(
                                            child: LinearProgressIndicator(
                                              value: 1,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                  ),
                                ],
                              ),
                            );
                          } else {
                            final double? percent = percentList?.isEmpty == true
                                ? null
                                : percentList?.first;
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
                  }),
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
            double? percent = percentList?.fold(0, (p, c) => p! + c);
            percent = percent == null ? null : percent / (percentList?.length ?? 1);
            percent = (percent ?? 0) > 1.0 ? 1.0 : percent;

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
