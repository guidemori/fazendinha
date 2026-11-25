# Little Farm

Jogo Flutter para Android e iOS. Toque em um canteiro vazio para escolher
uma semente ou em um cultivo maduro para colher. Use o botão de melhorias
para comprar upgrades e o losango de expansão para comprar novos canteiros.

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
