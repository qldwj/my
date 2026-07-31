// widgets/markers_overlay.dart
import 'package:flutter/material.dart';
import '../models/marker.dart';

class MarkersOverlay extends StatelessWidget {
  final List<Marker> markers;
  final double width;
  final void Function(Marker) onTap;

  const MarkersOverlay({Key? key, required this.markers, required this.width, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: width,
      child: Stack(children: markers.map((m) {
        final left = (m.position.clamp(0.0, 1.0)) * width;
        return Positioned(
          left: left - 6,
          top: 0,
          child: GestureDetector(
            onTap: () => onTap(m),
            child: Tooltip(
              message: m.text,
              child: Container(width: 12, height: 18, decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        );
      }).toList()),
    );
  }
}
