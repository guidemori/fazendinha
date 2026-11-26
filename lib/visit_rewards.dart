import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class VisitRewardsApi {
  VisitRewardsApi(this.base, this.installationKey, {http.Client? client})
      : _client = client ?? http.Client();

  static const event = 'daily-login-v2';
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

  Future<VisitSnapshot> claim(String date) => _send('claims', date: date);

  void close() => _client.close();

  Future<VisitSnapshot> _send(String endpoint, {String? date}) async {
    final response = await _client
        .post(
          base.resolve('v2/$endpoint'),
          headers: {
            'Authorization': 'Bearer $installationKey',
            if (date != null) 'Content-Type': 'application/json',
          },
          body: date == null ? null : jsonEncode({'date': date}),
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
  const VisitSnapshot._({
    required this.date,
    required this.streak,
    required this.rewardDay,
    required this.claimable,
    required this.claimedToday,
    required this.coinsPaid,
    required this.seedsPaid,
    required this.rewards,
  });

  final String date;
  final int streak;
  final int rewardDay;
  final bool claimable;
  final bool claimedToday;
  final int coinsPaid;
  final int seedsPaid;
  final List<({int coins, int seeds})> rewards;

  factory VisitSnapshot.fromJson(Object? data) {
    if (data is! Map<String, dynamic> ||
        data['event'] != VisitRewardsApi.event) {
      throw const FormatException('Evento de login diário desconhecido.');
    }
    final date = data['date'];
    final streak = data['streak'];
    final rewardDay = data['rewardDay'];
    final claimable = data['claimable'];
    final claimedToday = data['claimedToday'];
    final coinsPaid = data['coinsPaid'];
    final seedsPaid = data['seedsPaid'];
    final rewards = data['rewards'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        streak is! int ||
        streak < 1 ||
        rewardDay is! int ||
        rewardDay != (streak - 1) % VisitRewardsApi.dayLimit + 1 ||
        claimable is! bool ||
        claimedToday is! bool ||
        (claimable && claimedToday) ||
        coinsPaid is! int ||
        coinsPaid < 0 ||
        seedsPaid is! int ||
        seedsPaid < 0 ||
        rewards is! List ||
        rewards.length != VisitRewardsApi.dayLimit) {
      throw const FormatException('Progresso de login diário inválido.');
    }
    return VisitSnapshot._(
      date: date,
      streak: streak,
      rewardDay: rewardDay,
      claimable: claimable,
      claimedToday: claimedToday,
      coinsPaid: coinsPaid,
      seedsPaid: seedsPaid,
      rewards: List.unmodifiable(rewards.map((reward) {
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
