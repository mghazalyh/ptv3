import 'package:flutter/material.dart';

/// Route navigation for movie/show recommendations.
///
/// [Navigator.push] deliberately retains the covered details screen. Using
/// pushReplacement here destroys its scroll, season selection and back stack.
abstract final class DetailNavigation {
  static Future<T?> push<T>(
    BuildContext context,
    WidgetBuilder builder,
  ) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: builder,
        settings: const RouteSettings(name: '/details'),
      ),
    );
  }
}
