import 'package:flutter/material.dart';

import 'safety_module_screen.dart';

class VoltageLeakageScreen extends StatelessWidget {
  const VoltageLeakageScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const SafetyModuleScreen(mode: SafetyMode.leakage);
}
