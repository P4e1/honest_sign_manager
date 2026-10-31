import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/history_provider.dart';
import 'providers/upload_provider.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = DatabaseService();
  await db.init();

  final settings = SettingsService();
  await settings.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: db),
        Provider<SettingsService>.value(value: settings),
        ChangeNotifierProvider(create: (_) => UploadProvider(db, settings)..init()),
        ChangeNotifierProvider(create: (_) => HistoryProvider(db, settings)..load()),
      ],
      child: const MyApp(),
    ),
  );
}
