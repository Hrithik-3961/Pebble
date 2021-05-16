import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:audiofileplayer/audiofileplayer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pebble/file_entity_list_tile.dart';
import 'package:pebble/wav_header.dart';
import 'package:slide_popup_dialog/slide_popup_dialog.dart';
import 'package:super_easy_permissions/super_easy_permissions.dart';

enum RecordState { stopped, recording }

class DetailPage extends StatefulWidget {
  final BluetoothDevice server;

  const DetailPage({this.server});

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  //BluetoothConnection connection;
  List<BluetoothService> services;
  List<BluetoothCharacteristic> characteristics;

  int timeElapsed = 0;

  bool isConnecting = true;

  bool get isConnected => services != null;
  bool isDisconnecting = false;

  List<List<int>> chunks = [];
  int contentLength = 0;
  Uint8List _bytes;

  RestartableTimer _timer;
  RecordState _recordState = RecordState.stopped;
  DateFormat dateFormat = DateFormat("yyyy-MM-dd_HH_mm_ss");

  List<FileSystemEntity> files = [];
  String selectedFilePath;

  //FileAudioPlayer player = FileAudioPlayer();

  @override
  void initState() {
    super.initState();
    _getBTConnection();
    _timer = new RestartableTimer(Duration(seconds: 1), _completeByte);
    _listOfFiles();
    selectedFilePath = '';
  }

  @override
  void dispose() {
    if (isConnected) {
      isDisconnecting = true;
      //connection.dispose();
      //connection = null;
    }
    _timer.cancel();
    super.dispose();
  }

  _getBTConnection() async {
    print('MAC ADDRESS: ${widget.server}');

    await widget.server.connect(autoConnect: false).catchError((error) {
      print("ERROR: $error");
    });
    widget.server.connect(autoConnect: false).then((_connection) async {
      print("debug");
      services = await widget.server.discoverServices();
      print("debug 2");
      isConnecting = false;
      isDisconnecting = false;
      setState(() {});
      services.forEach((service) {
        characteristics = service.characteristics;
        characteristics.forEach((characteristic) {
          characteristic.value.listen(_onDataReceived).onDone(() {
            if (this.mounted) {
              setState(() {});
            }
            Navigator.of(context).pop();
          });
        });
      });
    }).catchError((error) {
      print("myERROR: $error");
      Navigator.of(context).pop();
    });

    print("skipped");
    /*BluetoothConnection.toAddress(widget.server.address).then((_connection) {
      connection = _connection;
      isConnecting = false;
      isDisconnecting = false;
      setState(() {});
      connection.input.listen(_onDataReceived).onDone(() {
        if (isDisconnecting) {
          print('Disconnecting locally');
        } else {
          print('Disconnecting remotely');
        }
        if (this.mounted) {
          setState(() {});
        }
        Navigator.of(context).pop();
      });
    }).catchError((error) {
      print("myERROR: $error");
      Navigator.of(context).pop();
    });*/
  }

  _completeByte() async {
    if (chunks.length == 0 || contentLength == 0) {
      EasyLoading.dismiss();
      return;
    }
    _bytes = Uint8List(contentLength);
    int offset = 0;
    for (final List<int> chunk in chunks) {
      _bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    bool granted = await SuperEasyPermissions.isGranted(Permissions.storage);
    if (granted) {
      final File file = await _makeNewFile;
      List<int> headerList = WavHeader.createWavHeader(contentLength);
      file.writeAsBytesSync(headerList, mode: FileMode.write);
      file.writeAsBytesSync(_bytes, mode: FileMode.append);

      EasyLoading.showToast("File saved at ${file.path}");
      _listOfFiles();

      contentLength = 0;
      chunks.clear();
    } else {
      bool result =
          await SuperEasyPermissions.askPermission(Permissions.storage);
      if (result) {
        final File file = await _makeNewFile;
        List<int> headerList = WavHeader.createWavHeader(contentLength);
        file.writeAsBytesSync(headerList, mode: FileMode.write);
        file.writeAsBytesSync(_bytes, mode: FileMode.append);

        EasyLoading.showToast("File saved at ${file.path}");
        _listOfFiles();

        contentLength = 0;
        chunks.clear();
      } else
        EasyLoading.showToast("Unable to save the file");
    }
    EasyLoading.dismiss();
  }

  void _onDataReceived(Uint8List data) {
    if (data != null && data.length > 0) {
      chunks.add(data);
      contentLength += data.length;
      _timer.reset();
    } else
      EasyLoading.showToast("ERROR IN DATA RECEIVED");
  }

  void _sendMessage(String text) async {
    text = text.trim();
    if (text.length > 0) {
      try {
        characteristics.forEach((characteristic) {
          characteristic.write(utf8.encode(text));
        });
        /*connection.output.add(utf8.encode(text));
        await connection.output.allSent;*/

        if (text == "START") {
          _recordState = RecordState.recording;
        } else if (text == "STOP") {
          _recordState = RecordState.stopped;
        }
        setState(() {});
      } catch (e) {
        EasyLoading.showToast("ERROR IN SEND MESSAGE");
        setState(() {});
      }
    } else {
      EasyLoading.showToast("ERROR IN SEND MESSAGE 2");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: (isConnecting
              ? Text('Connecting to ${widget.server.name} ...')
              : isConnected
                  ? Text('Connected with ${widget.server.name}')
                  : Text('Disconnected with ${widget.server.name}')),
        ),
        body: SafeArea(
          child: isConnected
              ? Column(
                  children: <Widget>[
                    recordButton(3),
                    recordButton(23),
                    Expanded(
                      child: ListView(
                        children: files
                            .map((_file) => FileEntityListTile(
                                  filePath: _file.path,
                                  fileSize: _file.statSync().size,
                                  onLongPress: () async {
                                    if (await File(_file.path).exists()) {
                                      File(_file.path).deleteSync();

                                      files.remove(_file);
                                      setState(() {});
                                    }
                                  },
                                  onTap: () async {
                                    Audio audio = Audio.load(_file.path);
                                    if (_file.path == selectedFilePath) {
                                      //await player.stop();
                                      audio.dispose();
                                      selectedFilePath = '';
                                      return;
                                    }

                                    if (await File(_file.path).exists()) {
                                      selectedFilePath = _file.path;
                                      //await player.start(_file.path);
                                      audio.play();
                                    } else {
                                      selectedFilePath = '';
                                    }

                                    setState(() {});
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Text(
                    "Connecting...",
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
        ));
  }

  Widget recordButton(int seconds) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: MaterialButton(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.red)),
        onPressed: () {
          setState(() {
            if (_recordState == RecordState.stopped) {
              _sendMessage("START");
              _showRecordingDialog(seconds);
            } else {
              _sendMessage("STOP");
            }
          });
        },
        color: Colors.red,
        textColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            _recordState == RecordState.stopped
                ? "RECORD FOR $seconds seconds"
                : "STOP",
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }

  void _showRecordingDialog(int seconds) {
    print("START TIME: ${DateTime.now().minute}, ${DateTime.now().second}");
    /*for (int i = 0; i < seconds; i++) {
      Future.delayed(Duration(seconds: 1), () {
        setState(() => timeElapsed++);
      });
    }*/
    Future.delayed(Duration(seconds: seconds), () {
      EasyLoading.show(
          status: "Stopping...", maskType: EasyLoadingMaskType.black);
      _sendMessage("STOP");
      Navigator.of(context).pop();
    });

    showSlideDialog(
        barrierDismissible: false,
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 50,
            ),
            Text(
              "Recording",
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            SizedBox(
              height: 20,
            ),
            Text("Time Elapsed: $timeElapsed seconds"),
            SizedBox(height: 100),
            Container(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                strokeWidth: 10,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
            SizedBox(
              height: 100,
            ),
          ],
        ));
  }

  Future<String> get _localPath async {
    final directory = await getExternalStorageDirectory();
    return directory.path;
  }

  Future<File> get _makeNewFile async {
    final path = await _localPath;
    String newFileName = dateFormat.format(DateTime.now());
    return File('$path/Pebble/$newFileName/noise.wav');
  }

  void _listOfFiles() async {
    final path = await _localPath;
    var fileList = Directory(path).list();
    files.clear();
    fileList.forEach((element) {
      if (element.path.contains("wav")) {
        files.insert(0, element);
      }
    });
    setState(() {});
  }
}
