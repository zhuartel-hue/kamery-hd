import 'package:flutter/material.dart';

import '../theme.dart';

class _DragData {
  const _DragData(this.id, this.group);
  final String id;
  final String group;
}

/// Przytrzymaj i przeciągnij kafel na inny, żeby zamienić je miejscami.
/// Przytrzymanie bez przesuwania wywołuje [onHold] (menu kamery).
class DragSwap extends StatefulWidget {
  const DragSwap({
    super.key,
    required this.id,
    required this.group,
    required this.preview,
    required this.onSwap,
    required this.onHold,
    required this.child,
  });

  final String id;

  /// Zamieniać można tylko kafle z tej samej grupy (tego samego rejestratora).
  final String group;

  /// Lekki podgląd (zdjęcie) pokazywany pod palcem podczas przeciągania.
  final Widget preview;
  final void Function(String from, String to) onSwap;
  final VoidCallback onHold;
  final Widget child;

  @override
  State<DragSwap> createState() => _DragSwapState();
}

class _DragSwapState extends State<DragSwap> {
  double _moved = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        return DragTarget<_DragData>(
          onWillAcceptWithDetails: (d) => d.data.group == widget.group && d.data.id != widget.id,
          onAcceptWithDetails: (d) => widget.onSwap(d.data.id, widget.id),
          builder: (context, candidates, _) => LongPressDraggable<_DragData>(
            data: _DragData(widget.id, widget.group),
            hapticFeedbackOnStart: true,
            onDragStarted: () => setState(() {
              _moved = 0;
              _dragging = true;
            }),
            onDragUpdate: (d) => _moved += d.delta.distance,
            onDragEnd: (d) {
              setState(() => _dragging = false);
              // Przytrzymanie bez przesunięcia = menu kamery, jak dotąd.
              if (!d.wasAccepted && _moved < 12) widget.onHold();
            },
            feedback: Material(
              color: Colors.transparent,
              elevation: 14,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: w * 0.9,
                height: h * 0.9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Opacity(opacity: 0.9, child: widget.preview),
                ),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (_dragging) const IgnorePointer(child: ColoredBox(color: Color(0x99000000))),
                if (candidates.isNotEmpty)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Ocean.aqua.withValues(alpha: 0.15),
                        border: Border.all(color: Ocean.aqua, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
