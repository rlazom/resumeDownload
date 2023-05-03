import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'dart:io' as io;
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
  static const noFilesStr = 'No Files';

  // final double maxAvailableMemory = 0.5; // Max limit of available memory
  final double maxAvailableMemory = 0.80; // Max limit of available memory
  final availableCores = Platform.numberOfProcessors;

  DateTime? before;
  int? minSpeed;
  int? maxSpeed;
  int sumPrevSize = 0;

  // List<int> aveSpeedList = [];
  String fileLocalRouteStr = '';
  Dio dio = Dio();
  Directory? dir;
  TextEditingController urlTextEditingCtrl = TextEditingController();

  List<CancelToken> cancelTokenList = [];
  List<DateTime> percentUpdate = [];

  // final percentNotifier = ValueNotifier<List<double>?>(null);
  final percentTotalNotifier = ValueNotifier<double?>(null);
  final percentNotifier = ValueNotifier<List<ValueNotifier<double?>>?>(null);
  final speedNotifier = ValueNotifier<double?>(null);
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

  _checkOnLocal({
    required String fileUrl,
    required String fileLocalRouteStr,
  }) async {
    debugPrint('_checkOnLocal()...');
    List<FileSystemEntity>? files;
    localNotifier.value = '';
    String dir = path.dirname(fileLocalRouteStr);
    int sumSizes = 0;

    debugPrint('_checkOnLocal() - _getOriginFileSize()...');
    int? fileOriginSize = await _getOriginFileSize(fileUrl);
    String localText = 'fileOriginSize: ${filesize(fileOriginSize)}\n';
    debugPrint('_checkOnLocal() - fileOriginSize:"${filesize(fileOriginSize)}"');

    if(fileOriginSize == null) {
      localText = 'fileOriginSize: -\n';
      localNotifier.value = localText;
      return;
    }

    final localDir = Directory(dir);
    final localDirExists = localDir.existsSync();
    debugPrint('_checkOnLocal() - localDirExists:"$localDirExists"');
    if (localDirExists) {
      files = localDir.listSync(
        recursive: true,
        followLinks: false,
      );

      if (files.isEmpty) {
        localText += '\n$noFilesStr\n';
      } else {
        files.sort((a, b) => a.path.compareTo(b.path));
        for (FileSystemEntity file in files) {
          if (file is File) {
            String filepath = file.path;
            int tSize = file.lengthSync();
            sumSizes += tSize;

            String basename = path.basename(filepath);
            if(basename.startsWith('_')) {
              String value = file.readAsStringSync();
              localText += '\nFile: "$basename", Value: $value';
            } else {
              localText += '\nFile: "$basename", Size: ${filesize(tSize)}';
            }
          }
        }

        localText += '\n\nSize: ${filesize(sumSizes)}/${filesize(fileOriginSize)}';
        localText += '\nBytes: $sumSizes/$fileOriginSize';
        localText += '\n${(sumSizes / fileOriginSize * 100).toStringAsFixed(2)}%';
      }
    }

    if (files == null || files.isEmpty == true) {
      localText += '\n$noFilesStr\n';
    }
    localNotifier.value = localText;
  }

  _deleteLocal() {
    localNotifier.value = null;
    percentNotifier.value = null;
    percentTotalNotifier.value = null;
    speedNotifier.value = null;
    sumPrevSize = 0;
    dir!.deleteSync(recursive: true);
  }

  _cancel() {
    for (CancelToken cancelToken in cancelTokenList) {
      cancelToken.cancel();
    }

    percentTotalNotifier.value = null;
    percentNotifier.value = null;
    speedNotifier.value = null;

    var dir = path.dirname(fileLocalRouteStr);
    int sumSizes = 0;
    final localDir = Directory(dir);

    if (localDir.existsSync()) {
      List<FileSystemEntity> files = localDir.listSync(
        recursive: true,
        followLinks: false,
      );

      for (FileSystemEntity file in files) {
        if (file is File) {
          sumSizes += file.lengthSync();
        }
      }
    }
    sumPrevSize = sumSizes;

    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
  }

  Future<int?> _getOriginFileSize(String url) async {
    int fileOriginSize = 0;

    /// GET ORIGIN FILE SIZE - BEGIN
    Response response = await dio.head(url, options: Options()).timeout(const Duration(seconds: 20));
    try {
      response = await dio.head(url);
    } on io.SocketException catch (_) {
      debugPrint('_getOriginFileSize() - TRY dio.head() - ERROR: - SocketException');
      return null;
    } on TimeoutException catch (_) {
      debugPrint('_getOriginFileSize() - TRY dio.head() - ERROR:  - TimeoutException');
      return null;
    } catch (e) {
      debugPrint('_getOriginFileSize() - TRY dio.head() - ERROR: "${e.toString()}"');
      return null;
      // rethrow;
    }

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
        : ((maxParallelDownloads + availableCores) / 2).floor();
        // : ((maxParallelDownloads + availableCores) / 2).ceil();

    // debugPrint('..maxParallelDownloads: $maxParallelDownloads');
    // debugPrint('..availableCores: $availableCores');
    // debugPrint('..result: $result');

    return result;
  }

  _onReceiveProgress(int received, int total, index, sizes) {
    // debugPrint('_onReceiveProgress(index: "$index")... received: "$received", total: "$total"');
    var cancelToken = cancelTokenList.elementAt(index);
    if (!cancelToken.isCancelled) {
      int sum = sizes.fold(0, (p, c) => p + c);
      received += sum;

      var valueNew = received / total;
      percentNotifier.value?[index].value = valueNew;

      DateTime timeOld = percentUpdate[index];
      DateTime timeNew = DateTime.now();
      percentUpdate[index] = timeNew;
      final timeDifference = timeNew.difference(timeOld).inMilliseconds / 1000;

      List? percentList = percentNotifier.value;
      double? totalPercent = percentList?.fold(0, (p, c) => (p ?? 0) + (c.value ?? 0));
      totalPercent = totalPercent == null ? null : totalPercent / (percentList?.length ?? 1);
      totalPercent = (totalPercent ?? 0) > 1.0 ? 1.0 : totalPercent;
      percentTotalNotifier.value = totalPercent;

      if (timeDifference == 0) {
        return;
      }

      //////////////////////////////////////////////////////////////////////////
      var dir = path.dirname(fileLocalRouteStr);
      int sumSizes = 0;
      final localDir = Directory(dir);

      if (localDir.existsSync()) {
        List<FileSystemEntity> files = localDir.listSync(
          recursive: true,
          followLinks: false,
        );

        for (FileSystemEntity file in files) {
          if (file is File) {
            sumSizes += file.lengthSync();
          }
        }
      }

      final totalElapsed = DateTime.now().millisecondsSinceEpoch - before!.millisecondsSinceEpoch;
      /// CONVERT TO SECONDS AND GET THE SPEED IN BYTES PER SECOND
      // final totalSpeed = (sumSize ?? 0) / totalElapsed * 1000;
      final totalSpeed = (sumSizes-sumPrevSize) / totalElapsed * 1000;

      speedNotifier.value = totalSpeed;
      //////////////////////////////////////////////////////////////////////////
      String percent = (valueNew * 100).toStringAsFixed(2);
      int speed = speedNotifier.value?.ceil() ?? 0;

      if (minSpeed == null || (minSpeed ?? 99999) > speed) {
        minSpeed = speed.round();
      }
      if (maxSpeed == null || (maxSpeed ?? -1) < speed) {
        maxSpeed = speed.round();
      }

      debugPrint('_onReceiveProgress(index: "$index")...'
          'percent: "$percent", '
          'speed: "${filesize(speed)} / second"');
    } else {
      // debugPrint('_onReceiveProgress(index: "$index")...percentNotifier [AFTER CANCELED]: ${(percentNotifier.value![index] * 100).toStringAsFixed(2)}');
      debugPrint('_onReceiveProgress(index: "$index")...percentNotifier [AFTER CANCELED]: ${(percentNotifier.value![index].value! * 100).toStringAsFixed(2)}');
    }
  }

  _download() async {
    before = DateTime.now();
    debugPrint('_download()...');
    localNotifier.value = null;
    percentNotifier.value = [];
    percentTotalNotifier.value = 0;
    percentUpdate = [];
    cancelTokenList.clear();
    speedNotifier.value = null;
    minSpeed = null;
    maxSpeed = null;
    fileUrl = urlTextEditingCtrl.text;

    fileLocalRouteStr = getLocalCacheFilesRoute(fileUrl, dir!);
    final File file = File(fileLocalRouteStr);

    String fileBasename = path.basename(fileLocalRouteStr);
    String fileDir = path.dirname(fileLocalRouteStr);
    final bool fileLocalExists = file.existsSync();
    final int fileLocalSize = fileLocalExists ? file.lengthSync() : 0;
    final int? fileOriginSize = await _getOriginFileSize(fileUrl);
    final int maxMemoryUsage = await _getMaxMemoryUsage();

    if(fileOriginSize == null) {
      _cancel();
      return;
    }

    int optimalMaxParallelDownloads = 1;
    int chunkSize = fileOriginSize;
    if (multipartNotifier.value) {
      optimalMaxParallelDownloads = _calculateOptimalMaxParallelDownloads(fileOriginSize, maxMemoryUsage);
      chunkSize = (chunkSize / optimalMaxParallelDownloads).ceil();

      File chunkSizeFile = File('$fileDir/_chunkSize');
      if(!chunkSizeFile.existsSync()) {
        debugPrint('_download() - Creating chunkSizeFile...');
        chunkSizeFile.createSync(recursive: true);
        chunkSizeFile.writeAsStringSync(chunkSize.toString());
        debugPrint('_download() - Creating chunkSizeFile... DONE');
      } else {
        debugPrint('_download() - Reading chunkSize from chunkSizeFile...');
        chunkSize = int.parse(chunkSizeFile.readAsStringSync());
      }

      File optimalMaxParallelDownloadsFile = File('$fileDir/_maxParallelDownloads');
      if(!optimalMaxParallelDownloadsFile.existsSync()) {
        debugPrint('_download() - Creating optimalMaxParallelDownloadsFile...');
        optimalMaxParallelDownloadsFile.createSync(recursive: true);
        optimalMaxParallelDownloadsFile.writeAsStringSync(optimalMaxParallelDownloads.toString());
        debugPrint('_download() - Creating optimalMaxParallelDownloadsFile... DONE');
      } else {
        debugPrint('_download() - Reading optimalMaxParallelDownloads from optimalMaxParallelDownloadsFile...');
        optimalMaxParallelDownloads = int.parse(optimalMaxParallelDownloadsFile.readAsStringSync());
      }
    }

    debugPrint('_download() - fileBasename: "$fileBasename"');
    debugPrint('_download() - fileDir: "$fileDir"');
    debugPrint('_download() - fileLocalExists: "$fileLocalExists"');
    debugPrint('_download() - fileLocalSize: "$fileLocalSize" (${filesize(fileLocalSize)})');
    debugPrint('_download() - fileOriginSize: "$fileOriginSize" (${filesize(fileOriginSize)})');
    debugPrint('_download() - multipart: "${multipartNotifier.value}"');
    debugPrint('_download() - maxMemoryUsage: "$maxMemoryUsage" (${filesize(maxMemoryUsage)})');
    debugPrint('_download() - optimalMaxParallelDownloads: "$optimalMaxParallelDownloads"');
    debugPrint('_download() - chunkSize: "$chunkSize" (${filesize(chunkSize)})');

    if (fileLocalSize < fileOriginSize) {
      String tBasename = path.basenameWithoutExtension(fileLocalRouteStr);

      final List<Future> tasks = [];
      List<ValueNotifier<double?>> tempNotifier = [];
      for (int i = 0; i < optimalMaxParallelDownloads; i++) {
        tempNotifier.add(ValueNotifier<double?>(null));
        percentNotifier.value = List.from(tempNotifier);
        cancelTokenList.add(CancelToken());
        percentUpdate.add(DateTime.now());
        final start = i * chunkSize;
        var end = (i + 1) * chunkSize - 1;
        if (fileLocalExists && end > fileLocalSize - 1) {
          end = fileLocalSize - 1;
        }

        String fileName = '$fileDir/$tBasename' '_$i';
        debugPrint('_download() - [index: "$i"] - fileName: "${path.basename(fileName)}", fileOriginChunkSize: "${end - start}", start: "$start", end: "$end"');
        final Future<File?> task = getChunkFileWithProgress(
            fileUrl: fileUrl,
            fileLocalRouteStr: fileName,
            fileOriginChunkSize: end - start,
            start: start,
            end: end,
            index: i);
        tasks.add(task);
      }

      List? results;
      try {
        debugPrint('_download() - TRY await Future.wait(tasks)...');
        results = await Future.wait(tasks);
      } catch (e) {
        debugPrint('_download() - TRY await Future.wait(tasks) - ERROR: "${e.toString()}"');
        return;
      }
      debugPrint('_download() - TRY await Future.wait(tasks)...DONE');

      /// WRITE BYTES
      if (results.isNotEmpty) {
        debugPrint('_download() - MERGING...');
        for (File result in results) {
          debugPrint('_download() - MERGING - file: "${path.basename(result.path)}"...');
          file.writeAsBytesSync(
            result.readAsBytesSync(),
            mode: FileMode.writeOnlyAppend,
          );
          result.delete();
        }
        debugPrint('_download() - MERGING...DONE');
      }
    } else {
      percentNotifier.value = List.from([ValueNotifier<double>(1.0)]);
      debugPrint('_download() - [ALREADY DOWNLOADED]');
    }

    if (file.existsSync()) {
      debugPrint('_download() - DONE - fileLocalRouteStr: "$fileLocalRouteStr"');
    } else {
      debugPrint('_download() - DONE - NO FILE');
    }
    DateTime after = DateTime.now();
    Duration diff = after.difference(before!);
    debugPrint('_download()... DURATION: \n'
        '${diff.inSeconds} seconds \n'
        '${diff.inMilliseconds} milliseconds');

    debugPrint('_download()... SPEED: '
        'min: "${filesize(minSpeed ?? 0)} / second", '
        'max: "${filesize(maxSpeed ?? 0)} / second" ');

    final totalElapsed = after.millisecondsSinceEpoch - before!.millisecondsSinceEpoch;

    /// CONVERT TO SECONDS AND GET THE SPEED IN BYTES PER SECOND
    final totalSpeed = file.lengthSync() / totalElapsed * 1000;
    debugPrint('_download()... SPEED: \n${filesize(totalSpeed.round())}ps');
    _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
  }

  Future<File?> getChunkFileWithProgress({
    required String fileUrl,
    required String fileLocalRouteStr,
    required int fileOriginChunkSize,
    int start = 0,
    int? end,
    int index = 0,
  }) async {
    debugPrint('getChunkFileWithProgress(index: "$index")...');

    File localFile = File(fileLocalRouteStr);
    String dir = path.dirname(fileLocalRouteStr);
    String basename = path.basenameWithoutExtension(fileLocalRouteStr);

    debugPrint('getChunkFileWithProgress(index: "$index") - basename: "$basename"...');
    String localRouteToSaveFileStr = fileLocalRouteStr;
    List<int> sizes = [];
    Options options = Options(
      headers: {'Range': 'bytes=$start-$end'},
    );

    bool existsSync = localFile.existsSync();
    debugPrint('getChunkFileWithProgress(index: "$index") - existsChunk: "$existsSync');
    if (existsSync) {
      int fileLocalSize = localFile.lengthSync();
      debugPrint('getChunkFileWithProgress(index: "$index") - existsChunk: "$basename", fileLocalSize: "$fileLocalSize" - ${filesize(fileLocalSize)}');
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

      int sumSizes = sizes.fold(0, (p, c) => p + c);
      if (sumSizes < fileOriginChunkSize) {
        debugPrint('getChunkFileWithProgress(index: "$index") - CREATING Chunk: "$basename''_$i.part"');
        int starBytes = start + sumSizes;
        debugPrint('getChunkFileWithProgress(index: "$index") - FETCH Options: sumSizes: "$sumSizes", start: "$start", end: "$end"');
        debugPrint('getChunkFileWithProgress(index: "$index") - FETCH Options: "bytes=$starBytes-$end"');
        options = Options(
          headers: {'Range': 'bytes=${start + sumSizes}-$end'},
        );
      } else {
        // List tempList = percentNotifier.value!;
        // tempList[index] = 1.0;
        // percentNotifier.value = List.from(tempList);
        // percentNotifier.notifyListeners();

        percentNotifier.value![index].value = 1.0;

        debugPrint('getChunkFileWithProgress(index: "$index") - [ALREADY DOWNLOADED]');
        if (sizes.length == 1) {
          debugPrint('getChunkFileWithProgress(index: "$index") - [ALREADY DOWNLOADED - ONE FILE]');
          // _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
          return localFile;
        }
      }
    }

    // if ((percentNotifier.value?[index] ?? 0) < 1) {
    if ((percentNotifier.value?[index].value ?? 0) < 1) {
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
            onReceiveProgress: (int received, int total) => _onReceiveProgress(received, fileOriginChunkSize, index, sizes));
      } catch (e) {
        debugPrint(
            'getChunkFileWithProgress(index: "$index") - TRY dio.download() - ERROR: "${e.toString()}"');
        // return null;
        rethrow;
      }
    }

    if (existsSync) {
      debugPrint('getChunkFileWithProgress(index: "$index") - CHUNKS DOWNLOADED - MERGING FILES...');
      var raf = await localFile.open(mode: FileMode.writeOnlyAppend);

      int i = 1;
      String filePartLocalRouteStr = '$dir/$basename' '_$i.part';
      File f = File(filePartLocalRouteStr);
      while (f.existsSync()) {
        // raf = await raf.writeFrom(await f.readAsBytes());
        await raf.writeFrom(await f.readAsBytes());
        await f.delete();

        i++;
        filePartLocalRouteStr = '$dir/$basename' '_$i.part';
        f = File(filePartLocalRouteStr);
      }
      await raf.close();
    }

    // _checkOnLocal(fileUrl: fileUrl, fileLocalRouteStr: fileLocalRouteStr);
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
      body: Stack(
        children: [
          Center(
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
                        // return ValueListenableBuilder<List<double>?>(
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ValueListenableBuilder<List<ValueNotifier<double?>>?>(
                                  valueListenable: percentNotifier,
                                  builder: (context, percentList, _) {
                                    // double? totalPercent = percentList?.fold(0, (p, c) => p! + c);
                                    double? totalPercent = percentList?.fold(0, (p, c) => (p ?? 0) + (c.value ?? 0));
                                    totalPercent = totalPercent ?? 0;
                                    if (percentList != null && percentList.isNotEmpty) {
                                      totalPercent = totalPercent / percentList.length;
                                    }
                                    totalPercent = (totalPercent > 1.0 ? 1.0 : totalPercent) * 100;

                                    if (isMultipart) {
                                      return Padding(
                                        // padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                        padding: const EdgeInsets.symmetric(horizontal: 0.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(totalPercent.toStringAsFixed(2)),
                                            spaceWdt,
                                            Row(
                                              children: (percentList?.isEmpty == true
                                                      ? [
                                                          const Expanded(
                                                            child: LinearProgressIndicator(),
                                                          )
                                                        ]
                                                      : percentList
                                                          ?.map(
                                                            (e) => Expanded(
                                                              child: ValueListenableBuilder<double?>(
                                                                valueListenable: e,
                                                                builder: (context, progress, _) {
                                                                  return Column(
                                                                    children: [
                                                                      LinearProgressIndicator(
                                                                        value: progress,
                                                                        color: (progress ?? 0) > 0.99
                                                                            ? Colors.green
                                                                            : null,
                                                                      ),
                                                                      Text((progress ?? 0).toStringAsFixed(2)),
                                                                    ],
                                                                  );
                                                                }
                                                              ),
                                                            ),
                                                          ).toList()) ?? [],
                                            ),
                                          ],
                                        ),
                                      );
                                    } else {
                                      if(percentList == null || percentList.isEmpty == true) {
                                        return Stack(
                                          alignment: Alignment.center,
                                          children: const [
                                            SizedBox(
                                              width: 60,
                                              height: 60,
                                              child: CircularProgressIndicator(
                                                value: 100,
                                                // color: Colors.grey,
                                                color: Colors.transparent,
                                              ),
                                            ),
                                            Text('0.00'),
                                          ],
                                        );
                                      }
                                      return ValueListenableBuilder<double?>(
                                        valueListenable: percentList.first,
                                        builder: (context, percent, _) {
                                          return Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SizedBox(
                                                width: 60,
                                                height: 60,
                                                child: CircularProgressIndicator(
                                                  value: percent == 0 ? null : percent,
                                                ),
                                              ),
                                              Text(((percent ?? 0) * 100).toStringAsFixed(2)),
                                            ],
                                          );
                                        }
                                      );
                                    }
                                  }),
                              ValueListenableBuilder<double?>(
                                valueListenable: percentTotalNotifier,
                                builder: (context, percent, _) {
                                  if(percent == 0 || percent == 1 || percent != null) {
                                    return const SizedBox.shrink();
                                  }
                                  return LayoutBuilder(
                                      builder: (context, constraints) {
                                        const double tWidth = 64;
                                        return AnimatedPadding(
                                          duration: const Duration(milliseconds: 250),
                                          padding: EdgeInsets.only(top: isMultipart ? 24.0 : 0),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 250),
                                            width: isMultipart ? constraints.maxWidth : tWidth,
                                            height: isMultipart ? 4 : tWidth,
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Colors.grey,
                                                // color: Colors.red,
                                                width: 4.0,
                                              ),
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(isMultipart ? 0 : 100),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                  );
                                }
                              ),
                            ],
                          ),
                        );
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
                                                  noFilesStr.toLowerCase()))
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
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(16),
                  )
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, color: Colors.white),
                      const SizedBox(width: 4.0,),
                      ValueListenableBuilder<double?>(
                        valueListenable: speedNotifier,
                        builder: (context, speed, _) {
                          return Text(speed == null ? 'Speed' : '${filesize(speed.round())}ps', style: TextStyle(color: speed == null ? Colors.white54 : Colors.white),);
                        }
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<double?>(
          valueListenable: percentTotalNotifier,
          builder: (context, percent, _) {
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
