import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/api.dart';

void main() {
  test('self-signed trust stays on the configured host', () {
    const base = 'https://tasks.example.com';
    expect(VikunjaApi.certHostAllowed(base, 'tasks.example.com'), isTrue);
    expect(VikunjaApi.certHostAllowed(base, 'evil.example'), isFalse);
    expect(
      VikunjaApi.certHostAllowed(
        'https://tasks.example.com:8443',
        'tasks.example.com',
      ),
      isTrue,
    );
    expect(
      VikunjaApi.certHostAllowed('not a url', 'tasks.example.com'),
      isFalse,
    );
  });

  test('base URL normalisation', () {
    final api = VikunjaApi(baseUrl: 'https://tasks.example.com/api/v1/');
    expect(api.baseUrl, 'https://tasks.example.com');
  });
}
