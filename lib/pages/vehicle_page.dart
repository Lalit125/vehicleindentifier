import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'dart:async';

// Global controllers
final TextEditingController _lineNumberController = TextEditingController();
final TextEditingController _numberPlateController = TextEditingController();
final TextEditingController _parkingNumberController = TextEditingController();

// Variables to persist last submitted values
String? _lastParkingNumber;
String? _lastLineNumber;
String? _lastSelectedLocation;
String? _lastNumberPlate;

// API base URL and credentials
const String _apiBaseUrl = 'https://rssbvehicleparking-cfebhed4eaawbyay.centralindia-01.azurewebsites.net/vehicles/bulk';
const String _username = 'rssb';
const String _password = 'rssb';

// Singleton database instance
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database == null || !_database!.isOpen) {
      await _initDatabase();
    }
    return _database!;
  }

  Future<void> _initDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final dbPath = path.join(databasesPath, 'parking.db');
      _database = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE parking_records (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              line_number INTEGER,
              number_plate TEXT,
              parking_number TEXT,
              location TEXT,
              created_at TEXT,
              record_entry_time TEXT,
              is_synced INTEGER,
              synced_at TEXT
            )
          ''');
        },
      );
    } catch (e) {
      print("Database initialization error: $e");
    }
  }
}

class VehiclePage extends StatefulWidget {
  const VehiclePage({Key? key}) : super(key: key);

  @override
  _VehiclePageState createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  final _formKey = GlobalKey<FormState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _isLoading = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isConnected = false;
  List<String> _locations = ['BHATI', 'PUSA'];
  String? _selectedLocation;
  static const int _batchSize = 100;
  Timer? _syncTimer;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _populateTextControllers();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
          final isConnected = results.any((result) => result != ConnectivityResult.none);
          if (mounted) {
            setState(() {
              _isConnected = isConnected;
            });
          }
          if (isConnected) {
            _triggerSync();
          }
        });
    _startSyncTimer();
  }

  // Populate text controllers with last submitted values
  void _populateTextControllers() {
    setState(() {
      _selectedLocation =
          _lastSelectedLocation ?? (_locations.isNotEmpty ? _locations[0] : null);
      if (_lastParkingNumber != null) {
        _parkingNumberController.text = _lastParkingNumber!;
      }
      if (_lastLineNumber != null) {
        _lineNumberController.text = _lastLineNumber!;
      }
      if (_lastNumberPlate != null) {
        _numberPlateController.text = _lastNumberPlate!;
      }
    });
  }

  // Start periodic sync timer (every 1 minute)
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        _triggerSync();
      } else {
        timer.cancel();
      }
    });
  }

  // Trigger sync process
  Future<void> _triggerSync() async {
    if (_isSyncing || !mounted) {
      print("Sync skipped: Sync in progress or widget not mounted");
      return;
    }

    final db = await DatabaseHelper().database;
    if (!_isConnected) {
      print("Sync skipped: No internet connection");
      return;
    }

    setState(() {
      _isSyncing = true;
    });
    print("Starting sync attempt at ${DateTime.now()}");
    await _syncPendingRecords(db);
    if (mounted) {
      setState(() {
        _isSyncing = false;
      });
    }
    print("Sync attempt completed at ${DateTime.now()}");
  }

  // Check connectivity status
  Future<void> _checkConnectivity() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult.any((result) => result != ConnectivityResult.none);
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
      if (isConnected) {
        _triggerSync();
      }
    } catch (e) {
      print("Connectivity check error: $e");
    }
  }

  // Show success SnackBar
  void _showSuccessSnackBar(String message) {
    if (mounted) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  // Show error SnackBar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  // Sync pending records to remote server
  Future<void> _syncPendingRecords(Database db) async {
    try {
      final List<Map<String, dynamic>> pending = await db.query(
        'parking_records',
        where: 'is_synced = ?',
        whereArgs: [0],
        limit: _batchSize,
      );
      if (pending.isEmpty) {
        print("No pending records to sync");
        return;
      }

      print("Found ${pending.length} pending records to sync");

      // Prepare data for bulk API
      final List<Map<String, dynamic>> recordsToSync = pending.map((record) {
        return {
          'line_number': record['line_number'],
          'number_plate': record['number_plate'],
          'parking_number': record['parking_number'],
          'location': record['location'],
          'created_at': record['created_at'],
          'record_entry_time': record['record_entry_time'],
        };
      }).toList();

      // Encode credentials for Basic Authentication
      final String basicAuth =
          'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';

      // Send bulk request to server
      final response = await http.post(
        Uri.parse(_apiBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': basicAuth,
        },
        body: jsonEncode(recordsToSync),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final now = DateTime.now().toIso8601String();
        for (var record in pending) {
          if (!db.isOpen) {
            print("Database closed during sync, aborting");
            return;
          }
          await db.update(
            'parking_records',
            {
              'is_synced': 1,
              'synced_at': now,
            },
            where: 'id = ?',
            whereArgs: [record['id']],
          );
        }
        _showSuccessSnackBar("Synced ${pending.length} records successfully");
        print("Successfully synced ${pending.length} records");
      } else {
        print("Failed to sync records: ${response.statusCode} ${response.body}");
        _showErrorSnackBar("Failed to sync records; will retry in 1 minute");
      }
    } catch (e) {
      print("Sync error: $e");
      _showErrorSnackBar("Sync failed: $e; will retry in 1 minute");
    }
  }

  // Submit form and save record
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fill all fields');
      return;
    }

    final db = await DatabaseHelper().database;

    setState(() {
      _isLoading = true;
    });
    final now = DateTime.now().toIso8601String();
    final data = {
      'line_number': int.parse(_lineNumberController.text.trim()),
      'number_plate': _numberPlateController.text.trim(),
      'parking_number': _parkingNumberController.text.trim(),
      'location': _selectedLocation,
      'created_at': now,
      'record_entry_time': now,
      'is_synced': 0,
    };

    try {
      await db.insert('parking_records', data,
          conflictAlgorithm: ConflictAlgorithm.replace);
      setState(() {
        _lastParkingNumber = _parkingNumberController.text;
        _lastLineNumber = _lineNumberController.text;
        _lastSelectedLocation = _selectedLocation;
        _lastNumberPlate = ''; // Clear last number plate
        _numberPlateController.clear(); // Clear vehicle number field
      });
      _showSuccessSnackBar("Saved Successfully");
      if (_isConnected) {
        _triggerSync();
      }
    } catch (e) {
      _showErrorSnackBar("Failed to save: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Open camera to scan number plate
  Future<void> _openCameraAndScanPlate() async {
    var status = await Permission.camera.request();
    if (!status.isGranted) {
      _showErrorSnackBar("Camera permission denied");
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      _showErrorSnackBar("No camera available");
      return;
    }

    final camera = cameras.first;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NumberPlateScanner(camera: camera),
      ),
    );

    if (result != null && result is String) {
      setState(() {
        _numberPlateController.text = result;
        _lastNumberPlate = result;
      });
      _showSuccessSnackBar("Number Plate Scanned Successfully");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Parking Entry Form"),
          actions: [
            Icon(_isConnected ? Icons.wifi : Icons.wifi_off,
                color: _isConnected ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.blue),
              onPressed: _isSyncing ? null : _triggerSync,
              tooltip: 'Manual Sync',
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedLocation,
                  items: _locations
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedLocation = v),
                  validator: (v) => v == null ? "Select location" : null,
                  decoration: const InputDecoration(
                      labelText: "Location", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _parkingNumberController,
                  decoration: const InputDecoration(
                      labelText: "Parking Number", border: OutlineInputBorder()),
                  validator: (v) =>
                  v == null || v.isEmpty ? "Enter parking number" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lineNumberController,
                  decoration: const InputDecoration(
                      labelText: "Line Number", border: OutlineInputBorder()),
                  validator: (v) =>
                  v == null || v.isEmpty ? "Enter line number" : null,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _numberPlateController,
                  decoration: InputDecoration(
                    labelText: "Vehicle Number",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.blue),
                      onPressed: _openCameraAndScanPlate,
                    ),
                  ),
                  validator: (v) =>
                  v == null || v.isEmpty ? "Enter vehicle number" : null,
                  keyboardType: TextInputType.text, // Alphanumeric keyboard
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Submit"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}

class NumberPlateScanner extends StatefulWidget {
  final CameraDescription camera;
  const NumberPlateScanner({Key? key, required this.camera}) : super(key: key);

  @override
  State<NumberPlateScanner> createState() => _NumberPlateScannerState();
}

class _NumberPlateScannerState extends State<NumberPlateScanner> {
  CameraController? _controller;
  late Future<void> _initializeControllerFuture;
  final TextRecognizer _textRecognizer = TextRecognizer();

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.high,
        enableAudio: false);
    _initializeControllerFuture = _controller!.initialize().catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Camera initialization failed: $e")),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _scanNumberPlate() async {
    try {
      await _initializeControllerFuture;
      final picture = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(picture.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      String allText = recognizedText.blocks
          .map((block) => block.text)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      print("Recognized text: $allText");

      final plateRegex = RegExp(
        r'[A-Z]{2,3}\s?-?\s?[0-9]{1,3}\s?-?\s?[A-Z]{0,2}\s?-?\s?[0-9]{2,4}',
        caseSensitive: false,
      );

      String? plate;
      final match = plateRegex.firstMatch(allText);
      if (match != null) {
        plate = match.group(0)?.replaceAll(RegExp(r'\s|-'), '');
      }

      if (plate == null && allText.isNotEmpty) {
        final candidates = allText.split(' ').where((t) => RegExp(r'^[A-Z0-9]+$').hasMatch(t));
        if (candidates.isNotEmpty) {
          plate = candidates.reduce((a, b) => a.length > b.length ? a : b);
        }
      }

      if (plate != null && plate.isNotEmpty) {
        print("Detected number plate: $plate");
        Navigator.pop(context, plate);
      } else {
        print("No valid number plate detected");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No valid number plate detected, try again")),
        );
      }
    } catch (e) {
      print("Error scanning number plate: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Number Plate")),
      body: FutureBuilder(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
            return CameraPreview(_controller!);
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanNumberPlate,
        child: const Icon(Icons.camera),
      ),
    );
  }
}