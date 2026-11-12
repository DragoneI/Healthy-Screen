import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/native_bridge.dart';
import '../domain/schedule_config.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _nativeBridge = NativeBridge();
  bool _hasWriteSettings = false;
  bool _hasExactAlarm = false;

  int _sunriseHour = 7;
  int _sunriseMinute = 0;
  int _sunsetHour = 19;
  int _sunsetMinute = 0;
  int _nightHour = 22;
  int _nightMinute = 0;
  double _nightBrightness = 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _loadSchedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Relit les permissions quand l'utilisateur revient des paramètres système.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final write = await _nativeBridge.canWriteSettings();
    final exact = await _nativeBridge.canScheduleExact();
    if (!mounted) return;
    setState(() {
      _hasWriteSettings = write;
      _hasExactAlarm = exact;
    });
  }

  // Recharge la dernière configuration enregistrée.
  Future<void> _loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sunriseHour = prefs.getInt('sunriseHour') ?? _sunriseHour;
      _sunriseMinute = prefs.getInt('sunriseMinute') ?? _sunriseMinute;
      _sunsetHour = prefs.getInt('sunsetHour') ?? _sunsetHour;
      _sunsetMinute = prefs.getInt('sunsetMinute') ?? _sunsetMinute;
      _nightHour = prefs.getInt('nightHour') ?? _nightHour;
      _nightMinute = prefs.getInt('nightMinute') ?? _nightMinute;
      final saved = prefs.getInt('nightBrightness');
      if (saved != null) {
        // Recale sur la grille du slider (pas de 5, de 10 à 255).
        final snapped = (10 + ((saved - 10) / 5).round() * 5).clamp(10, 255);
        _nightBrightness = snapped.toDouble();
      }
    });
  }

  Future<void> _persistSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sunriseHour', _sunriseHour);
    await prefs.setInt('sunriseMinute', _sunriseMinute);
    await prefs.setInt('sunsetHour', _sunsetHour);
    await prefs.setInt('sunsetMinute', _sunsetMinute);
    await prefs.setInt('nightHour', _nightHour);
    await prefs.setInt('nightMinute', _nightMinute);
    await prefs.setInt('nightBrightness', _nightBrightness.toInt());
  }

  Future<void> _pickTime(
    int initialHour,
    int initialMinute,
    void Function(int, int) onSelected,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (context, child) {
        // On garde le thème courant (mode sombre inclus), seule la couleur change.
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(primary: Colors.teal),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onSelected(picked.hour, picked.minute);
    }
  }

  void _showMessage(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  Future<void> _saveSchedule() async {
    if (!_hasWriteSettings || !_hasExactAlarm) {
      _showMessage('Accordez d’abord les permissions requises.');
      return;
    }

    final sunrise = _sunriseHour * 60 + _sunriseMinute;
    final sunset = _sunsetHour * 60 + _sunsetMinute;
    final night = _nightHour * 60 + _nightMinute;
    if (!(sunrise < sunset && sunset < night)) {
      _showMessage(
        'Les horaires doivent respecter : lever < coucher < nuit profonde.',
      );
      return;
    }

    final config = ScheduleConfig(
      sunriseHour: _sunriseHour,
      sunriseMinute: _sunriseMinute,
      sunsetHour: _sunsetHour,
      sunsetMinute: _sunsetMinute,
      nightHour: _nightHour,
      nightMinute: _nightMinute,
      nightBrightness: _nightBrightness.toInt(),
    );

    await _nativeBridge.saveSchedule(config);
    await _persistSchedule();

    if (!mounted) return;
    _showMessage(
      '✨ Configuration enregistrée et alarmes programmées !',
      color: Colors.teal,
    );
  }

  Widget _grantedChip() => Chip(
        label: const Text('Autorisé'),
        backgroundColor: Colors.green.shade100,
        labelStyle: TextStyle(color: Colors.green.shade800),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Healthy Screen',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔐 Permissions requises',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Modifier la luminosité'),
                      _hasWriteSettings
                          ? _grantedChip()
                          : ElevatedButton(
                              onPressed: () async {
                                // La relecture se fait au retour dans l'app
                                // (didChangeAppLifecycleState).
                                await _nativeBridge.openWriteSettings();
                              },
                              child: const Text('Activer'),
                            ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Alarmes exactes'),
                      _hasExactAlarm
                          ? _grantedChip()
                          : ElevatedButton(
                              onPressed: () async {
                                await _nativeBridge.openExactAlarmSettings();
                              },
                              child: const Text('Activer'),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '⏰ Planification de la journée',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildTimeCard(
            title: 'Lever du soleil',
            subtitle: 'Remet la luminosité automatique & fond clair',
            icon: Icons.wb_sunny,
            color: Colors.orange,
            hour: _sunriseHour,
            minute: _sunriseMinute,
            onTap: () => _pickTime(_sunriseHour, _sunriseMinute, (h, m) {
              setState(() {
                _sunriseHour = h;
                _sunriseMinute = m;
              });
            }),
          ),
          const SizedBox(height: 10),
          _buildTimeCard(
            title: 'Coucher du soleil',
            subtitle: 'Bascule vers l’ambiance du soir',
            icon: Icons.nights_stay,
            color: Colors.deepOrange,
            hour: _sunsetHour,
            minute: _sunsetMinute,
            onTap: () => _pickTime(_sunsetHour, _sunsetMinute, (h, m) {
              setState(() {
                _sunsetHour = h;
                _sunsetMinute = m;
              });
            }),
          ),
          const SizedBox(height: 10),
          _buildTimeCard(
            title: 'Mode Nuit Profonde',
            subtitle: 'Baisse de luminosité & fond sombre',
            icon: Icons.bedtime,
            color: Colors.indigo,
            hour: _nightHour,
            minute: _nightMinute,
            onTap: () => _pickTime(_nightHour, _nightMinute, (h, m) {
              setState(() {
                _nightHour = h;
                _nightMinute = m;
              });
            }),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Niveau de luminosité de nuit',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Intensité : ${_nightBrightness.toInt()} / 255'),
                  Slider(
                    value: _nightBrightness,
                    min: 10,
                    max: 255,
                    divisions: 49, // pas de 5 : (255 - 10) / 49
                    activeColor: Colors.teal,
                    label: _nightBrightness.toInt().toString(),
                    onChanged: (val) {
                      setState(() {
                        _nightBrightness = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saveSchedule,
              icon: const Icon(Icons.save),
              label: const Text(
                'Enregistrer et armer les alarmes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int hour,
    required int minute,
    required VoidCallback onTap,
  }) {
    final timeFormatted =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Text(
              timeFormatted,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}