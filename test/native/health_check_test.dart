import 'package:metadata_audio/src/native/api.dart';
import 'package:metadata_audio/src/native/frb_generated.dart';
import 'package:test/test.dart';

void main() {
  group('healthCheck binding', () {
    setUpAll(RustLib.init);

    tearDownAll(RustLib.dispose);

    test('calls generated healthCheck API', () async {
      final result = await healthCheck();

      expect(result, 'symphonia-native-ok');
    });
  });
}
