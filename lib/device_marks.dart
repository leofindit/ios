import 'package:flutter/foundation.dart';

// Enum representing the mark/status of a device
enum DeviceMark { unknown, friendly, suspect }

// Manage the marks/statuses of devices, allowing retrieval, setting, and clearing of marks
class DeviceMarks {
  static final Map<String, DeviceMark> _marks = {};
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  // Retrieve the mark/status of a device by its signature
  static DeviceMark? get(String signature) {
    return _marks[signature];
  }

  // Set the mark/status of a device by its signature
  static void set(String signature, DeviceMark mark) {
    _marks[signature] = mark;
    version.value++;
  }

  // Clear the mark/status of a device by its signature
  static void clear(String signature) {
    _marks.remove(signature);
    version.value++;
  }
}