# Little Farm

Jogo Flutter para Android e iOS. Prepare a terra com a **Enxada** quando
necessário e use **Regar** para umedecê-la. Compre sementes na **Loja**,
selecione uma no estoque **Sementes** e toque no canteiro úmido. O indicador
do canteiro mostra a ação em andamento, saúde e crescimento. A saúde só cai após a
maturação. A janela de colheita é 48 vezes o tempo base de crescimento de cada
cultura, limitada a 48 horas. A enxada limpa cultivos que passaram desse prazo.

Compre **Fertilizante** na Loja e use a ferramenta **Adubo** em um cultivo
em crescimento. Cada aplicação consome uma unidade e reduz em 25% o tempo
que ainda falta para amadurecer.

Use **Colher** para ganhar XP e enviar a produção ao **Armazém**, onde você
pode vender por espécie ou vender tudo. **Login diário** registra o acesso pela data do servidor
em Brasília. Perder uma data retorna ao Dia 1. Faça resgates no dia em que
forem liberados. As recompensas crescem até o marco do Dia 7 e repetem o ciclo
se a sequência continuar. O cultivo funciona offline.

O jogo abre em paisagem. O progresso é salvo no Hive e o crescimento usa o
tempo decorrido desde o plantio, incluindo o tempo com o aplicativo fechado.

Com o Flutter e um celular ou emulador configurado, execute:

```sh
flutter pub get
flutter run
```

O Android usa o banner de teste do AdMob. Para rodar sem anúncios de teste,
use `flutter run --dart-define=ENABLE_TEST_ADS=false`. Para a prévia no
navegador, use `flutter run -d chrome`.

## Serviço de login diário

Execute com Python 3.10 ou posterior e os dados de fuso horário IANA instalados:

```sh
python3 -m server.visit_rewards --db visits.sqlite3 --web-origin=http://localhost:4173
```

Em outro terminal, inicie o cliente:

```sh
flutter run -d chrome --web-port=4173 --dart-define=VISIT_REWARDS_URL=http://127.0.0.1:8090/
```

Para Android/iOS, configure
`VISIT_REWARDS_URL` com a URL HTTPS do serviço. Hospede o serviço atrás de um
proxy TLS com banco persistente. Sem URL, o painel de visitas informa que a
conexão com o serviço está indisponível.

O serviço identifica o save por uma chave aleatória por instalação. A API v2
começa uma nova sequência e conserva os créditos acumulados da API v1.
O saldo da fazenda permanece local. A chave de instalação fica no Hive e não
oferece recuperação por conta após apagar os dados do aplicativo.

Com a URL configurada, o app pede permissão para notificações no Android e no
iOS. Se autorizadas, o aparelho agenda um lembrete diário para as 20h de Brasília.
O Android pode adiar a entrega conforme as regras de economia de bateria.

```sh
python3 -m unittest server.test_visit_rewards
flutter test
```
