//For the hamburger menu feature
import 'package:flutter/material.dart';
import 'quick_start_page.dart';
import 'advanced_search_help_page.dart';
import 'tips_page.dart';
import 'filters_page.dart';
import 'reports_page.dart';
import 'warrent_info_page.dart';

class AppDrawer extends StatelessWidget {
  final GlobalKey<State<StatefulWidget>>? filtersTileKey;
  final GlobalKey<State<StatefulWidget>>? reportsTileKey;

  const AppDrawer({super.key, this.filtersTileKey, this.reportsTileKey});

  void _open(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const DrawerHeader(
              child: Text(
                'LEOFindIt',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text(
                "Help & Guidance",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: const Text("Quick Start"),
              onTap: () => _open(context, const QuickStartPage()),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text("Advanced Search"),
              onTap: () => _open(context, const AdvancedSearchHelpPage()),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text("Warrant Info"),
              onTap: () => _open(context, const WarrantInfoPage()),
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text("Tips"),
              onTap: () => _open(context, const TipsPage()),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text(
                "Tools",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              key: filtersTileKey,
              leading: const Icon(Icons.tune),
              title: const Text("Filters"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FiltersPage()),
                );
              },
            ),
            ListTile(
              key: reportsTileKey,
              leading: const Icon(Icons.description_outlined),
              title: const Text("Reports"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
