import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _redirect = 'com.guidemori.fazendinhaidle://social-login';

Future<SupabaseClient?> configureSocialFarm() async {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      key.isEmpty) {
    return null;
  }
  final endpoint = Uri.tryParse(url);
  if (endpoint == null || endpoint.scheme != 'https' || endpoint.host.isEmpty) {
    return null;
  }
  try {
    final supabase = await Supabase.initialize(url: url, publishableKey: key);
    return supabase.client;
  } catch (error) {
    debugPrint('Não foi possível iniciar o modo social: ${error.runtimeType}');
    return null;
  }
}

Future<void> showSocialFarm(BuildContext context, SupabaseClient client) =>
    showDialog<void>(
      context: context,
      builder: (context) => StreamBuilder<AuthState>(
        stream: client.auth.onAuthStateChange,
        builder: (context, snapshot) => _SocialFarmDialog(
          key: ValueKey(client.auth.currentUser?.id),
          client: client,
        ),
      ),
    );

class _SocialFarmDialog extends StatefulWidget {
  const _SocialFarmDialog({required this.client, super.key});

  final SupabaseClient client;

  @override
  State<_SocialFarmDialog> createState() => _SocialFarmDialogState();
}

class _SocialFarmDialogState extends State<_SocialFarmDialog> {
  final _input = TextEditingController();
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _plots = [];
  Map<String, dynamic>? _owner;
  String? _message;
  bool _busy = false;
  bool _loaded = false;

  SupabaseClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    if (_client.auth.currentUser != null) _run(_refresh);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      _message = switch (error.message) {
        'invalid_friend_code' => 'Código de amigo inválido.',
        'crop_unavailable' => 'A colheita deste canteiro está indisponível.',
        'friendship_required' =>
          'Esta fazenda não está na sua lista de amigos.',
        _ => 'Não foi possível concluir. Tente novamente.',
      };
    } catch (_) {
      if (mounted) _message = 'Não foi possível conectar. Tente novamente.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Map<String, dynamic>>> _rows(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    final result = await _client.rpc(function, params: params) as List;
    return result.cast<Map<String, dynamic>>();
  }

  Future<void> _refresh({String? name}) async {
    final profile = await _client.rpc(
      'farm_social_profile',
      params: {if (name != null) 'p_name': name},
    ) as Map<String, dynamic>?;
    final friends = profile == null
        ? <Map<String, dynamic>>[]
        : await _rows('farm_social_friends');
    final inventory = profile == null
        ? <Map<String, dynamic>>[]
        : await _rows('farm_social_inventory');
    if (!mounted) return;
    _profile = profile;
    _friends = friends;
    _inventory = inventory;
    _loaded = true;
  }

  Future<void> _visit(Map<String, dynamic> friend) async {
    final plots = await _rows(
      'farm_social_visit',
      params: {'p_owner': friend['id']},
    );
    if (!mounted) return;
    _plots = plots;
    _owner = friend;
  }

  Future<void> _harvest(Map<String, dynamic> plot) async {
    final owner = _owner!;
    await _client.rpc('farm_social_harvest', params: {'p_plot': plot['id']});
    if (!mounted) return;
    await _visit(owner);
    final inventory = await _rows('farm_social_inventory');
    if (!mounted) return;
    _inventory = inventory;
    _message = 'Colheita registrada no armazém social.';
  }

  Future<void> _saveName() async {
    final name = _input.text.trim();
    if (name.isEmpty) {
      _message = 'Informe um nome para sua fazenda.';
      return;
    }
    await _refresh(name: name);
    if (mounted) _input.clear();
  }

  Future<void> _addFriend() async {
    final code = _input.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
        .hasMatch(code)) {
      _message = 'Cole o código de amigo completo.';
      return;
    }
    await _client.rpc('farm_social_add_friend', params: {'p_code': code});
    if (mounted) _input.clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final owner = _owner;
    return AlertDialog(
      title: Text(
          owner == null ? 'Amigos' : 'Fazenda de ${owner['display_name']}'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_message case final message?) Text(message),
            if (_client.auth.currentUser == null)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final launched = await _client.auth.signInWithOAuth(
                            OAuthProvider.facebook,
                            redirectTo: _redirect,
                            authScreenLaunchMode:
                                LaunchMode.externalApplication,
                          );
                          if (!launched && mounted) {
                            _message =
                                'Não foi possível abrir o login do Facebook.';
                          }
                        }),
                child: const Text('Entrar com Facebook'),
              )
            else if (!_loaded)
              TextButton(
                onPressed: _busy ? null : () => _run(_refresh),
                child: const Text('Carregar perfil'),
              )
            else if (profile == null) ...[
              TextField(
                controller: _input,
                enabled: !_busy,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Nome da fazenda'),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _run(_saveName),
                child: const Text('Criar fazenda de teste'),
              ),
            ] else if (owner != null) ...[
              for (final plot in _plots)
                ListTile(
                  title: Text('${plot['crop']}'),
                  subtitle: Text('${plot['remaining']} disponível(is)'),
                  trailing: TextButton(
                    onPressed: _busy ||
                            plot['claimed'] == true ||
                            plot['ready'] != true ||
                            plot['remaining'] == 0
                        ? null
                        : () => _run(() => _harvest(plot)),
                    child: Text(plot['claimed'] == true ? 'Colhido' : 'Colher'),
                  ),
                ),
            ] else ...[
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await Clipboard.setData(
                            ClipboardData(
                                text: profile['friendCode'] as String),
                          );
                          if (mounted) _message = 'Código de amigo copiado.';
                        }),
                icon: const Icon(Icons.copy),
                label: const Text('Copiar meu código de amigo'),
              ),
              TextField(
                controller: _input,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Código do amigo'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(_addFriend),
                child: const Text('Adicionar amigo'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(_refresh),
                child: const Text('Atualizar lista'),
              ),
              for (final friend in _friends)
                ListTile(
                  title: Text('${friend['display_name']}'),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _run(() => _visit(friend)),
                    child: const Text('Visitar'),
                  ),
                ),
              const Text('Armazém social'),
              if (_inventory.isEmpty) const Text('Nenhuma colheita de visita.'),
              for (final item in _inventory)
                Text('${item['crop']} · ${item['quantity']}'),
            ],
          ],
        ),
      ),
      actions: [
        if (_client.auth.currentUser != null && owner == null)
          TextButton(
            onPressed: _busy ? null : () => _run(() => _client.auth.signOut()),
            child: const Text('Sair da conta'),
          ),
        if (owner != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _owner = null;
                      _message = null;
                    }),
            child: const Text('Voltar'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
