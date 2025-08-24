import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Function to fetch total vehicles from SQLite database
  Future<int?> _fetchTotalVehicles() async {
    try {
      // Get the path to the database
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'vehicles.db');

      // Open the database
      final database = await openDatabase(path);

      // Query to count total records in the vehicles table
      final result = await database.rawQuery('SELECT COUNT(id) as count FROM vehicles');

      // Close the database
      await database.close();

      // Extract the count from the result
      if (result.isNotEmpty) {
        return Sqflite.firstIntValue(result);
      }

      // Log if no records are found
      debugPrint('No records found in vehicles table');
      return null;
    } catch (e) {
      debugPrint('Error fetching vehicle data from SQLite: $e');
      return null;
    }
  }

  // Function to fetch total unsynced parking records
  Future<int?> _fetchUnsyncedParkingRecords() async {
    try {
      // Get the path to the database
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'parking.db');

      // Open the database
      final database = await openDatabase(path);

      // Query to count unsynced records in the parking_records table
      final result = await database.rawQuery(
          'SELECT COUNT(*) as count FROM parking_records WHERE is_synced = 0');

      // Close the database
      await database.close();

      // Extract the count from the result
      if (result.isNotEmpty) {
        return Sqflite.firstIntValue(result);
      }

      // Log if no records are found
      debugPrint('No unsynced records found in parking_records table');
      return null;
    } catch (e) {
      debugPrint('Error fetching unsynced parking records from SQLite: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Card for Total Vehicles
          Card(
            elevation: 4,
            child: ListTile(
              leading: const Icon(Icons.directions_car, color: Colors.green),
              title: const Text('Total Sync Vehicles'),
              subtitle: FutureBuilder<int?>(
                future: _fetchTotalVehicles(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  } else if (snapshot.hasError || snapshot.data == null) {
                    return const Text('After Sync ');
                  } else {
                    return Text('Total Available Records: ${snapshot.data}');
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Card for Unsynced Parking Records
          Card(
            elevation: 4,
            child: ListTile(
              leading: const Icon(Icons.sync_disabled, color: Colors.red),
              title: const Text('Total Unsynced Parking Records'),
              subtitle: FutureBuilder<int?>(
                future: _fetchUnsyncedParkingRecords(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  } else if (snapshot.hasError || snapshot.data == null) {
                    return const Text('No unsynced records');
                  } else {
                    return Text('Total Unsynced Records: ${snapshot.data}');
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFeaturedCard(String title, Color color) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}