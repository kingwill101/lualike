import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:love2d/love2d.dart' hide LoveGpuRenderBackend;
import 'package:love2d_gpu/love2d_gpu.dart';

/// Integration test for the love2d_gpu demo.
///
/// Launches the full LOVE renderer with GPU backend and verifies it
/// renders without crashing for several seconds, catching deferred
/// GPU errors like texture binding failures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('love2d_gpu demo', () {
    testWidgets('full GPU rendering runs 10 seconds without crash',
        (tester) async {
      // Initialize GPU backend.
      LoveGpuRenderBackend? gpuBackend;
      try {
        gpuBackend = await LoveGpuRenderBackend.create();
      } catch (_) {}
      if (gpuBackend == null) return; // GPU not available — skip.

      // Build the full app widget with GPU backend.
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('love2d — Flutter GPU'),
              backgroundColor: const Color(0xFF0D0D1A),
              foregroundColor: Colors.white70,
            ),
            body: Stack(
              children: [
                LoveFlameHarness(
                  key: ValueKey(gpuBackend.runtimeType),
                  entryAsset: 'assets/main.lua',
                  renderBackend: gpuBackend,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: Material(
                      color: const Color(0xDD111827),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.speed,
                              size: 18,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'GPU',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Pump frames for 10 seconds to exercise the full GPU pipeline:
      // texture upload, surface acquire, render pass, present.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));

        // Verify the app is alive — look for the title.
        expect(find.textContaining('love2d'), findsWidgets);
      }
    });
  });
}
