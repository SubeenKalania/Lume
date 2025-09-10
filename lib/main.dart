import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_quill/flutter_quill.dart' hide Text;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
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
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  } catch (_) {}
  Color? initial;
  if (args.isNotEmpty) {
    try {
      final Map<String, dynamic> data = jsonDecode(args.first);
      final int? bg = data['bg'] as int?;
      if (bg != null) initial = Color(bg);
    } catch (_) {}
  }

  runApp(StickyNotesApp(initialBackground: initial));

  doWhenWindowReady(() {
    const initialSize = Size(600, 600);
    appWindow.minSize = initialSize;
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = "Sticky Notes";
    appWindow.show();
  });
}

class StickyNotesApp extends StatelessWidget {
  const StickyNotesApp({super.key, this.initialBackground});

  final Color? initialBackground;

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
      home: StickyNotePage(initialBackground: initialBackground),
    );
  }
}

class StickyNotePage extends StatefulWidget {
  const StickyNotePage({super.key, this.initialBackground});

  final Color? initialBackground;

  @override
  State<StickyNotePage> createState() => _StickyNotePageState();
}

class _StickyNotePageState extends State<StickyNotePage> {
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
      final window = await DesktopMultiWindow.createWindow(
        jsonEncode({'bg': color.value}),
      );
      // Best-effort positioning; APIs vary by platform/plugins, so keep it minimal.
      // window.center();
      // window.setTitle('Sticky Notes');
      await window.show();
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
        return AlertDialog(
          title: const Text('Choose theme color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: temp,
              onColorChanged: (c) => temp = c,
              enableAlpha: false,
              labelTypes: const [],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                _applyTheme(temp);
                Navigator.of(ctx).pop();
              },
              child: const Text('Use Color'),
            ),
          ],
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
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _quill.removeListener(_syncFromController);
    _quill.dispose();
    super.dispose();
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

                        // Middle: draggable empty area
                        Expanded(
                          child: MoveWindow(
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
                        CloseWindowButton(
                          colors: WindowButtonColors(
                            mouseOver: Colors.red.shade400,
                            mouseDown: Colors.red.shade700,
                            iconNormal: Colors.white,
                            iconMouseOver: Colors.white,
                          ),
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
