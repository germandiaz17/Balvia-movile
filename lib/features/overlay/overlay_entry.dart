// Overlay entry point and UI.
//
// ISOLATE BOUNDARY:
//   This file is loaded by a separate FlutterEngine started by
//   flutter_overlay_window. It has NO access to the main app's Riverpod
//   providers, HTTP client, or tokens. All data comes from:
//     - SQLite via a dedicated Drift WAL connection (openOverlayDatabase).
//     - SharedPreferences for settings (readable cross-isolate after reload).
//
// The overlay has two visual states:
//   Collapsed → half-pill "tube" docked flush to a screen edge (flat side
//               against the edge, rounded side facing the screen).
//   Expanded  → capture card centered in the upper half of the screen; the
//               amount is typed with the system keyboard (window switches to
//               a focusable flag while expanded so the IME can appear).

// ignore_for_file: use_build_context_synchronously

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/amount_formatter.dart';
import '../../core/amount_input_formatter.dart';
import '../../core/theme.dart';
import '../../data/local/app_database.dart' as db;
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../data/sync/sync_engine.dart'
    show generateClientId, generateLocalId;
import '../../shared/balvia_logo.dart';
import 'overlay_database.dart';
import 'overlay_logic.dart';
import 'overlay_settings.dart';

// ---------------------------------------------------------------------------
// @pragma entry-point — called by flutter_overlay_window
// ---------------------------------------------------------------------------

/// Secondary entry point for the overlay FlutterEngine.
/// Must be a top-level function annotated with @pragma("vm:entry-point").
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

// ---------------------------------------------------------------------------
// Root widget of the overlay engine
// ---------------------------------------------------------------------------

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BalviaTheme.light(),
      darkTheme: BalviaTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _OverlayRoot(),
    );
  }
}

// ---------------------------------------------------------------------------
// Root — manages state, loads data, handles expand/collapse
// ---------------------------------------------------------------------------

class _OverlayRoot extends StatefulWidget {
  const _OverlayRoot();

  @override
  State<_OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<_OverlayRoot> {
  bool _expanded = false;
  bool _loading = true;
  String? _initError;

  OverlaySettings _settings = const OverlaySettings();
  db.AppDatabase? _database;

  List<Category> _categories = [];
  List<db.Account> _accounts = [];
  String? _todaySpend; // formatted COP string
  String? _balance; // formatted COP string

  // Quick-capture state (managed locally — no Riverpod here).
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  String? _selectedCategoryId;
  String? _selectedAccountId;
  String _description = '';
  bool _isSaving = false;
  String? _saveError;
  String? _successMessage;

  /// Whether the bubble is docked on the LEFT screen edge (flat side left).
  /// Initial dock is the right edge (window alignment: centerRight).
  bool _dockedLeft = false;

  /// Window position (dp) saved right before expanding, restored on collapse
  /// so the bubble returns to the edge the user left it on.
  OverlayPosition? _savedPosition;

  /// Raw digits currently in the amount field (thousand separators stripped).
  String get _rawDigits => _amountController.text.replaceAll('.', '');

  @override
  void initState() {
    super.initState();
    _initialize();
    // Listen for messages from the main app (e.g. "refresh" after settings change).
    FlutterOverlayWindow.overlayListener.listen(_onMessage);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    _database?.close();
    super.dispose();
  }

  /// Screen size in dp. The overlay FlutterView is only the small overlay
  /// window, so MediaQuery is useless here — resolve from the Display API.
  Size _screenSizeDp() {
    final display = WidgetsBinding.instance.platformDispatcher.displays.first;
    return display.size / display.devicePixelRatio;
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _settings = overlaySettingsFromPrefs(prefs);
      _database = await openOverlayDatabase();
      await _loadData();
    } catch (e) {
      // Surface init failures in logcat — the collapsed bubble can only show
      // a generic error tint, which is undebuggable on its own.
      debugPrint('Overlay init failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _initError = e.toString();
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadData() async {
    final dbRef = _database;
    if (dbRef == null) return;

    // Categories.
    final catRows = await dbRef.categoriesDao.getAll();
    final cats = catRows
        .where((r) => r.deletedAt == null)
        .map(
          (r) => Category(
            id: r.id,
            name: r.name,
            categoryType: r.categoryType,
            isSystem: r.isSystem,
            parentId: r.parentId,
            icon: r.icon,
            color: r.color,
            displayOrder: r.displayOrder,
          ),
        )
        .toList();

    // Accounts.
    final accRows = await dbRef.accountsDao.getAll();

    // Default account.
    String? defaultAccId = _settings.defaultAccountId;
    if (defaultAccId == null && accRows.isNotEmpty) {
      defaultAccId = accRows.first.id;
    }

    // Compute most-used categories.
    List<Transaction> recentTxs = [];
    try {
      final period = await dbRef.trackingPeriodsDao.getActive();
      if (period != null) {
        final rows = await dbRef.transactionsDao.getByPeriod(period.id);
        recentTxs = rows
            .where((r) => r.deletedAt == null)
            .map(
              (r) => Transaction(
                id: r.id,
                trackingPeriodId: r.trackingPeriodId,
                accountId: r.accountId,
                transactionType: r.transactionType,
                amount: Decimal.parse(r.amount),
                currency: r.currency,
                transactionDate: r.transactionDate,
                createdAt: DateTime.parse(r.createdAt),
                categoryId: r.categoryId,
              ),
            )
            .toList();
      }
    } catch (_) {}
    final topCats = mostUsedExpenseCategories(recentTxs, cats);

    // Today spend and balance.
    String? todaySpend;
    String? balance;
    if (_settings.showTodaySpend) {
      try {
        final period = await dbRef.trackingPeriodsDao.getActive();
        if (period != null) {
          final today = DateTime.now().toIso8601String().substring(0, 10);
          final txRows = await dbRef.transactionsDao.getByPeriod(period.id);
          final total = txRows
              .where(
                (t) =>
                    t.transactionDate == today &&
                    t.transactionType == 'expense' &&
                    t.deletedAt == null,
              )
              .fold(Decimal.zero, (s, t) => s + Decimal.parse(t.amount));
          todaySpend = AmountFormatter.formatCOP(total);
        }
      } catch (_) {}
    }
    if (_settings.showBalance && defaultAccId != null && accRows.isNotEmpty) {
      try {
        final acc = accRows.firstWhere(
          (a) => a.id == defaultAccId,
          orElse: () => accRows.first,
        );
        balance = AmountFormatter.formatCOP(Decimal.parse(acc.currentBalance));
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _categories = topCats;
        _accounts = accRows;
        _selectedAccountId = defaultAccId;
        _todaySpend = todaySpend;
        _balance = balance;
      });
    }
  }

  void _onMessage(dynamic message) async {
    if (message is String && message == 'refresh') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final previousSize = _settings.bubbleSize;
      setState(() {
        _settings = overlaySettingsFromPrefs(prefs);
      });
      // Live-resize the collapsed window when the size setting changed.
      if (!_expanded && _settings.bubbleSize != previousSize) {
        final size = clampBubbleSize(_settings.bubbleSize);
        await FlutterOverlayWindow.resizeOverlay(
          collapsedWindowWidth(size),
          collapsedWindowHeight(size),
          true,
        );
      }
      await _loadData();
    }
  }

  // ---- Expand / collapse ----

  /// Expanded capture card dimensions (dp). Sized for: header + amount field
  /// + category chips + input row + buttons (the numeric keypad is gone — the
  /// system keyboard is used instead).
  static const int _kCardW = 340;
  static const int _kCardH = 340;
  static const int _kCardTopMargin = 48;

  Future<void> _toggleExpand() async {
    final willExpand = !_expanded;
    setState(() {
      _expanded = willExpand;
      if (!willExpand) {
        _amountController.clear();
        _selectedCategoryId = null;
        _description = '';
        _saveError = null;
        _successMessage = null;
      }
    });

    if (willExpand) {
      // Remember where the bubble is so collapse can put it back on the same
      // edge. Then: focusable flag (so the IME can appear) → resize → center.
      // Sequential awaits — the Java side must never see concurrent writers.
      _savedPosition = await FlutterOverlayWindow.getOverlayPosition();
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
      await FlutterOverlayWindow.resizeOverlay(_kCardW, _kCardH, false);
      final screen = _screenSizeDp();
      final offset = expandedOverlayOffset(
        screenW: screen.width,
        screenH: screen.height,
        cardW: _kCardW,
        cardH: _kCardH,
        topMargin: _kCardTopMargin,
      );
      await FlutterOverlayWindow.moveOverlay(
        OverlayPosition(offset.x.toDouble(), offset.y.toDouble()),
      );
      // The window needs a layout pass to become focusable before the IME
      // will honor a focus request.
      await Future.delayed(const Duration(milliseconds: 120));
      if (mounted && _expanded) _amountFocus.requestFocus();
    } else {
      // Dismiss the IME first; switching back to a non-focusable flag at the
      // end also guarantees it cannot linger.
      FocusManager.instance.primaryFocus?.unfocus();
      final size = clampBubbleSize(_settings.bubbleSize);
      await FlutterOverlayWindow.resizeOverlay(
        collapsedWindowWidth(size),
        collapsedWindowHeight(size),
        true,
      );
      final saved = _savedPosition;
      if (saved != null) {
        await FlutterOverlayWindow.moveOverlay(saved);
      }
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    }
  }

  void _collapse() {
    if (_expanded) _toggleExpand();
  }

  /// Called on every pointer-up over the collapsed bubble. After the plugin's
  /// edge-snap animation settles, reads the window position to work out which
  /// edge the bubble is docked on and mirrors the pill shape accordingly.
  Future<void> _detectDockSide() async {
    if (_expanded) return;
    // Snap animation: 25ms ticks with geometric 2/3 decay — settled well
    // before 400ms.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || _expanded) return;
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      final screenW = _screenSizeDp().width;
      // Window gravity is RIGHT|CENTER: x is the offset from the RIGHT edge,
      // so a large x means the bubble sits on the LEFT edge.
      final dockedLeft = pos.x > screenW / 2;
      if (mounted && dockedLeft != _dockedLeft) {
        setState(() => _dockedLeft = dockedLeft);
      }
    } catch (_) {}
  }

  // ---- Amount helpers ----

  /// Quick "×1000" affordance: COP amounts are large, and this was the most
  /// useful key of the old in-card keypad, so it survives as a suffix chip.
  void _appendThousands() {
    final digits = _rawDigits;
    if (digits.isEmpty) return;
    final next = '${digits}000';
    if (next.length > 10) return;
    // Programmatic writes skip inputFormatters — format here.
    _amountController.value = TextEditingValue(
      text: AmountFormatter.formatDisplay(next),
      selection: TextSelection.collapsed(
        offset: AmountFormatter.formatDisplay(next).length,
      ),
    );
    setState(() => _saveError = null);
  }

  // ---- Save ----

  Future<void> _save() async {
    if (_rawDigits.isEmpty) {
      setState(() => _saveError = 'Ingresa un monto mayor a cero');
      return;
    }
    if (_selectedAccountId == null) {
      setState(() => _saveError = 'Configura una cuenta por defecto');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final dbRef = _database!;
      final period = await dbRef.trackingPeriodsDao.getActive();
      if (period == null) {
        setState(() {
          _isSaving = false;
          _saveError = 'Sin periodo activo. Abre Balvia primero.';
        });
        return;
      }

      final amount = Decimal.parse(_rawDigits);
      final now = DateTime.now().toUtc().toIso8601String();
      final date = DateTime.now().toIso8601String().substring(0, 10);

      // Same id scheme as the rest of the app: the sync engine classifies
      // 'local-' ids as creates and the server dedupes on client_id.
      final localId = generateLocalId();
      final clientId = generateClientId();

      final companion = db.TransactionsCompanion.insert(
        id: localId,
        userId: '',
        trackingPeriodId: period.id,
        accountId: _selectedAccountId!,
        transactionType: 'expense',
        amount: amount.toStringAsFixed(2),
        currency: 'COP',
        transactionDate: date,
        createdAt: now,
        updatedAt: now,
        categoryId: drift.Value(_selectedCategoryId),
        description: drift.Value(
          _description.trim().isEmpty ? null : _description.trim(),
        ),
        clientId: drift.Value(clientId),
        syncStatus: const drift.Value('pending'),
      );

      await dbRef.transactionsDao.upsert(companion);

      // Notify main app to trigger a sync + UI refresh.
      FlutterOverlayWindow.shareData('refresh');

      _amountController.clear();
      setState(() {
        _isSaving = false;
        _successMessage = 'Gasto registrado';
        _selectedCategoryId = null;
        _description = '';
      });

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) _collapse();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _saveError = e.toString();
      });
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildCollapsed();
    if (_initError != null) return _buildCollapsed(error: true);
    if (_expanded) return _buildExpanded(context);
    return _buildCollapsed();
  }

  // -- Collapsed bubble: half-pill "tube" docked flush to a screen edge --
  //
  // The flat side sits against the screen edge; the opposite side is a full
  // semicircle facing the open screen. The shape mirrors depending on which
  // edge the bubble is docked to (detected after each drag in _detectDockSide).

  Widget _buildCollapsed({bool error = false}) {
    final color = _settings.bubbleColor;
    final size = clampBubbleSize(_settings.bubbleSize);
    final radius = Radius.circular(size / 2);
    // The Listener sees every pointer-up (it does not join the gesture arena,
    // so tap-to-expand keeps working) — used to re-detect the docked side
    // after the plugin's edge-snap animation.
    return Listener(
      onPointerUp: (_) => _detectDockSide(),
      child: Align(
        // Flat side flush against the window edge that touches the screen.
        alignment: _dockedLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: GestureDetector(
          onTap: _toggleExpand,
          child: Opacity(
            opacity: _settings.opacity.clamp(0.3, 1.0),
            child: Container(
              width: bubbleWidth(size).toDouble(),
              height: size,
              decoration: BoxDecoration(
                color: error ? Colors.red : color,
                borderRadius: _dockedLeft
                    ? BorderRadius.horizontal(right: radius)
                    : BorderRadius.horizontal(left: radius),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    // Shadow falls toward the open side of the screen.
                    offset: Offset(_dockedLeft ? 2 : -2, 2),
                  ),
                ],
              ),
              child: Center(
                child: BalviaLogoMark(size: size * 0.5, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- Expanded card --

  Widget _buildExpanded(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(BalviaTheme.radiusLg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(cs),
              if (_successMessage != null) _buildSuccess(),
              _buildAmountDisplay(cs),
              _buildCategoryChips(),
              const SizedBox(height: 4),
              _buildInputRow(cs),
              if (_saveError != null) _buildError(),
              const SizedBox(height: 2),
              _buildButtons(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      decoration: const BoxDecoration(
        color: BalviaTheme.seed,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BalviaTheme.radiusLg),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          BalviaLogoMark(size: 20, color: Colors.white),
          const SizedBox(width: 8),
          if (_settings.showTodaySpend && _todaySpend != null)
            Text(
              'Hoy: -$_todaySpend',
              style: BalviaTheme.captionStyle(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          if (_settings.showTodaySpend &&
              _todaySpend != null &&
              _settings.showBalance &&
              _balance != null)
            Text(
              '  ·  ',
              style: BalviaTheme.captionStyle(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          if (_settings.showBalance && _balance != null)
            Text(
              'Saldo: $_balance',
              style: BalviaTheme.captionStyle(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: _collapse,
            child: const Icon(Icons.close, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Text(
        'Gasto registrado',
        style: TextStyle(
          color: BalviaTheme.income,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAmountDisplay(ColorScheme cs) {
    final amountStyle = BalviaTheme.displayStyle(
      color: BalviaTheme.expense,
    ).copyWith(fontSize: 34);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        children: [
          Text(
            'MONTO',
            style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            keyboardType: TextInputType.number,
            inputFormatters: const [CopAmountInputFormatter()],
            textAlign: TextAlign.center,
            style: amountStyle,
            cursorColor: BalviaTheme.expense,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '0',
              hintStyle: amountStyle.copyWith(
                color: BalviaTheme.expense.withValues(alpha: 0.35),
              ),
              prefixText: '\$ ',
              prefixStyle: amountStyle,
              // COP quick-multiplier: appends "000" to the typed digits.
              suffixIcon: TextButton(
                onPressed: _appendThousands,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 32),
                  foregroundColor: cs.onSurfaceVariant,
                ),
                child: const Text(
                  ',000',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            onChanged: (_) {
              if (_saveError != null) setState(() => _saveError = null);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    if (_categories.isEmpty) return const SizedBox(height: 6);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        separatorBuilder: (_, i) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final cat = _categories[i];
          final selected = _selectedCategoryId == cat.id;
          return _CategoryChip(
            category: cat,
            selected: selected,
            onTap: () =>
                setState(() => _selectedCategoryId = selected ? null : cat.id),
          );
        },
      ),
    );
  }

  Widget _buildInputRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (_accounts.isNotEmpty) ...[
            _AccountChip(
              accounts: _accounts,
              selectedId: _selectedAccountId,
              onSelect: (id) => setState(() => _selectedAccountId = id),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                onChanged: (v) => setState(() => _description = v),
                style: BalviaTheme.bodyStyle(
                  color: cs.onSurface,
                ).copyWith(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nombre (opcional)',
                  hintStyle: BalviaTheme.captionStyle(
                    color: cs.onSurfaceVariant,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Text(
        _saveError!,
        style: const TextStyle(color: BalviaTheme.expense, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildButtons(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _collapse,
              // Narrow slot (1/3 of a 340dp card): trim the default padding
              // so "Cancelar" fits on one line.
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: const Text('Cancelar', maxLines: 1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: BalviaTheme.seed,
                foregroundColor: Colors.white,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category chip widget
// ---------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color catColor = BalviaTheme.seed;
    try {
      if (category.color != null) {
        final hex = category.color!.replaceAll('#', '');
        if (hex.length == 6) {
          catColor = Color(int.parse('FF$hex', radix: 16));
        }
      }
    } catch (_) {}

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? catColor : catColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: catColor, width: 1.5)
              : Border.all(color: catColor.withValues(alpha: 0.3), width: 1),
        ),
        child: Text(
          category.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : catColor,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account chip + picker
// ---------------------------------------------------------------------------

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
  });

  final List<db.Account> accounts;
  final String? selectedId;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = accounts.firstWhere(
      (a) => a.id == selectedId,
      orElse: () => accounts.first,
    );

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 12,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              selected.name,
              style: BalviaTheme.captionStyle(color: cs.onSurface),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Seleccionar cuenta'),
        children: accounts.map((a) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.of(ctx).pop();
              onSelect(a.id);
            },
            child: Text(a.name),
          );
        }).toList(),
      ),
    );
  }
}
