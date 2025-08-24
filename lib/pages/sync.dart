import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;

class Sync extends StatefulWidget {
  const Sync({super.key, required Database database});

  @override
  SyncState createState() => SyncState();
}

class SyncState extends State<Sync> {
  static const String _username = 'rssb';
  static const String _password = 'rssb';
  DateTime? _startDate;
  DateTime? _endDate;
  int _totalRecords = 0;
  bool _isLoading = false;
  Database? _database;
  List<Map<String, dynamic>> _vehicleRecords = [];
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _isDatabaseInitialized = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 0));
    _startDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 0, 0, 0);
    _endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    _initializeDatabaseAndLoadData();
  }

  Future<void> _initializeDatabaseAndLoadData() async {
    try {
      await _initDatabase();
      await Future.delayed(const Duration(milliseconds: 300)); // Ensure DB setup completes
      await _verifyTableExists();
      setState(() {
        _isDatabaseInitialized = true;
      });
      await _loadLocalData();
    } catch (e) {
      debugPrint('Error during initialization: $e');
      developer.log('Initialization error', name: 'Sync', error: e, level: 1000);
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Failed to initialize app: $e. Tap Sync to retry.')),
        );
      }
    }
  }

  Future<void> _initDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'vehicles.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS vehicles (
              id TEXT PRIMARY KEY,
              numberPlate TEXT,
              parkingNumber TEXT,
              lineNumber INTEGER,
              batchEntryTime TEXT,
              recordEntryTime TEXT,
              createdAt TEXT,
              locationId INTEGER,
              locationName TEXT
            )
          ''');
          developer.log('Table "vehicles" created during onCreate', name: 'Sync', level: 700);
        },
        onOpen: (db) async {
          await _verifyTableExists(db: db);
        },
      );
      debugPrint('Database initialized at $path');
      developer.log('Database initialized at $path', name: 'Sync', level: 700);
    } catch (e) {
      debugPrint('Error initializing database: $e');
      developer.log('Database initialization error', name: 'Sync', error: e, level: 1000);
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Failed to initialize database: $e. Tap Sync to retry.')),
        );
      }
      rethrow;
    }
  }

  Future<void> _verifyTableExists({Database? db}) async {
    final database = db ?? _database;
    if (database == null) {
      throw Exception('Database is null');
    }
    final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'");
    if (tables.isEmpty) {
      await database.execute('''
        CREATE TABLE vehicles (
          id TEXT PRIMARY KEY,
          numberPlate TEXT,
          parkingNumber TEXT,
          lineNumber INTEGER,
          batchEntryTime TEXT,
          recordEntryTime TEXT,
          createdAt TEXT,
          locationId INTEGER,
          locationName TEXT
        )
      ''');
      developer.log('Table "vehicles" created during verification', name: 'Sync', level: 700);
    }
  }

  Future<void> _loadLocalData() async {
    if (!_isDatabaseInitialized || _database == null) {
      debugPrint('Cannot load data: Database not initialized');
      developer.log('Attempted to load data but database is not initialized', name: 'Sync', level: 900);
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Database not ready. Please try syncing.')),
        );
      }
      return;
    }
    try {
      await _verifyTableExists();
      final records = await _database!.query('vehicles');
      if (mounted) {
        setState(() {
          _vehicleRecords = records;
          _totalRecords = records.length;
        });
      }
      debugPrint('Loaded ${_vehicleRecords.length} records from local database');
      developer.log('Loaded ${_vehicleRecords.length} local records', name: 'Sync', level: 700);
    } catch (e) {
      debugPrint('Error loading local data: $e');
      developer.log('Error loading local data', name: 'Sync', error: e, level: 1000);
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Failed to load local data: $e')),
        );
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime initialStartDate = now.subtract(const Duration(days: 7));
    final DateTime initialEndDate = now;

    final DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: initialStartDate,
        end: initialEndDate,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (pickedRange == null || !mounted) return;

    setState(() {
      _startDate = DateTime(
        pickedRange.start.year,
        pickedRange.start.month,
        pickedRange.start.day,
        0,
        0,
        0,
      );
      _endDate = DateTime(
        pickedRange.end.year,
        pickedRange.end.month,
        pickedRange.end.day,
        23,
        59,
        59,
      );
    });

    debugPrint('Selected date range: ${_startDate!.toIso8601String()} to ${_endDate!.toIso8601String()}');
    developer.log('Selected date range: ${_startDate!.toIso8601String()} to ${_endDate!.toIso8601String()}',
        name: 'Sync', level: 700);
  }

  Future<void> _syncData() async {
    // Retry database initialization if not initialized
    if (!_isDatabaseInitialized || _database == null) {
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Retrying database initialization...')),
        );
      }
      try {
        await _initializeDatabaseAndLoadData();
      } catch (e) {
        if (mounted) {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Failed to initialize database: $e')),
          );
        }
        return;
      }
    }

    if (_startDate == null || _endDate == null) {
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Date range is not set')),
        );
      }
      return;
    }

    if (_startDate!.isAfter(_endDate!)) {
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Start date cannot be after end date')),
        );
      }
      return;
    }

    final DateTime now = DateTime.now();
    if (_startDate!.isAfter(now)) {
      if (mounted) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Selected dates cannot be in the future')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _totalRecords = 0;
    });

    try {
      await _verifyTableExists();
      final dateFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss");
      final formattedStartDate = dateFormat.format(_startDate!);
      final formattedEndDate = dateFormat.format(_endDate!);
      int page = 0;
      bool hasMoreData = true;
      const int pageSize = 50;

      final String basicAuth = 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';

      await _database!.delete(
        'vehicles',
        where: 'recordEntryTime >= ? AND recordEntryTime <= ?',
        whereArgs: [formattedStartDate, formattedEndDate],
      );
      debugPrint('Cleared existing records for date range: $formattedStartDate to $formattedEndDate');
      developer.log('Cleared existing records for date range', name: 'Sync', level: 700);

      while (hasMoreData && mounted) {
        final url = Uri.parse(
          'https://rssbvehicleparking-cfebhed4eaawbyay.centralindia-01.azurewebsites.net/vehicles'
              '?startDate=${Uri.encodeComponent(formattedStartDate)}'
              '&endDate=${Uri.encodeComponent(formattedEndDate)}'
              '&page=$page'
              '&size=$pageSize',
        );

        debugPrint('Fetching URL: $url');
        developer.log('Fetching data for page $page with startDate=$formattedStartDate, endDate=$formattedEndDate', name: 'Sync', level: 700);

        final response = await http.get(
          url,
          headers: <String, String>{
            'Authorization': basicAuth,
            'Content-Type': 'application/json',
          },
        );

        debugPrint('Response status: ${response.statusCode}');
        developer.log('HTTP response for page $page: status=${response.statusCode}, body length=${response.body.length}', name: 'Sync', level: 700);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          developer.log('Parsed JSON data for page $page', name: 'Sync', level: 700);

          if (data['content'] == null || data['content'] is! List) {
            debugPrint('No content field or content is not a list');
            developer.log('Invalid content field in response for page $page', name: 'Sync', error: 'Content is null or not a list', level: 900);
            hasMoreData = false;
            break;
          }

          final records = data['content'] as List<dynamic>;

          debugPrint('Received ${records.length} records for page $page');
          developer.log('Received ${records.length} records for page $page', name: 'Sync', level: 700);

          if (records.isEmpty) {
            hasMoreData = false;
          } else {
            final batch = _database!.batch();
            for (var record in records) {
              final location = record['location'] as Map<String, dynamic>?;
              final vehicleData = {
                'id': record['id']?.toString() ?? '',
                'numberPlate': record['numberPlate']?.toString() ?? '',
                'parkingNumber': record['parkingNumber']?.toString() ?? '',
                'lineNumber': record['lineNumber'] as int? ?? 0,
                'batchEntryTime': record['batchEntryTime']?.toString() ?? '',
                'recordEntryTime': record['recordEntryTime']?.toString() ?? '',
                'createdAt': record['createdAt']?.toString() ?? '',
                'locationId': location?['locationId'] as int? ?? 0,
                'locationName': location?['locationName']?.toString() ?? '',
              };
              batch.insert(
                'vehicles',
                vehicleData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
            debugPrint('Batch inserted ${records.length} records for page $page');
            developer.log('Batch inserted ${records.length} records for page $page', name: 'Sync', level: 700);

            _totalRecords += records.length;
            page++;
            if (data['last'] == true) {
              hasMoreData = false;
              debugPrint('Last page reached: page $page');
              developer.log('Reached last page of data: page $page', name: 'Sync', level: 700);
            }
            if (mounted) {
              setState(() {});
            }
          }
        } else {
          final error = 'Failed to fetch data on page $page: ${response.statusCode} - ${response.body}';
          debugPrint(error);
          developer.log(error, name: 'Sync', error: response.body, level: 900);
          throw Exception(error);
        }
      }

      await _loadLocalData();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Synced $_totalRecords records successfully')),
        );
        debugPrint('Sync completed: $_totalRecords records');
        developer.log('Sync completed with $_totalRecords records', name: 'Sync', level: 700);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        final errorMessage = e.toString().contains('could not be parsed')
            ? 'Invalid date format. Please try a different date range.'
            : 'Error syncing data: $e';
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
      debugPrint('Error during sync: $e');
      developer.log('Sync error', name: 'Sync', error: e, level: 1000);
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Not selected';
    return DateFormat('MMM dd, yyyy HH:mm:ss').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sync Vehicle Records'),
          elevation: 2,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Date Range',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'From',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDateTime(_startDate),
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'To',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDateTime(_endDate),
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () => _selectDateRange(context),
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Select Date Range'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Records',
                        style: TextStyle(fontSize: 16),
                      ),
                      Text(
                        '$_totalRecords',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                  onPressed: _syncData, // Button is always enabled unless loading
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Records'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: Text(
                    _vehicleRecords.isEmpty ? 'No records available' : 'Records loaded',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _database?.close();
    debugPrint('Database closed');
    developer.log('Database closed during dispose', name: 'Sync', level: 700);
    super.dispose();
  }
}