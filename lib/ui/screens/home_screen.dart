import 'package:flutter/material.dart';

import '../../models/player.dart';
import '../widgets/plot_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.player});

  final Player player;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedPlot;

  void _step(int delta) {
    final count = widget.player.plots.length;
    if (count == 0) return;

    final current = _selectedPlot ?? (delta > 0 ? -1 : 0);
    setState(() => _selectedPlot = (current + delta) % count);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final plots = player.plots;
    final selected = _selectedPlot;
    final plot =
        selected != null && selected < plots.length ? plots[selected] : null;

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return Scaffold(
      backgroundColor: const Color(0xff253f29),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: isPortrait ? 1.23 : 16 / 9,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 800,
                      height: 450,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ExcludeSemantics(
                            child: Image.asset(
                              'assets/images/farm.webp',
                              fit: BoxFit.fill,
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final height = constraints.maxHeight;
                              final columns =
                                  (plots.length / 2).ceil().clamp(2, 8);
                              final rows = (plots.length / columns).ceil();
                              final span = (columns + rows - 2).clamp(2, 1000);
                              final stepX = width * .18 / span;
                              final stepY = height * .16 / span;
                              final tileWidth = stepX * 2;
                              final tileHeight = stepY * 2;

                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (var index = 0;
                                      index < plots.length;
                                      index++)
                                    Positioned(
                                      left: width * .40 +
                                          (index % columns - index ~/ columns) *
                                              stepX -
                                          tileWidth / 2,
                                      top: height * .55 +
                                          (index % columns + index ~/ columns) *
                                              stepY,
                                      width: tileWidth,
                                      height: tileHeight,
                                      child: PlotWidget(
                                        plot: plots[index],
                                        number: index + 1,
                                        selected: index == selected,
                                        onTap: () => setState(
                                            () => _selectedPlot = index),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _Panel(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 15,
                          backgroundColor: Color(0xffe9efad),
                          child: Icon(
                            Icons.spa_rounded,
                            color: Color(0xff426e31),
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Fazendinha',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.monetization_on_rounded,
                          color: Color(0xffffdb72),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Semantics(
                          label: 'Moedas',
                          child: Text('${player.coins}'),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (plot != null && selected != null) ...[
                        _Panel(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              'Canteiro ${selected + 1} · '
                              '${plot.plantedCrop?.label ?? 'Terra vazia'}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _Panel(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: plots.isEmpty ? null : () => _step(-1),
                              tooltip: 'Canteiro anterior',
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            IconButton(
                              onPressed: plots.isEmpty
                                  ? null
                                  : () => setState(
                                        () => _selectedPlot =
                                            _selectedPlot == null ? 0 : null,
                                      ),
                              tooltip: plot == null
                                  ? 'Inspecionar canteiros'
                                  : 'Visão geral',
                              isSelected: plot != null,
                              icon: const Icon(Icons.grid_view_rounded),
                              selectedIcon: const Icon(Icons.landscape_rounded),
                            ),
                            IconButton(
                              onPressed: plots.isEmpty ? null : () => _step(1),
                              tooltip: 'Próximo canteiro',
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xfffff7d8);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xf02c472c),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xff9fbe67)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55304220),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(foregroundColor: foreground),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: foreground,
              fontFamily: 'FarmRoboto',
              fontSize: 14,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
