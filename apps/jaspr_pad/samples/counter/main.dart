// [sample=0] Counter
import 'package:jaspr/jaspr.dart';

void main() {
  runApp(App());
}

class App extends StatefulComponent {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int count = 0;

  @override
  Iterable<Component> build(BuildContext context) sync* {
    yield text('Count is $count');

    yield button(
      events: {
        'click': (e) {
          setState(() => count++);
        },
      },
      [text('Press Me')],
    );
  }
}
