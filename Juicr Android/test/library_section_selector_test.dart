import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/app_state.dart';
import 'package:juicr/src/catalog_item.dart';
import 'package:juicr/src/library_page.dart';
import 'package:juicr/src/visual_style.dart';

void main() {
  testWidgets('library section selector shares semantic and touch activation',
      (tester) async {
    tester.view.physicalSize = const Size(1344, 2992);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previousReady = AppState.preferencesReady.value;
    final previousCatalog = AppState.defaultCatalogEnabled.value;
    final previousLibrary = AppState.library.value;
    final previousContinue = AppState.continueWatching.value;
    final previousCompleted = AppState.completedWatching.value;
    final previousLists = AppState.libraryLists.value;
    addTearDown(() {
      AppState.preferencesReady.value = previousReady;
      AppState.defaultCatalogEnabled.value = previousCatalog;
      AppState.library.value = previousLibrary;
      AppState.continueWatching.value = previousContinue;
      AppState.completedWatching.value = previousCompleted;
      AppState.libraryLists.value = previousLists;
    });

    AppState.preferencesReady.value = true;
    AppState.defaultCatalogEnabled.value = true;
    AppState.library.value = const <String, CatalogItem>{
      '866398': CatalogItem(
        type: MediaType.movie,
        id: '866398',
        name: 'The Beekeeper',
        year: '2024',
      ),
    };
    AppState.continueWatching.value = <String, ContinueWatchingEntry>{};
    AppState.completedWatching.value = <String, CompletedWatchingEntry>{};
    AppState.libraryLists.value = const <LibraryList>[];

    final navigatorObserver = _RecordingNavigatorObserver();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navigatorObserver],
        home: const LibraryPage(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final selector = find.bySemanticsLabel('Library section');
    expect(selector, findsOneWidget);
    final selectorNode = tester.getSemantics(selector);
    expect(
      selectorNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    tester.semantics.tap(find.semantics.byLabel('Library section'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Movies'), findsOneWidget);
    expect(find.byType(JuicrSheetOptionTile), findsNWidgets(5));
    final moviesTile = find.ancestor(
      of: find.text('Movies'),
      matching: find.byType(JuicrSheetOptionTile),
    );
    final moviesOption = tester.widget<JuicrSheetOptionTile>(moviesTile);
    expect(moviesOption.onTap, isNotNull);
    moviesOption.onTap!.call();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSemantics(selector).getSemanticsData().value, 'Movies');
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -1200),
    );
    await tester.pump(const Duration(seconds: 1));

    final movieCard = find.bySemanticsLabel('Open The Beekeeper');
    expect(movieCard, findsOneWidget);
    expect(
      tester
          .getSemantics(movieCard)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    final pushesBeforeCardTap = navigatorObserver.pushes;
    tester.semantics.tap(find.semantics.byLabel('Open The Beekeeper'));
    await tester.pump(const Duration(seconds: 1));
    expect(navigatorObserver.pushes, pushesBeforeCardTap + 1);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(selector);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Series'), findsOneWidget);
    expect(find.byType(JuicrSheetOptionTile), findsNWidgets(5));
    final seriesTile = find.ancestor(
      of: find.text('Series'),
      matching: find.byType(JuicrSheetOptionTile),
    );
    final seriesOption = tester.widget<JuicrSheetOptionTile>(seriesTile);
    expect(seriesOption.onTap, isNotNull);
    seriesOption.onTap!.call();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSemantics(selector).getSemanticsData().value, 'Series');

    await tester.tap(selector);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) pushes += 1;
  }
}
