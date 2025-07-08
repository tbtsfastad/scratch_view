import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pointer_tap_simulator/pointer_tap_simulator.dart';

class _ScratchRevealNotification extends Notification {
  final Offset position;
  final double width;
  final double height;

  _ScratchRevealNotification(this.position, this.width, this.height);
}

class ScratchRevealAllByRowsNotification extends Notification {
  final int rowCount;

  ScratchRevealAllByRowsNotification(this.rowCount);
}

class ScratchView extends StatefulWidget {
  const ScratchView({
    super.key,
    required this.cover,
    required this.behind,
    this.revealThreshold = 0.8,
    this.revealDuration = const Duration(seconds: 2),
    this.onProgress,
    this.scratchRadius,
  }) : assert(revealThreshold >= 0.0 && revealThreshold <= 1.0);
  final Widget cover;
  final Widget behind;
  final double revealThreshold;
  final Duration revealDuration;
  final ValueChanged<double>? onProgress;
  final double? scratchRadius;

  @override
  State<ScratchView> createState() => ScratchViewState();
}

class ScratchViewState extends State<ScratchView> with SingleTickerProviderStateMixin {
  late final double _scratchRadius;
  final List<Offset?> _scratchedPoints = [];
  final List<Rect> _revealRects = [];

  bool _isRevealed = false;
  Offset? _lastPoint;
  bool _isRevealingByRows = false;

  late final AnimationController _animationController;
  double _lastRevealedAnimValue = 0;

  final Set<Point<int>> _scratchedCells = {};
  Size? _areaSize;
  static const int _progressResolution = 20;

  @override
  void initState() {
    _scratchRadius = widget.scratchRadius ?? 20;
    _animationController = AnimationController(vsync: this, duration: widget.revealDuration);
    super.initState();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> revealAllByRows({int rowCount = 1}) async {
    assert(rowCount > 0, "rowCount must be greater than 0");
    if (_isRevealed || _isRevealingByRows || _areaSize == null) return;

    setState(() {
      _isRevealingByRows = true;
      _lastRevealedAnimValue = 0;
    });

    const int stepsPerRow = 20;
    final double rowHeight = _areaSize!.height / rowCount;
    final double stepWidth = _areaSize!.width / stepsPerRow;

    _animationController.addListener(() {
      if (!mounted || _isRevealed) {
        _animationController.stop();
        return;
      }

      final animValue = _animationController.value;
      final totalSteps = rowCount * stepsPerRow;
      final currentStep = (animValue * totalSteps).floor();
      final lastStep = (_lastRevealedAnimValue * totalSteps).floor();

      if (currentStep > lastStep) {
        final rectsToAdd = <Rect>[];
        for (int step = lastStep; step < currentStep; step++) {
          final row = step ~/ stepsPerRow;
          final col = step % stepsPerRow;
          rectsToAdd.add(Rect.fromLTWH(col * stepWidth, row * rowHeight, stepWidth, rowHeight));
        }

        if (rectsToAdd.isNotEmpty) {
          setState(() {
            _revealRects.addAll(rectsToAdd);
          });
          _calculateProgress(rectsToAdd.last.center);
        }
        _lastRevealedAnimValue = animValue;
      }
    });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        if (mounted) {
          setState(() {
            _isRevealingByRows = false;
          });
        }
      }
    });

    _animationController.forward(from: 0);
  }

  Rect convertToTapRevealRect(Offset position, double width, double height) {
    final rect = context.findRenderObject() as RenderBox;
    final offset = rect.localToGlobal(Offset.zero);
    return Rect.fromLTWH(position.dx - offset.dx, position.dy - offset.dy, width, height);
  }

  void revealByTapRect(Offset position, double width, double height) {
    final rect = convertToTapRevealRect(position, width, height);
    revealByRect(rect);
  }

  void revealByRect(Rect rect) {
    if (_isRevealed) return;

    setState(() {
      _revealRects.add(rect);
    });

    final step = _scratchRadius / 2;
    for (double dx = rect.left; dx < rect.right; dx += step) {
      for (double dy = rect.top; dy < rect.bottom; dy += step) {
        _calculateProgress(Offset(dx, dy));
      }
    }
  }

  void _calculateProgress(Offset position) {
    if (_areaSize == null) return;

    final cellWidth = _areaSize!.width / _progressResolution;
    final cellHeight = _areaSize!.height / _progressResolution;

    final rect = Rect.fromCircle(center: position, radius: _scratchRadius);

    final startCol = (rect.left / cellWidth).floor().clamp(0, _progressResolution - 1);
    final endCol = (rect.right / cellWidth).ceil().clamp(0, _progressResolution - 1);
    final startRow = (rect.top / cellHeight).floor().clamp(0, _progressResolution - 1);
    final endRow = (rect.bottom / cellHeight).ceil().clamp(0, _progressResolution - 1);

    var wasCellAdded = false;
    for (var r = startRow; r <= endRow; r++) {
      for (var c = startCol; c <= endCol; c++) {
        final cellCenter = Offset((c + 0.5) * cellWidth, (r + 0.5) * cellHeight);
        final distance = (cellCenter - position).distance;
        if (distance <= _scratchRadius) {
          if (_scratchedCells.add(Point(c, r))) {
            wasCellAdded = true;
          }
        }
      }
    }

    if (wasCellAdded) {
      final progress = _scratchedCells.length / (_progressResolution * _progressResolution);

      widget.onProgress?.call(progress);

      if (progress >= widget.revealThreshold && !_isRevealed) {
        setState(() {
          _isRevealed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => NotificationListener(
    onNotification: (notification) {
      switch (notification) {
        case _ScratchRevealNotification():
          WidgetsBinding.instance.addPostFrameCallback((_) {
            revealByTapRect(notification.position, notification.width, notification.height);
          });
          return true;
        case ScratchRevealAllByRowsNotification():
          WidgetsBinding.instance.addPostFrameCallback((_) {
            revealAllByRows(rowCount: notification.rowCount);
          });
          return true;
        default:
          return false;
      }
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        _areaSize = constraints.biggest;
        return Stack(
          alignment: Alignment.center,
          children: [
            widget.behind,
            if (!_isRevealed)
              PointerTapSimulator(
                onPointerDown: (details) {
                  if (_isRevealed || _isRevealingByRows) return;
                  _lastPoint = details.localPosition;
                },
                onPointerMove: (details) {
                  if (_isRevealed || _isRevealingByRows) return;
                  final currentPoint = details.localPosition;
                  setState(() {
                    if (_lastPoint != null) {
                      _scratchedPoints.add(_lastPoint);
                      _calculateProgress(_lastPoint!);
                      _lastPoint = null;
                    }
                    _scratchedPoints.add(currentPoint);
                    _calculateProgress(currentPoint);
                  });
                },
                onPointerUp: (details) {
                  if (_isRevealed || _isRevealingByRows) return;
                  setState(() {
                    _lastPoint = null;
                    _scratchedPoints.add(null);
                  });
                },
                child: ClipPath(
                  clipper: _ScratchAreaClipper(
                    points: _scratchedPoints,
                    scratchRadius: _scratchRadius,
                    rects: _revealRects,
                  ),
                  child: widget.cover,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _ScratchAreaClipper extends CustomClipper<Path> {
  final List<Offset?> points;
  final double scratchRadius;
  final List<Rect>? rects;

  _ScratchAreaClipper({required this.points, required this.scratchRadius, this.rects});

  @override
  Path getClip(Size size) {
    final revealPath = Path();

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point == null) continue;
      if (!point.dx.isFinite || !point.dy.isFinite) continue;

      revealPath.addOval(Rect.fromCircle(center: point, radius: scratchRadius));

      if (i + 1 < points.length) {
        final nextPoint = points[i + 1];
        if (nextPoint != null) {
          if (!nextPoint.dx.isFinite || !nextPoint.dy.isFinite) continue;

          final offset = nextPoint - point;
          final distance = offset.distance;
          if (distance.isFinite && distance > 0.1) {
            final angle = offset.direction;
            if (!angle.isFinite) continue;

            final rectPath = Path()
              ..addRect(Rect.fromLTWH(0, -scratchRadius, distance, scratchRadius * 2));

            final transformedPath = rectPath.transform(
              (Matrix4.identity()
                    ..translate(point.dx, point.dy)
                    ..rotateZ(angle))
                  .storage,
            );
            revealPath.addPath(transformedPath, Offset.zero);
          }
        }
      }
    }

    if (rects != null) {
      for (final rect in rects!) {
        if (rect.left.isFinite &&
            rect.top.isFinite &&
            rect.right.isFinite &&
            rect.bottom.isFinite) {
          revealPath.addRect(rect);
        }
      }
    }

    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      revealPath,
    );
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return true;
  }
}

class ScratchRevealRectButtonView extends StatefulWidget {
  const ScratchRevealRectButtonView({super.key, required this.child, this.onTap});

  final Widget child;
  final Function()? onTap;

  @override
  State<ScratchRevealRectButtonView> createState() => _ScratchRevealRectButtonViewState();
}

class _ScratchRevealRectButtonViewState extends State<ScratchRevealRectButtonView> {
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: _onTap, child: widget.child);

  void _onTap() {
    final rect = context.findRenderObject() as RenderBox;
    final size = rect.size;
    _ScratchRevealNotification(
      rect.localToGlobal(Offset.zero),
      size.width,
      size.height,
    ).dispatch(context);
    widget.onTap?.call();
  }
}
