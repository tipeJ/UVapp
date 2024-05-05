import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UV Index App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: BleUVIndexPage(),
    );
  }
}

class BleUVIndexPage extends StatefulWidget {
  @override
  _BleUVIndexPageState createState() => _BleUVIndexPageState();
}

class _BleUVIndexPageState extends State<BleUVIndexPage> {
  final flutterReactiveBle = FlutterReactiveBle();
  late Stream<BleStatus> bleStatusStream;
  bool _isConnected = false;
  String _uvIndex = 'N/A';
  String _connectedDeviceId = '';
  Color _appColor = Colors.white; // Default color
  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  Timer? _notificationTimer;
  static const int NOTIFICATION_TIME_LIMIT = 10; // in seconds

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions();
    bleStatusStream = flutterReactiveBle.statusStream;
  }

  void _initNotifications() async {
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _onSelectNotification(response.payload);
      },
    );
  }

  Future<void> _onSelectNotification(String? payload) async {
    // Handle notification selection
  }

  void _requestPermissions() async {
    if (await Permission.bluetooth.status != PermissionStatus.granted) {
      await Permission.bluetooth.request();
    }
    if (await Permission.location.status != PermissionStatus.granted) {
      await Permission.location.request();
    }
  }

  void _connectToDevice() async {
    // Find the first device with the name 'UV_BLE_APP'
    final devices = flutterReactiveBle.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
      requireLocationServicesEnabled: true,
    );
    // Print all device names, until the desired device is found
    final device = await devices.firstWhere((device) {
      print('Device found: ${device.name}');
      return device.name == 'UV_BLE_APP';
    });

    final deviceId = device.id;
    final connection = flutterReactiveBle.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    );
    connection.listen((connectionState) {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        setState(() {
          _isConnected = true;
          _connectedDeviceId = deviceId;
        });
        _subscribeToUVIndex(deviceId);
      } else if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        setState(() {
          _isConnected = false;
          _connectedDeviceId = '';
        });
      }
    }, onError: (Object error) {
      print('Connection Error: $error');
    });
  }

  void _subscribeToUVIndex(String deviceId) async {
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse('4fafc201-1fb5-459e-8fcc-c5c9c331914b'),
      characteristicId: Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a8'),
      deviceId: deviceId,
    );
    final subscription =
        flutterReactiveBle.subscribeToCharacteristic(characteristic);
    subscription.listen((data) {
      setState(() {
        _uvIndex = String.fromCharCodes(data);
        double _uvIndexDouble = double.parse(_uvIndex);
        _updateColorScheme(_uvIndexDouble.toInt());
        if (_uvIndexDouble > 5) {
          _scheduleNotification();
        }
      });
    }, onError: (dynamic error) {
      print('Subscription Error: $error');
    });
  }

  void _updateColorScheme(int uvIndex) {
    setState(() {
      if (uvIndex <= 2) {
        _appColor = Colors.white; // Low level
      } else if (uvIndex <= 5) {
        _appColor = Colors.yellow; // Moderate level
      } else if (uvIndex <= 7) {
        _appColor = Colors.orange; // High level
      } else {
        _appColor = Colors.purple; // Very high level
      }
    });
  }

  void _scheduleNotification() {
    if (_notificationTimer == null || !_notificationTimer!.isActive) {
      _notificationTimer =
          Timer(Duration(seconds: NOTIFICATION_TIME_LIMIT), () {
        _showNotification();
      });
    }
  }

  Future<void> _showNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'high_uv_alert', // channel ID
      'High UV Alert', // channel name
      channelDescription: 'Alerts when UV index is high', // channel description
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _flutterLocalNotificationsPlugin.show(
      0, // notification ID
      'High UV Alert', // title
      'The UV index is high!', // body
      platformChannelSpecifics,
      payload: 'High UV Alert', // optional payload
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('UV Index App'),
      ),
      body: AnimatedContainer(
        duration: Duration(milliseconds: 500), // Smooth transition duration
        color: _appColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'UV Index:',
                style: TextStyle(fontSize: 24.0),
              ),
              SizedBox(height: 20.0),
              Text(
                _uvIndex,
                style: TextStyle(fontSize: 36.0, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20.0),
              _isConnected
                  ? Text('Connected to BLE device: $_connectedDeviceId')
                  : ElevatedButton(
                      onPressed: _connectToDevice,
                      child: Text('Connect'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }
}
