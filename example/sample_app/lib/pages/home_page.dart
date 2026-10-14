import 'package:flutter/material.dart';

/// Landing page. Hand-written logic below the build method is kept intact
/// by Widget Bench edits.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trail Notes'),
        actions: [IconButton(onPressed: _increment, icon: const Icon(Icons.search))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Good morning',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Three hikes planned this week.'),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Ridge Loop'),
                subtitle: const Text('8.2 km · Saturday'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Lakeside Trail'),
                subtitle: const Text('5.4 km · Sunday'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _increment, child: const Text('Plan a hike')),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _increment,
        child: const Icon(Icons.add),
      ),
    );
  }

  // Custom code: untouched by visual edits.
  void _increment() => setState(() => _taps++);
}
