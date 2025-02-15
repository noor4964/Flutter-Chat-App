import 'package:flutter/material.dart';

class MyNavigatorObserver extends NavigatorObserver {
  VoidCallback? _callback;

  void setCallback(VoidCallback callback) {
    _callback = callback;
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (_callback != null) {
      _callback!();
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (_callback != null) {
      _callback!();
    }
  }
}