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
  

  @override
  void initState() {
    super.initState();
    _quill = QuillController.basic();
  }

  @override
  void dispose() {
    _quill.dispose();
    super.dispose();
  }

  void _format(Attribute attribute) {
    _quill.formatSelection(attribute);
  }

  void _toggleBullets() {
    final style = _quill.getSelectionStyle();
    final isBulleted = style.attributes[Attribute.list.key]?.value == Attribute.ul.value;
    _quill.formatSelection(
      isBulleted ? Attribute.clone(Attribute.list, null) : Attribute.ul,
    );
  }

  void _toggleCheckbox() {
    final style = _quill.getSelectionStyle();
    final current = style.attributes[Attribute.list.key]?.value;
    if (current == 'checked') {
      _quill.formatSelection(Attribute.unchecked);
    } else if (current == 'unchecked') {
      _quill.formatSelection(Attribute.clone(Attribute.list, null));
    } else {
      _quill.formatSelection(Attribute.unchecked);
    }
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
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: Colors.deepPurple.shade900,
                      fontSize: 18,
                      height: 1.35,
                    ),
                    child: QuillEditor.basic(
                      controller: _quill,
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
                    _ToolIcon(icon: Icons.format_list_bulleted, tooltip: 'Bulleted list', onPressed: _toggleBullets),
                    // Checkbox list toggle (cycles [ ] <-> [x])
                    _ToolIcon(icon: Icons.check_box_outline_blank, tooltip: 'Checkbox', onPressed: _toggleCheckbox),
                    const SizedBox(width: 12),
                    _TextActionButton(label: 'B', onTap: () => _format(Attribute.bold)),
                    const SizedBox(width: 12),
                    _TextActionButton(label: 'i', fontStyle: FontStyle.italic, onTap: () => _format(Attribute.italic)),
                    const SizedBox(width: 12),
                    _TextActionButton(label: 'U', underline: true, onTap: () => _format(Attribute.underline)),
                    const SizedBox(width: 12),
                    _TextActionButton(label: 'S', strike: true, onTap: () => _format(Attribute.strikeThrough)),
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

  const _TextActionButton({
    required this.label,
    required this.onTap,
    this.fontStyle,
    this.underline = false,
    this.strike = false,
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.deepPurple.shade900,
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

  const _ToolIcon({required this.icon, required this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.deepPurple.shade900, size: 22),
      splashRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: kToolbarHeight),
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
