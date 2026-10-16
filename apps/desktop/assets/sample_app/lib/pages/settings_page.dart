import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(title: Text('Account'), leading: Icon(Icons.person)),
          const ListTile(title: Text('Notifications'), leading: Icon(Icons.notifications)),
          const Divider(),
          const ListTile(title: Text('Sign out'), leading: Icon(Icons.logout)),
        ],
      ),
    );
  }
}
