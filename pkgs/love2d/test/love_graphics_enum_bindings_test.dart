import 'package:flutter_test/flutter_test.dart';
import 'package:lualike/lualike.dart';
import 'package:love2d/love2d.dart';

void main() {
  test('graphics enum tables are exposed on love.graphics and as globals', () {
    final runtime = Interpreter();
    installLove2d(runtime: runtime, host: LoveHeadlessHost());

    expect(
      _tableField(runtime, const <String>['love', 'graphics', 'AlignMode']),
      isA<Map>(),
    );
    expect(
      _tableField(runtime, const <String>[
        'love',
        'graphics',
        'AlignMode',
        'justify',
      ]),
      'justify',
    );
    expect(
      _tableField(runtime, const <String>['AlignMode', 'center']),
      'center',
    );
    expect(
      _tableField(runtime, const <String>['BlendMode', 'premultiplied']),
      'premultiplied',
    );
    expect(
      _tableField(runtime, const <String>[
        'love',
        'graphics',
        'SpriteBatchUsage',
        'dynamic',
      ]),
      'dynamic',
    );
    expect(
      _tableField(runtime, const <String>[
        'love',
        'graphics',
        'TextureType',
        '2d',
      ]),
      '2d',
    );
    expect(
      _tableField(runtime, const <String>['StencilAction', 'incrementwrap']),
      'incrementwrap',
    );
  });
}

Object? _tableField(Interpreter runtime, List<String> path) {
  var current = runtime.getCurrentEnv().get(path.first);
  for (final segment in path.skip(1)) {
    final table = current is Value ? current.raw : current;
    expect(
      table,
      isA<Map>(),
      reason: 'Expected ${path.join('.')} to traverse a Lua table',
    );
    current = (table as Map)[segment];
  }

  return current is Value ? current.unwrap() : current;
}
