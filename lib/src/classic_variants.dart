import 'tableau_variant.dart';

/// Klasik solitaire kuralları. Zorluk 1–10 bazı ayarları değiştirir.

List<int> _klondikeDown(int n) => [for (var i = 0; i < n; i++) i];

TableauVariant klondike(int d) => TableauVariant(
      dealDown: _klondikeDown(7),
      dealUp: List.filled(7, 1),
      build: Build.altColor,
      pick: Pick.ordered,
      empty: Empty.king,
      draw: d >= 7 ? 3 : 1,
      redeals: -1,
    );

TableauVariant freeCell(int d) => TableauVariant(
      dealDown: List.filled(8, 0),
      dealUp: const [7, 7, 7, 7, 6, 6, 6, 6],
      build: Build.altColor,
      pick: Pick.supermove,
      empty: Empty.any,
      cells: d >= 10 ? 3 : 4,
    );

/// Spider: 1–6 tek renk, 7–10 iki renk.
TableauVariant spider(int d) => TableauVariant(
      decks: 2,
      suits: d <= 6 ? const [0] : const [0, 1],
      dealDown: const [5, 5, 5, 5, 4, 4, 4, 4, 4, 4],
      dealUp: List.filled(10, 1),
      build: Build.anySuit,
      seqBuild: Build.sameSuit,
      pick: Pick.ordered,
      empty: Empty.any,
      stockToTableau: true,
      noEmptyForDeal: true,
      foundations: false,
    );

TableauVariant yukon(int d) => TableauVariant(
      dealDown: const [0, 1, 2, 3, 4, 5, 6],
      dealUp: const [1, 5, 5, 5, 5, 5, 5],
      build: Build.altColor,
      pick: Pick.anyFaceUp,
      empty: Empty.king,
    );

TableauVariant scorpion(int d) => TableauVariant(
      dealDown: const [3, 3, 3, 3, 0, 0, 0],
      dealUp: const [4, 4, 4, 4, 7, 7, 7],
      build: Build.sameSuit,
      pick: Pick.anyFaceUp,
      empty: Empty.king,
      stockToTableau: true,
      stockDealPiles: 3,
      foundations: false,
    );

TableauVariant fortyThieves(int d) => TableauVariant(
      decks: 2,
      dealDown: List.filled(10, 0),
      dealUp: List.filled(10, 4),
      build: Build.sameSuit,
      pick: Pick.supermove,
      empty: Empty.any,
      draw: 1,
      redeals: d <= 5 ? 2 : 1,
    );

TableauVariant canfield(int d) => TableauVariant(
      dealDown: List.filled(4, 0),
      dealUp: List.filled(4, 1),
      reserve: 13,
      baseFromFirst: true,
      wrap: true,
      build: Build.altColor,
      pick: Pick.ordered,
      empty: Empty.any,
      autoFillFromReserve: true,
      draw: d >= 6 ? 3 : 1,
      redeals: -1,
    );
