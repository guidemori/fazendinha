import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/game_constants.dart';
import 'models/player.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox(GameConstants.hiveBoxName);

  final player = Player.initial(plotCount: GameConstants.startingPlots);
  runApp(FazendinhaApp(player: player));
}

class FazendinhaApp extends StatelessWidget {
  const FazendinhaApp({super.key, required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fazendinha Idle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'FarmRoboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
      ),
      home: HomeScreen(player: player),
    );
  }
}
