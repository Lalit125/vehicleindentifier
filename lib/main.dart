import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'pages/home_page.dart';
import 'pages/vehicle_page.dart';
import 'pages/list_vehicle_page.dart';
import 'pages/sync.dart';
import 'api_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await _initializeDatabase();
  runApp(MyApp(database: database));
}

Future<Database> _initializeDatabase() async {
  final databasePath = await getDatabasesPath();
  final dbPath = join(databasePath, 'parking.db');
  return openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS parking_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          line_number INTEGER,
          number_plate TEXT,
          parking_number TEXT,
          location TEXT,
          created_at TEXT,
          record_entry_time TEXT,
          is_synced INTEGER DEFAULT 0,
          synced_at TEXT
        )
      ''');
    },
  );
}

class MyApp extends StatelessWidget {
  final Database database;
  const MyApp({Key? key, required this.database}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vehicle Identifier',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: MyHomePage(database: database),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final Database database;
  const MyHomePage({Key? key, required this.database}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      const HomePage(),
      const VehiclePage(),
      ListVehiclePage(database: widget.database),
      Sync(database: widget.database),
    ];
    print('API Base URL: ${ApiConfig().baseUrl}');
    print('Is Production: ${ApiConfig().isProduction}');
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/RSSB_logo.svg',
              height: 40,
              fit: BoxFit.contain,
              placeholderBuilder: (context) => const Icon(Icons.error, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text(
              'Vehicle Identifier',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        centerTitle: true,
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Vehicle',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync),
            label: 'Sync Records',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}