import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:io' show Platform, exit;
import 'package:flutter_quill/flutter_quill.dart' hide Text;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'dart:convert';
// Removed persistence-related imports
import 'package:bitsdojo_window/bitsdojo_window.dart';

// Default color palette for the mockup-style UI (can be overridden at runtime)
const Color kHeaderColor = Color(0xFF6A3FB5); // dark purple header
const Color kHeaderAccent = Color(0xFF8A4FFF); // thin accent line under header
const Color kBackgroundColor = Color(0xFFE3D1FF); // light purple canvas

// Layout constants
const double kHeaderHeight = 50;
const double kDrawerHeight = 60;
const double kToolbarHeight = 40;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await windowManager.ensureInitialized();
  } catch (_) {}
  Color? initial;
  int currentWindowId = 0; // 0 => main window for desktop_multi_window
  double? argW, argH, argX, argY;
  if (args.isNotEmpty) {
    try {
      // desktop_multi_window passes: ['multi_window', windowId, argumentsJson]
      // If not a multi-window boot, treat args.first as our payload directly.
      String? payload;
      if (args.first == 'multi_window') {
        if (args.length > 1) {
          currentWindowId = int.tryParse(args[1].toString()) ?? 0;
        }
        if (args.length > 2) payload = args[2];
      } else {
        payload = args.first;
      }

      final Map<String, dynamic> data =
          payload != null ? jsonDecode(payload) as Map<String, dynamic> : {};
      final int? bg = data['bg'] as int?;
      if (bg != null) initial = Color(bg);
      final num? w = data['w'] as num?;
      final num? h = data['h'] as num?;
      final num? x = data['x'] as num?;
      final num? y = data['y'] as num?;
      if (w != null && h != null) {
        argW = w.toDouble();
        argH = h.toDouble();
      }
      if (x != null && y != null) {
        argX = x.toDouble();
        argY = y.toDouble();
      }
    } catch (_) {}
  }

  // Configure the window (for both main and newly spawned windows)
  const defaultSize = Size(600, 600);
  final windowOptions = const WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  try {
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setMinimumSize(defaultSize);
      if (argW != null && argH != null) {
        await windowManager.setSize(Size(argW!, argH!));
      } else {
        await windowManager.setSize(defaultSize);
      }
      if (argX != null && argY != null) {
        await windowManager.setPosition(Offset(argX!, argY!));
      } else {
        await windowManager.center();
      }
      await windowManager.setTitle('Sticky Notes');
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {
    // In multi-window (desktop_multi_window) contexts, window_manager may not be
    // attached during early startup of secondary windows. Avoid crashing; we'll
    // continue and let the UI render, then attempt to focus later.
  }

  // On Windows, the runner is configured with BDW_HIDE_ON_STARTUP (bitsdojo_window),
  // so explicitly show the window once it's ready.
  if (Platform.isWindows) {
    try {
      doWhenWindowReady(() {
        appWindow.show();
        // Use window_manager to focus the window; bitsdojo_window doesn't expose focus().
        windowManager.focus();
      });
    } catch (_) {
      // bitsdojo_window may not manage secondary windows; ignore.
    }
  }

  runApp(StickyNotesApp(initialBackground: initial, windowId: currentWindowId));

  // Post-frame fallback: on secondary windows the early waitUntilReadyToShow
  // may have been skipped. Try to apply styling/focus again without blocking.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.show();
      await windowManager.focus();
      // If size/position were provided via args but early init failed,
      // apply them here as a fallback to avoid overlapping windows.
      try {
        if (argW != null && argH != null) {
          await windowManager.setSize(Size(argW!, argH!));
        }
        if (argX != null && argY != null) {
          await windowManager.setPosition(Offset(argX!, argY!));
        }
      } catch (_) {}
    } catch (_) {
      // Ignore if window_manager isn't attached in this context.
    }
  });
}

class StickyNotesApp extends StatelessWidget {
  const StickyNotesApp({super.key, this.initialBackground, this.windowId = 0});

  final Color? initialBackground;
  final int windowId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sticky Notes',
      theme: ThemeData(
        scaffoldBackgroundColor: kBackgroundColor,
        colorScheme: ColorScheme.fromSeed(seedColor: kHeaderColor),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.deepPurple.shade900,
          selectionColor: Colors.deepPurple.shade400.withOpacity(0.35),
        ),
        useMaterial3: true,
      ),
      home: StickyNotePage(
        initialBackground: initialBackground,
        windowId: windowId,
      ),
    );
  }
}

class StickyNotePage extends StatefulWidget {
  const StickyNotePage({super.key, this.initialBackground, this.windowId = 0});

  final Color? initialBackground;
  final int windowId; // 0 == main window

  @override
  State<StickyNotePage> createState() => _StickyNotePageState();
}

class _StickyNotePageState extends State<StickyNotePage> with WindowListener {
  late QuillController _quill;
  bool _menuOpen = false;
  late FocusNode _editorFocusNode;
  late ScrollController _editorScrollController;

  // Theme state (derived shades)
  Color _background = kBackgroundColor;
  Color _headerShade = kHeaderColor;
  Color _accentShade = kHeaderAccent;
  Color _uiShade = const Color(0xFF2E1065); // deep purple fallback

  Color _shiftLightness(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  Color _randomPleasantColor() {
    final seed = DateTime.now().microsecondsSinceEpoch % 360;
    return HSLColor.fromAHSL(1, seed.toDouble(), 0.55, 0.70).toColor();
  }

  Future<void> _openNewNote() async {
    // Clone current theme; do not clone user data
    final color = _background;
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      // Determine visible work area of the display under the current window
      List<Display> displays = [];
      try {
        displays = await screenRetriever.getAllDisplays();
      } catch (_) {}
      Display? display;
      for (final d in displays) {
        final vp = d.visiblePosition ?? const Offset(0, 0);
        final vs = d.visibleSize ?? d.size;
        if (pos.dx >= vp.dx && pos.dy >= vp.dy &&
            pos.dx < vp.dx + vs.width && pos.dy < vp.dy + vs.height) {
          display = d;
          break;
        }
      }
      display ??= await screenRetriever.getPrimaryDisplay();
      final vp = display.visiblePosition ?? const Offset(0, 0);
      final vs = display.visibleSize ?? display.size;
      final left = vp.dx, top = vp.dy, right = vp.dx + vs.width, bottom = vp.dy + vs.height;

      // New window size (slightly smaller than current)
      final newW = size.width * 0.9;
      final newH = size.height * 0.9;
      final clampedW = newW.clamp(360.0, vs.width - 16.0);
      final clampedH = newH.clamp(300.0, vs.height - 16.0);

      // Prefer placing to the right; if off-screen, place to the left; else clamp within screen
      double newX = pos.dx + size.width + 16;
      double newY = pos.dy;
      const margin = 8.0;
      if (newX + clampedW > right - margin) {
        newX = pos.dx - clampedW - 16;
      }
      if (newX < left + margin) newX = left + margin;
      if (newY + clampedH > bottom - margin) newY = math.max(top + margin, bottom - margin - clampedH);

      final window = await DesktopMultiWindow.createWindow(
        jsonEncode({
          'bg': color.value,
          'w': clampedW,
          'h': clampedH,
          'x': newX,
          'y': newY,
        }),
      );
      // Show first to ensure the native window exists, then set the frame.
      await window.show();
      await window.setFrame(Rect.fromLTWH(newX, newY, clampedW, clampedH));
    } catch (_) {
      // Fallback: push a new page in the same window if multi-window is unavailable
      if (mounted) {
        // ignore: use_build_context_synchronously
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StickyNotePage(initialBackground: color),
          ),
        );
      }
    }
  }

  Color _deriveContrast(Color base, double magnitude) {
    final hsl = HSLColor.fromColor(base);
    final sign = hsl.lightness >= 0.5 ? -1.0 : 1.0;
    return _shiftLightness(base, sign * magnitude);
  }

  void _applyTheme(Color base) {
    _background = base;
    _headerShade = _deriveContrast(base, 0.35);
    _accentShade = _deriveContrast(base, 0.20);
    _uiShade = _deriveContrast(base, 0.45);
    setState(() {});
  }

  Future<void> _openThemePicker() async {
    Color temp = _background;
    await showDialog(
      context: context,
      builder: (ctx) {
        final screenW = MediaQuery.of(ctx).size.width;
        final width = math.min(520.0, screenW - 32.0);
        final pickerW = width - 48.0; // padding margins
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Material(
              color: _background.withOpacity(0.92),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App-style header bar
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _headerShade.withOpacity(0.85),
                          _headerShade.withOpacity(0.65),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(color: _accentShade, width: 2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Text(
                          'Choose theme color',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                          splashRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: pickerW,
                        child: ColorPicker(
                          pickerColor: temp,
                          onColorChanged: (c) => temp = c,
                          enableAlpha: false,
                          labelTypes: const [],
                          // Use horizontal hue slider to avoid vertical overflow.
                          paletteType: PaletteType.hsv,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text('Cancel', style: TextStyle(color: _uiShade)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            _applyTheme(temp);
                            Navigator.of(ctx).pop();
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(_accentShade),
                            foregroundColor: const WidgetStatePropertyAll(Colors.white),
                          ),
                          child: const Text('Use Color'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Persistent inline-style toggles
  bool _boldOn = false;
  bool _italicOn = false;
  bool _underlineOn = false;
  bool _strikeOn = false;
  

  @override
  void initState() {
    super.initState();
    _quill = QuillController.basic();
    _editorFocusNode = FocusNode();
    _editorScrollController = ScrollController();
    // Keep buttons in sync with keyboard shortcuts and selection changes
    _quill.addListener(_syncFromController);
    _quill.onSelectionChanged = (_) => _syncFromController();
    // Initialize theme derived shades (allow caller to override initial color)
    _applyTheme(widget.initialBackground ?? _background);
    // Intercept close so we can keep process alive until the last window closes
    windowManager.addListener(this);
    // Prevent native close; we'll decide behavior in onWindowClose.
    // On secondary engines this method may be missing; ignore failures.
    // Don't await inside initState.
    // ignore: discarded_futures
    windowManager.setPreventClose(true).catchError((_) {});
    // Basic method handler so other windows can check liveness (e.g., sub -> main ping)
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'ping') return 'pong';
      if (call.method == 'isVisible') {
        try {
          return await windowManager.isVisible();
        } catch (_) {
          return false;
        }
      }
      return null;
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _quill.removeListener(_syncFromController);
    _quill.dispose();
    super.dispose();
  }

  Future<void> _performCloseAction() async {
    // Determine if this is the main window (0) or a sub-window (>0)
    final isMain = widget.windowId == 0;
    final subIds = await DesktopMultiWindow.getAllSubWindowIds();

    if (isMain) {
      // Never exit the app automatically; just hide the main window when
      // closed. Other windows continue to run if any exist.
      await windowManager.hide();
      return;
    }

    // Sub-window
    bool mainAlive = true;
    bool mainVisible = false;
    try {
      final res = await DesktopMultiWindow.invokeMethod(0, 'isVisible');
      if (res is bool) mainVisible = res;
    } catch (_) {
      mainAlive = false;
    }
    await windowManager.destroy();
    // Do not exit the app from a sub-window close. The process should remain
    // alive as long as the main window exists (visible or hidden).
  }

  @override
  void onWindowClose() {
    () async {
      // Determine if this is the main window (0) or a sub-window (>0)
      final isMain = widget.windowId == 0;
      // Current subwindow list (excludes main window id 0)
      List<int> subIds = await DesktopMultiWindow.getAllSubWindowIds();

      if (isMain) {
        // Keep the process alive; hide the main window instead of exiting.
        await windowManager.hide();
      } else {
        await windowManager.destroy();
        // Do not exit the app when a sub-window closes.
      }
    }();
  }

  void _preserveSelection(VoidCallback action) {
    final selBefore = _quill.selection;
    action();
    if (!selBefore.isCollapsed) {
      _quill.updateSelection(selBefore, ChangeSource.local);
    }
  }

  void _syncFromController() {
    final attrs = _quill.getSelectionStyle().attributes;
    final b = attrs.containsKey(Attribute.bold.key);
    final i = attrs.containsKey(Attribute.italic.key);
    final u = attrs.containsKey(Attribute.underline.key);
    final s = attrs.containsKey(Attribute.strikeThrough.key);
    if (b != _boldOn || i != _italicOn || u != _underlineOn || s != _strikeOn) {
      setState(() {
        _boldOn = b;
        _italicOn = i;
        _underlineOn = u;
        _strikeOn = s;
      });
    }
  }

  // Toggle inline attributes like bold/italic/underline/strike
  void _toggleInline(Attribute attribute) {
    // Flip persistent state
    switch (attribute.key) {
      case 'bold':
        _boldOn = !_boldOn;
        break;
      case 'italic':
        _italicOn = !_italicOn;
        break;
      case 'underline':
        _underlineOn = !_underlineOn;
        break;
      case 'strike':
        _strikeOn = !_strikeOn;
        break;
    }

    // If there is a selection, apply/remove formatting to that selection
    final sel = _quill.selection;
    if (!sel.isCollapsed) {
      bool turningOn = true;
      if (attribute.key == 'bold') turningOn = _boldOn;
      else if (attribute.key == 'italic') turningOn = _italicOn;
      else if (attribute.key == 'underline') turningOn = _underlineOn;
      else if (attribute.key == 'strike') turningOn = _strikeOn;
      _preserveSelection(() {
        _quill.formatSelection(
          turningOn ? attribute : Attribute.clone(attribute, null),
        );
      });
    }

    // Always re-apply persistent toggled style for future typing
    _applyPersistentToggles();
    // Keep caret visible by retaining focus on editor
    _editorFocusNode.requestFocus();
    setState(() {});
  }

  void _toggleBullets() {
    final style = _quill.getSelectionStyle();
    final isBulleted =
        style.attributes[Attribute.list.key]?.value == Attribute.ul.value;
    _preserveSelection(() {
      _quill.formatSelection(
        isBulleted ? Attribute.clone(Attribute.list, null) : Attribute.ul,
      );
    });
    _editorFocusNode.requestFocus();
  }

  void _toggleCheckbox() {
    final style = _quill.getSelectionStyle();
    final current = style.attributes[Attribute.list.key]?.value;
    final isChecklist = current == 'checked' || current == 'unchecked';
    _preserveSelection(() {
      _quill.formatSelection(
        isChecklist ? Attribute.clone(Attribute.list, null) : Attribute.unchecked,
      );
    });
    _editorFocusNode.requestFocus();
  }

  bool _isInlineActive(Attribute attribute) {
    // Reflect persistent toggle state so the button stays highlighted
    switch (attribute.key) {
      case 'bold':
        return _boldOn;
      case 'italic':
        return _italicOn;
      case 'underline':
        return _underlineOn;
      case 'strike':
        return _strikeOn;
      default:
        final attrs = _quill.getSelectionStyle().attributes;
        return attrs.containsKey(attribute.key);
    }
  }

  void _applyPersistentToggles() {
    // Only include attributes that are ON; omit others entirely so that
    // keyboard shortcuts can freely toggle them off/on without being
    // overridden by our forced style.
    final map = <String, Attribute>{};
    if (_boldOn) map[Attribute.bold.key] = Attribute.bold;
    if (_italicOn) map[Attribute.italic.key] = Attribute.italic;
    if (_underlineOn) map[Attribute.underline.key] = Attribute.underline;
    if (_strikeOn) map[Attribute.strikeThrough.key] = Attribute.strikeThrough;
    _quill.forceToggledStyle(Style.attr(map));
  }

  bool _isBulletsActive() {
    final attrs = _quill.getSelectionStyle().attributes;
    return attrs[Attribute.list.key]?.value == Attribute.ul.value;
  }

  bool _isChecklistActive() {
    final v = _quill.getSelectionStyle().attributes[Attribute.list.key]?.value;
    return v == Attribute.unchecked.value || v == Attribute.checked.value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: WindowBorder(
        color: _headerShade,
        width: 1,
        child: Stack(
          children: [
            // Bottom layer: content fills the window
            Positioned.fill(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  16,
                  (kHeaderHeight + 16) + (_menuOpen ? kDrawerHeight : 0.0), // push content below drawer
                  16,
                  16 + kToolbarHeight + 8, // leave space for bottom toolbar
                ),
                child: Container(
                  color: _background,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: _uiShade,
                            onPrimary: _background.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                            onSurface: _uiShade,
                            surface: _background,
                          ),
                    ),
                    child: QuillEditor.basic(
                      key: ValueKey<int>(_background.value),
                      controller: _quill,
                      focusNode: _editorFocusNode,
                      scrollController: _editorScrollController,
                      config: QuillEditorConfig(
                      placeholder: 'Start typing…',
                      autoFocus: false,
                      showCursor: true,
                      onTapOutsideEnabled: false,
                      textSelectionThemeData: TextSelectionThemeData(
                        cursorColor: _uiShade,
                        selectionColor: _uiShade.withOpacity(0.35),
                      ),
                      customStyles: DefaultStyles(
                        paragraph: DefaultTextBlockStyle(
                          TextStyle(
                            color: _uiShade,
                            fontSize: 18,
                            height: 1.30,
                            decoration: TextDecoration.none,
                          ),
                          const HorizontalSpacing(0, 0),
                          VerticalSpacing.zero,
                          VerticalSpacing.zero,
                          null,
                        ),
                        lists: DefaultListBlockStyle(
                          TextStyle(
                            color: _uiShade,
                            fontSize: 18,
                            height: 1.30,
                            decoration: TextDecoration.none,
                          ),
                          const HorizontalSpacing(0, 0),
                          VerticalSpacing.zero,
                          VerticalSpacing.zero,
                          null,
                          null,
                        ),
                        placeHolder: DefaultTextBlockStyle(
                          TextStyle(
                            color: _uiShade.withOpacity(0.35),
                            fontSize: 18,
                            height: 1.30,
                            decoration: TextDecoration.none,
                          ),
                          const HorizontalSpacing(0, 0),
                          VerticalSpacing.zero,
                          VerticalSpacing.zero,
                          null,
                       ),
                     ),
                  ),
                  ),
                ),
                ),
              ),
            ),

            // Top: translucent, blurred header over content
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: kHeaderHeight,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _headerShade.withOpacity(0.70),
                          _headerShade.withOpacity(0.55),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(color: _accentShade, width: 2),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Left: plus button
                        IconButton(
                          onPressed: _openNewNote,
                          icon: const Icon(Icons.add, color: Colors.white),
                          splashRadius: 18,
                          tooltip: 'New note',
                        ),

                        // Middle: draggable empty area (custom drag using window_manager)
                        Expanded(
                          child: DragToMoveArea(
                            child: const SizedBox.expand(),
                          ),
                        ),

                        // Right: menu + close
                        IconButton(
                          onPressed: () {
                            setState(() => _menuOpen = !_menuOpen);
                          },
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          splashRadius: 18,
                          tooltip: 'More',
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _performCloseAction,
                          icon: const Icon(Icons.close, color: Colors.white),
                          splashRadius: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Slide-down drawer, overlay below the header
            Positioned(
              top: kHeaderHeight,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: _menuOpen ? kDrawerHeight : 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      opacity: _menuOpen ? 1 : 0,
                      child: Container(
                        color: _background.withOpacity(0.78), // translucent drawer
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, color: _uiShade),
                                const SizedBox(width: 16),
                                Icon(Icons.send, color: _uiShade),
                                const SizedBox(width: 16),
                                Icon(Icons.push_pin_outlined, color: _uiShade),
                                const SizedBox(width: 16),
                                Icon(Icons.checklist_outlined, color: _uiShade),
                                const SizedBox(width: 16),
                                IconButton(
                                  tooltip: 'Theme',
                                  onPressed: _openThemePicker,
                                  icon: Icon(Icons.dashboard_customize_outlined, color: _uiShade),
                                  splashRadius: 18,
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.delete_outline, color: _uiShade),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom-left text formatting toolbar
            Positioned(
              left: 8,
              bottom: 8,
              child: SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    // Bulleted list toggle
                    _ToolIcon(
                      icon: Icons.format_list_bulleted,
                      tooltip: 'Bulleted list',
                      onPressed: _toggleBullets,
                      isActive: _isBulletsActive(),
                      color: _uiShade,
                    ),
                    // Checkbox list toggle (cycles [ ] <-> [x])
                    _ToolIcon(
                      icon: Icons.check_box_outline_blank,
                      tooltip: 'Checkbox',
                      onPressed: _toggleCheckbox,
                      isActive: _isChecklistActive(),
                      color: _uiShade,
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'B',
                      isActive: _isInlineActive(Attribute.bold),
                      onTap: () => _toggleInline(Attribute.bold),
                      color: _uiShade,
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'i',
                      fontStyle: FontStyle.italic,
                      isActive: _isInlineActive(Attribute.italic),
                      onTap: () => _toggleInline(Attribute.italic),
                      color: _uiShade,
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'U',
                      underline: true,
                      isActive: _isInlineActive(Attribute.underline),
                      onTap: () => _toggleInline(Attribute.underline),
                      color: _uiShade,
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'S',
                      strike: true,
                      isActive: _isInlineActive(Attribute.strikeThrough),
                      onTap: () => _toggleInline(Attribute.strikeThrough),
                      color: _uiShade,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final FontStyle? fontStyle;
  final bool underline;
  final bool strike;
  final bool isActive;
  final Color? color;

  const _TextActionButton({
    required this.label,
    required this.onTap,
    this.fontStyle,
    this.underline = false,
    this.strike = false,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    TextDecoration? decoration;
    if (underline && strike) {
      decoration = TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
    } else if (underline) {
      decoration = TextDecoration.underline;
    } else if (strike) {
      decoration = TextDecoration.lineThrough;
    }

    final activeBg = Colors.black.withOpacity(0.07);
    final activeFg = color ?? Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: activeFg,
            fontSize: 20,
            fontWeight: label == 'B' ? FontWeight.w700 : FontWeight.w500,
            fontStyle: fontStyle,
            decoration: decoration,
          ),
        ),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? color;

  const _ToolIcon({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = Colors.black.withOpacity(0.07);
    final iconColor = (color ?? Theme.of(context).colorScheme.onSurface)
        .withOpacity(0.85);
    return Container(
      decoration: BoxDecoration(
        color: isActive ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: iconColor, size: 22),
        splashRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        constraints:
            const BoxConstraints(minWidth: 36, minHeight: kToolbarHeight),
      ),
    );
  }
}

// Placeholder widget removed per request

// Removed custom _DragToMoveArea in favor of window_manager's native DragToMoveArea

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonColors = WindowButtonColors(
      iconNormal: Colors.white,
      mouseOver: Colors.deepPurple.shade300,
      mouseDown: Colors.deepPurple.shade700,
      iconMouseOver: Colors.white,
      iconMouseDown: Colors.white,
    );

    final closeButtonColors = WindowButtonColors(
      mouseOver: Colors.red.shade400,
      mouseDown: Colors.red.shade700,
      iconNormal: Colors.white,
      iconMouseOver: Colors.white,
    );

    return Row(
      children: [
        MinimizeWindowButton(colors: buttonColors),
        MaximizeWindowButton(colors: buttonColors),
        CloseWindowButton(colors: closeButtonColors),
      ],
    );
  }
}
