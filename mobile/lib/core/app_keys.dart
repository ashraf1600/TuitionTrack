import 'package:flutter/material.dart';

/// The app's navigator and messenger, for code that runs outside a screen:
/// tapping a phone notification, for example.
final rootNavigatorKey = GlobalKey<NavigatorState>();
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();
