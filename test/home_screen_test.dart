import 'package:fazendinhaidle/main.dart';
import 'package:fazendinhaidle/models/player.dart';
import 'package:fazendinhaidle/ui/widgets/plot_widget.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewport in const [(390.0, 844.0), (1280.0, 720.0)]) {
    testWidgets('navega pelos canteiros em ${viewport.$1} × ${viewport.$2}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(viewport.$1, viewport.$2);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(FazendinhaApp(player: Player.initial()));
      await tester.pumpAndSettle();
      final plots = find.byType(PlotWidget);
      expect(plots, findsNWidgets(4));

      await tester.tap(plots.first);
      await tester.pumpAndSettle();
      expect(find.text('Canteiro 1 · Terra vazia'), findsOneWidget);

      await tester.tap(find.byTooltip('Próximo canteiro'));
      await tester.pumpAndSettle();
      expect(find.text('Canteiro 2 · Terra vazia'), findsOneWidget);

      await tester.tap(find.byTooltip('Visão geral'));
      await tester.pumpAndSettle();
      expect(find.text('Canteiro 2 · Terra vazia'), findsNothing);
    });
  }
}
