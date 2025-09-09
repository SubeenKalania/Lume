import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_quill/flutter_quill.dart' hide Text;
// Removed persistence-related imports
import 'package:bitsdojo_window/bitsdojo_window.dart';

// Color palette for the mockup-style UI
const Color kHeaderColor = Color(0xFF6A3FB5); // dark purple header
const Color kHeaderAccent = Color(0xFF8A4FFF); // thin accent line under header
const Color kBackgroundColor = Color(0xFFE3D1FF); // light purple canvas

// Layout constants
const double kHeaderHeight = 50;
const double kDrawerHeight = 60;
const double kToolbarHeight = 40;

void main() {
  runApp(const StickyNotesApp());

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
  const StickyNotesApp({super.key});

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
      home: const StickyNotePage(),
    );
  }
}

class StickyNotePage extends StatefulWidget {
  const StickyNotePage({super.key});

  @override
  State<StickyNotePage> createState() => _StickyNotePageState();
}

class _StickyNotePageState extends State<StickyNotePage> {
  late QuillController _quill;
  bool _menuOpen = false;
  late FocusNode _editorFocusNode;
  late ScrollController _editorScrollController;

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
    // Rebuild when selection/style changes so buttons can reflect active state
    _quill.addListener(() => setState(() {}));
    // Keep persistent toggles applied when the selection changes
    _quill.onSelectionChanged = (_) => _applyPersistentToggles();
    // Initialize toggled style to current persistent settings
    _applyPersistentToggles();
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _quill.dispose();
    super.dispose();
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
      _quill.formatSelection(
        turningOn ? attribute : Attribute.clone(attribute, null),
      );
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
    _quill.formatSelection(
      isBulleted ? Attribute.clone(Attribute.list, null) : Attribute.ul,
    );
    _editorFocusNode.requestFocus();
  }

  void _toggleCheckbox() {
    final style = _quill.getSelectionStyle();
    final current = style.attributes[Attribute.list.key]?.value;
    final isChecklist = current == 'checked' || current == 'unchecked';
    _quill.formatSelection(
      isChecklist ? Attribute.clone(Attribute.list, null) : Attribute.unchecked,
    );
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
    // Explicitly set or clear each inline style so newly typed text respects
    // the persistent toggles even inside a styled run.
    final map = <String, Attribute>{
      Attribute.bold.key:
          _boldOn ? Attribute.bold : Attribute.clone(Attribute.bold, null),
      Attribute.italic.key: _italicOn
          ? Attribute.italic
          : Attribute.clone(Attribute.italic, null),
      Attribute.underline.key: _underlineOn
          ? Attribute.underline
          : Attribute.clone(Attribute.underline, null),
      Attribute.strikeThrough.key: _strikeOn
          ? Attribute.strikeThrough
          : Attribute.clone(Attribute.strikeThrough, null),
    };
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
      backgroundColor: kBackgroundColor,
      body: WindowBorder(
        color: kHeaderColor,
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
                  color: kBackgroundColor,
                  child: QuillEditor.basic(
                    controller: _quill,
                    focusNode: _editorFocusNode,
                    scrollController: _editorScrollController,
                    config: QuillEditorConfig(
                      placeholder: 'Start typing…',
                      autoFocus: false,
                      showCursor: true,
                      onTapOutsideEnabled: false,
                      textSelectionThemeData: TextSelectionThemeData(
                        cursorColor: Colors.deepPurple.shade900,
                        selectionColor:
                            Colors.deepPurple.shade400.withOpacity(0.35),
                      ),
                      customStyles: DefaultStyles(
                        paragraph: DefaultTextBlockStyle(
                          TextStyle(
                            color: Colors.deepPurple.shade900,
                            fontSize: 18,
                            height: 1.30,
                            decoration: TextDecoration.none,
                          ),
                          const HorizontalSpacing(0, 0),
                          VerticalSpacing.zero,
                          VerticalSpacing.zero,
                          null,
                        ),
                        placeHolder: DefaultTextBlockStyle(
                          TextStyle(
                            color: Colors.deepPurple.shade900
                                .withOpacity(0.35),
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
                          kHeaderColor.withOpacity(0.70),
                          kHeaderColor.withOpacity(0.55),
                        ],
                      ),
                      border: const Border(
                        bottom: BorderSide(color: kHeaderAccent, width: 2),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Left: plus button
                        IconButton(
                          onPressed: () {},
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
                        color: kBackgroundColor.withOpacity(0.78), // translucent drawer
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, color: Colors.deepPurple.shade900),
                                const SizedBox(width: 16),
                                Icon(Icons.send, color: Colors.deepPurple.shade900),
                                const SizedBox(width: 16),
                                Icon(Icons.push_pin_outlined, color: Colors.deepPurple.shade900),
                                const SizedBox(width: 16),
                                Icon(Icons.checklist_outlined, color: Colors.deepPurple.shade900),
                                const SizedBox(width: 16),
                                Icon(Icons.dashboard_customize_outlined, color: Colors.deepPurple.shade900),
                                const SizedBox(width: 16),
                                Icon(Icons.delete_outline, color: Colors.deepPurple.shade900),
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
                    ),
                    // Checkbox list toggle (cycles [ ] <-> [x])
                    _ToolIcon(
                      icon: Icons.check_box_outline_blank,
                      tooltip: 'Checkbox',
                      onPressed: _toggleCheckbox,
                      isActive: _isChecklistActive(),
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'B',
                      isActive: _isInlineActive(Attribute.bold),
                      onTap: () => _toggleInline(Attribute.bold),
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'i',
                      fontStyle: FontStyle.italic,
                      isActive: _isInlineActive(Attribute.italic),
                      onTap: () => _toggleInline(Attribute.italic),
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'U',
                      underline: true,
                      isActive: _isInlineActive(Attribute.underline),
                      onTap: () => _toggleInline(Attribute.underline),
                    ),
                    const SizedBox(width: 12),
                    _TextActionButton(
                      label: 'S',
                      strike: true,
                      isActive: _isInlineActive(Attribute.strikeThrough),
                      onTap: () => _toggleInline(Attribute.strikeThrough),
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

  const _TextActionButton({
    required this.label,
    required this.onTap,
    this.fontStyle,
    this.underline = false,
    this.strike = false,
    this.isActive = false,
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

    final activeBg = Colors.deepPurple.shade100;
    final activeFg = Colors.deepPurple.shade900;
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

  const _ToolIcon({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = Colors.deepPurple.shade100;
    final iconColor = Colors.deepPurple.shade900;
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
