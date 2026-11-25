# Little Farm

Jogo Flutter para Android e iOS. Escolha a semente na barra inferior e
toque nos canteiros preparados para plantar. Use **Colher** nos cultivos
maduros para ganhar XP e colocar a produção no cesto. Use **Vender** para
converter o cesto em moedas e **Preparar** para arar a terra após a colheita.
O painel de nível mostra o progresso até o próximo nível.

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
