import 'package:flutter/material.dart';

import 'safety_module_screen.dart';

class VoltageSurgeScreen extends StatelessWidget {
  const VoltageSurgeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const SafetyModuleScreen(mode: SafetyMode.surge);
}
