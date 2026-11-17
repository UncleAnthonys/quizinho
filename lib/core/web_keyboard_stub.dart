import 'package:flutter/foundation.dart';

/// The app gets the keyboard from Flutter itself (viewInsets).
final ValueNotifier<double> keyboardInset = ValueNotifier(0);

/// Browsers only (see web_keyboard_web.dart): the app opens the keyboard itself.
void primeKeyboard() {}

/// Whether [primeKeyboard] opened the keyboard just now.
bool get keyboardPrimed => false;
