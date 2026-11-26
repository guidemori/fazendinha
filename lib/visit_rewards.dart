import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class VisitRewardsApi {
  VisitRewardsApi(this.base, this.installationKey, {http.Client? client})
      : _client = client ?? http.Client();

  static const event = 'daily-visits-v1';
  static const dayLimit = 7;
  final Uri base;
  final String installationKey;
  final http.Client _client;

  static String newInstallationKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<VisitSnapshot> visit() => _send('visits');

  Future<VisitSnapshot> claim(int day) => _send('claims', day: day);

  void close() => _client.close();

  Future<VisitSnapshot> _send(String endpoint, {int? day}) async {
    final response = await _client
        .post(
          base.resolve('v1/$endpoint'),
          headers: {
            'Authorization': 'Bearer $installationKey',
            if (day != null) 'Content-Type': 'application/json',
          },
          body: day == null ? null : jsonEncode({'day': day}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw const FormatException(
          'O serviço de visitas recusou a solicitação.');
    }
    return VisitSnapshot.fromJson(jsonDecode(response.body));
  }
}

class VisitSnapshot {
  const VisitSnapshot._(this.visited, this.claimed, this.rewards);

  final int visited;
  final int claimed;
  final List<({int coins, int seeds})> rewards;

  factory VisitSnapshot.fromJson(Object? data) {
    if (data is! Map<String, dynamic> ||
        data['event'] != VisitRewardsApi.event) {
      throw const FormatException('Evento de visitas desconhecido.');
    }
    final visited = data['visited'];
    final claimed = data['claimed'];
    final rewards = data['rewards'];
    if (visited is! int ||
        claimed is! int ||
        claimed < 0 ||
        claimed > visited ||
        visited > VisitRewardsApi.dayLimit ||
        rewards is! List ||
        rewards.length != VisitRewardsApi.dayLimit) {
      throw const FormatException('Progresso de visitas inválido.');
    }
    return VisitSnapshot._(
      visited,
      claimed,
      List.unmodifiable(rewards.map((reward) {
        if (reward is! Map<String, dynamic> ||
            reward['coins'] is! int ||
            reward['seeds'] is! int ||
            (reward['coins'] as int) < 0 ||
            (reward['seeds'] as int) < 0) {
          throw const FormatException('Recompensa inválida.');
        }
        return (coins: reward['coins'] as int, seeds: reward['seeds'] as int);
      })),
    );
  }
}
