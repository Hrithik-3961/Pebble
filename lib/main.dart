import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:pebble/BluetoothDeviceListEntry.dart';
import 'package:pebble/detail_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
      debugShowCheckedModeBanner: false,
      builder: EasyLoading.init(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  BluetoothState _bluetoothState = BluetoothState.unknown;
  FlutterBlue _flutterBlue = FlutterBlue.instance;

  List<BluetoothDevice> devices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    //_getBTState();
    _stateChangeListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state.index == 0) {
      //resume
      if (await _flutterBlue.isOn) {
        _listBondedDevices();
      }
    }
  }

  /*_getBTState() {
    FlutterBluetoothSerial.instance.state.then((state) {
      _bluetoothState = state;
      if (_bluetoothState.isEnabled) {
        _listBondedDevices();
      }
      setState(() {});
    });
  }*/

  _stateChangeListener() {
    _flutterBlue.state.listen((state) async {
      _bluetoothState = state;
      if (await _flutterBlue.isOn) {
        _listBondedDevices();
      } else {
        devices.clear();
      }
      setState(() {});
    });
    /*FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      _bluetoothState = state;
      if (_bluetoothState.isEnabled) {
        _listBondedDevices();
      } else {
        devices.clear();
      }
      setState(() {});
    });*/
  }

  _listBondedDevices() {
    _flutterBlue.startScan();
    _flutterBlue.scanResults.listen((results) {
      for (ScanResult r in results) devices.add(r.device);
      setState(() {});
    });
    /*FlutterBluetoothSerial.instance
        .getBondedDevices()
        .then((List<BluetoothDevice> bondedDevices) {
      devices = bondedDevices;
      setState(() {});
    });*/
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Pebble"),
      ),
      body: Container(
        child: Column(
          children: <Widget>[
            FutureBuilder(
              future: _flutterBlue.isOn,
              builder: (context, value) {
                return SwitchListTile(
                  title: Text('Enable Bluetooth'),
                  value: value.data,
                  onChanged: (bool value) async {
                    /*if (value) {
                      await FlutterBluetoothSerial.instance.requestEnable();
                    } else {
                      await FlutterBluetoothSerial.instance.requestDisable();
                    }*/
                    setState(() {});
                  },
                );
              },
            ),
            ListTile(
              title: Text("Bluetooth STATUS"),
              subtitle: Text(
                _bluetoothState.toString(),
                style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width * 0.04),
              ),
              trailing: MaterialButton(
                child: Text("Settings"),
                onPressed: () {
                  //FlutterBluetoothSerial.instance.openSettings();
                },
              ),
            ),
            Expanded(
              child: ListView(
                children: devices
                    .map((_device) => BluetoothDeviceListEntry(
                  context: context,
                  device: _device,
                  enabled: true,
                  onTap: () {
                    _startCBluetoothConnect(context, _device);
                  },
                ))
                    .toList(),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _startCBluetoothConnect(BuildContext context, BluetoothDevice server) {
    _flutterBlue.stopScan();
    Navigator.of(context).push(MaterialPageRoute(builder: (context) {
      return DetailPage(server: server);
    }));
  }
}
