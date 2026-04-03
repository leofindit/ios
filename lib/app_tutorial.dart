import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

// Helper to create a solid black outline effect
const List<Shadow> _textOutlines = [
  Shadow(offset: Offset(-1.5, -1.5), color: Colors.black),
  Shadow(offset: Offset(1.5, -1.5), color: Colors.black),
  Shadow(offset: Offset(1.5, 1.5), color: Colors.black),
  Shadow(offset: Offset(-1.5, 1.5), color: Colors.black),
];

TargetFocus tutorialTarget({
  required GlobalKey key,
  required String id,
  required String title,
  required String body,
  ContentAlign align = ContentAlign.bottom,
  double yOffset = 0,
}) {
  return TargetFocus(
    identify: id,
    keyTarget: key,
    alignSkip: Alignment.topRight,
    contents: [
      TargetContent(
        align: align,
        builder: (context, controller) {
          return Padding(
            padding: EdgeInsets.only(top: yOffset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: _textOutlines, // <-- Text Outline
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    shadows: _textOutlines, // <-- Text Outline
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ],
  );
}
