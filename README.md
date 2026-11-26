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

## Piloto social no Android

Crie um projeto Supabase e aplique a migração
`supabase/migrations/20261126000100_social_pilot.sql`. Configure o provedor
Facebook no Supabase usando o ID e o segredo do app da Meta. Na Meta, permita
o callback HTTPS mostrado no painel do Supabase e adicione as contas que
participarão do piloto. Configure a URL de retorno
`com.guidemori.fazendinhaidle://social-login` na lista de URLs permitidas do
Supabase. O segredo do Facebook fica no Supabase.

Execute em um aparelho Android conectado:

```bash
flutter run -d <id-do-aparelho> \
  --dart-define=SUPABASE_URL=https://<projeto>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<chave-publicavel>
```

O botão **Amigos** aparece com essa configuração. Entre via Facebook, crie um
perfil e copie o código de amigo. Na segunda conta, repita o login e cole o
código para vincular as duas fazendas. Compartilhe o código somente com quem
você quer adicionar, pois usá-lo estabelece a amizade imediatamente.

Cada perfil tem um canteiro de teste com uma cenoura pronta. Visite a primeira
fazenda com a segunda conta e colha a cenoura. A operação debita uma unidade
do canteiro e registra a colheita no armazém social da conta visitante. Uma
repetição da mesma colheita não dá outra unidade. A fazenda principal continua
salva no Hive. Esta fase usa amizades por código. A descoberta automática de
amigos do Facebook exige configurar o acesso a `user_friends`.

### Amigos do Facebook e convites

Aplique também a migração `20261126000200_facebook_friends.sql` e implante a
Edge Function `facebook-friends` no mesmo projeto Supabase:

```bash
supabase functions deploy facebook-friends --project-ref <projeto> --no-verify-jwt
```

A função valida o JWT com o Supabase Auth antes de consultar a Meta. A
migração exige que a identidade do Facebook consultada corresponda à conta do
Little Farm. O app solicita `user_friends` no login. Com acesso à permissão
habilitado na Meta, duas contas que autorizaram essa permissão e criaram seus
perfis aparecem automaticamente em **Amigos** após sincronizar. A confirmação
vale por sete dias e pode ser renovada ao atualizar a lista ou reconectar. A
sincronização bem-sucedida substitui os vínculos da Meta daquela conta e
preserva as amizades por código. Falhas de rede preservam a última confirmação
até que ela expire.

Para incluir o link de instalação no botão **Convidar para jogar**, passe
`--dart-define=LITTLE_FARM_INSTALL_URL=https://<link-de-instalacao>`. O botão
abre o compartilhamento do Android com o texto e o código de amigo. O
jogador escolhe o destinatário e confirma o envio no app de mensagens.
