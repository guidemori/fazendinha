# Little Farm

Jogo Flutter para Android e iOS. Prepare a terra com a **Enxada** quando
necessário e use **Regar** para umedecê-la. Compre sementes na **Loja**,
selecione uma no estoque **Sementes** e toque no canteiro úmido. O indicador
do canteiro mostra a ação em andamento, saúde e crescimento. Cultivos maduros
podem ser recolhidos por 48 horas. A enxada limpa cultivos que passaram desse prazo.

Use **Colher** para ganhar XP e enviar a produção ao **Armazém**, onde você
pode vender por espécie ou vender tudo. **Visitas de 7 dias** registra uma data
local por dia de acesso e libera recompensas crescentes em moedas e sementes.

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
