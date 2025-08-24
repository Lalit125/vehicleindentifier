import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart';

class ListVehiclePage extends StatefulWidget {
  const ListVehiclePage({Key? key, required Database database}) : super(key: key);

  @override
  _ListVehiclePageState createState() => _ListVehiclePageState();
}

class _ListVehiclePageState extends State<ListVehiclePage> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _parkingRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  Database? _database;

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _loadParkingRecords();
    _searchController.addListener(_filterRecords);
  }

  // Initialize SQLite database connection and check for table existence
  Future<void> _initDatabase() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'vehicles.db');

      _database = await openDatabase(path);
      // Check if vehicles table exists
      final tableExists = await _database!.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'"
      );
      if (tableExists.isEmpty) {
        _showErrorSnackBar('Please sync records first.');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to connect to database: $e');
    }
  }

  // Load all parking records from SQLite
  Future<void> _loadParkingRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_database != null) {
        // Check if vehicles table exists
        final tableExists = await _database!.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'"
        );
        if (tableExists.isEmpty) {
          _showErrorSnackBar('Vehicles table not found. Please sync records first.');
          setState(() {
            _parkingRecords = [];
            _filteredRecords = [];
            _isLoading = false;
          });
          return;
        }

        final localRecords = await _database!.query(
          'vehicles',
          orderBy: 'recordEntryTime DESC',
        );
        if (mounted) {
          setState(() {
            _parkingRecords = localRecords;
            _filteredRecords = _searchController.text.isEmpty ? [] : localRecords;
          });
        }
      } else {
        _showErrorSnackBar('Database not initialized');
      }
    } catch (e) {
      _showErrorSnackBar('Error loading records: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Filter records based on search query using SQLite SELECT query
  Future<void> _filterRecords() async {
    final query = _searchController.text.trim();
    setState(() {
      _isLoading = true;
    });

    try {
      if (_database != null) {
        // Check if vehicles table exists
        final tableExists = await _database!.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='vehicles'"
        );
        if (tableExists.isEmpty) {
          _showErrorSnackBar('Vehicles table not found. Please sync records first.');
          setState(() {
            _filteredRecords = [];
            _isLoading = false;
          });
          return;
        }

        if (query.isEmpty) {
          setState(() {
            _filteredRecords = [];
          });
        } else {
          final searchQuery = '%$query%';
          final filteredRecords = await _database!.query(
            'vehicles',
            where: 'numberPlate LIKE ? OR parkingNumber LIKE ? OR CAST(lineNumber AS TEXT) LIKE ?',
            whereArgs: [searchQuery, searchQuery, searchQuery],
            orderBy: 'recordEntryTime DESC',
          );
          if (mounted) {
            setState(() {
              _filteredRecords = filteredRecords;
            });
          }
        }
      } else {
        _showErrorSnackBar('Database not initialized');
      }
    } catch (e) {
      _showErrorSnackBar('Error filtering records: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Show error snackbar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Format date for display
  String _formatDate(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final date = DateTime.parse(dateTime);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Parking Records'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadParkingRecords,
              tooltip: 'Refresh Records',
            ),
          ],
        ),
        body: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    keyboardType: TextInputType.visiblePassword, // Use visiblePassword for alphanumeric keyboard
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')), // Restrict to alphanumeric
                    ],
                    decoration: InputDecoration(
                      hintText: 'Search by Number Plate, Parking Number, or Line Number',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Records Section
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredRecords.isEmpty
                        ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? 'Enter a search query to view records'
                            : 'No parking records found',
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                        : ListView.builder(
                      itemCount: _filteredRecords.length,
                      itemBuilder: (context, index) {
                        final record = _filteredRecords[index];
                        return Card(
                          elevation: 4,
                          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                              'Number Plate: ${record['numberPlate'] ?? 'N/A'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Text(
                                  'Line Number: ${record['lineNumber'] ?? 'N/A'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text('Parking Number: ${record['parkingNumber'] ?? 'N/A'}'),
                                Text('Location: ${record['locationName'] ?? 'N/A'}'),
                                Text(
                                  'Entry Time: ${_formatDate(record['recordEntryTime'])}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterRecords);
    _searchController.dispose();
    _database?.close();
    super.dispose();
  }
}