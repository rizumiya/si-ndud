import 'package:flutter/material.dart';

import 'ui/core/app_theme.dart';
import 'ui/features/dashboard/view_models/s11_dashboard_view_model.dart';
import 'ui/features/dashboard/views/s11_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const S11CompanionApp());
}

class S11CompanionApp extends StatefulWidget {
  const S11CompanionApp({super.key, this.viewModel});

  final S11DashboardViewModel? viewModel;

  @override
  State<S11CompanionApp> createState() => _S11CompanionAppState();
}

class _S11CompanionAppState extends State<S11CompanionApp> {
  late final S11DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? S11DashboardViewModel();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S11 Smartwatch Companion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: S11DashboardScreen(viewModel: _viewModel),
    );
  }
}
