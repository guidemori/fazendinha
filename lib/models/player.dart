import 'plot.dart';

/// Estado central do jogador. Nesta fase, apenas moedas e canteiros.
class Player {
  Player({
    required this.coins,
    required this.plotCount,
    required this.plots,
  });

  factory Player.initial({int plotCount = 4}) {
    return Player(
      coins: 0,
      plotCount: plotCount,
      plots: List.generate(plotCount, (i) => Plot(id: 'plot_$i')),
    );
  }

  int coins;
  int plotCount;
  List<Plot> plots;
}