import 'package:flutter/foundation.dart';

enum DeviceMark { unknown, friendly }

class DeviceMarks {
  static final Map<String, DeviceMark> _marks = {};

  // Notifier that triggers UI rebuilds
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static DeviceMark? get(String signature) {
    return _marks[signature];
  }

  static void set(String signature, DeviceMark mark) {
    _marks[signature] = mark;
    version.value++; // notify listeners
  }

  static void clear(String signature) {
    _marks.remove(signature);
    version.value++; // notify listeners
  }
}

// Only Using this so the unknown / friendly logic
// Can be saved across pages for the marks on
// The search page to the Identification page

// Issue that came up that I want to remember:
// Never let a newly created page see more data than an earlier / older page
// If an output wasn't valid on say the scan page it won't be valid
// On another page
