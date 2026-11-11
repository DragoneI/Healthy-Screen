
import 'package:flutter/material.dart';
import '../data/native_bridge.dart';
import '../domain/schedule_config.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nativeBridge = NativeBridge();
  bool _hasWriteSettings = false;
  bool _hasExactAlarm = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final write = await _nativeBridge.canWriteSettings();
    final exact = await _nativeBridge.canScheduleExact();
    setState(() {
      _hasWriteSettings = write;
      _hasExactAlarm = exact;
    });
  }

  Future<void> _saveAndApplyTestSchedule() async {
    // Configuration par défaut pour tester (ex: coucher à 22h, lever à 7h)
    final config = ScheduleConfig(
      sunriseHour: 7,
      sunriseMinute: 0,
      sunsetHour: 19,
      sunsetMinute: 0,
      nightHour: 22,
      nightMinute: 0,
      nightBrightness: 50,
    );

    await _nativeBridge.saveSchedule(config);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuration enregistrée et alarmes programmées !')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Healthy Screen'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'État des permissions requises :',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: const Text('Modifier les paramètres (Luminosité)'),
              subtitle: Text(_hasWriteSettings ? 'Autorisé ✅' : 'Non autorisé ❌'),
              trailing: ElevatedButton(
                onPressed: () async {
                  await _nativeBridge.openWriteSettings();
                  _checkPermissions();
                },
                child: const Text('Activer'),
              ),
            ),
            ListTile(
              title: const Text('Alarmes exactes'),
              subtitle: Text(_hasExactAlarm ? 'Autorisé ✅' : 'Non autorisé ❌'),
              trailing: ElevatedButton(
                onPressed: () async {
                  await _nativeBridge.openExactAlarmSettings();
                  _checkPermissions();
                },
                child: const Text('Activer'),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saveAndApplyTestSchedule,
                icon: const Icon(Icons.alarm, color: Colors.white),
                label: const Text(
                  'Enregistrer et armer les alarmes',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}