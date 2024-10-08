import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';

import '../codec/codec_resource.dart';
import '../utils.dart';

/// Builds mixins for components annotated with @sync
class SyncMixinsBuilder implements Builder {
  SyncMixinsBuilder(BuilderOptions options);

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    try {
      await generateSyncMixin(buildStep);
    } on SyntaxErrorInAssetException {
      rethrow;
    } catch (e, st) {
      print('An unexpected error occurred.\n'
          'This is probably a bug in jaspr_builder.\n'
          'Please report this here: '
          'https://github.com/schultek/jaspr/issues\n\n'
          'The error was:\n$e\n\n$st');
      rethrow;
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.sync.dart'],
      };

  Future<void> generateSyncMixin(BuildStep buildStep) async {
    // Performance optimization
    var file = await buildStep.readAsString(buildStep.inputId);
    if (!file.contains('@sync')) {
      return;
    }

    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
      return;
    }

    var library = await buildStep.inputLibrary;

    var annotated = library.topLevelElements
        .whereType<ClassElement>()
        .map((clazz) => (
              clazz,
              clazz.fields.where((element) => syncChecker.firstAnnotationOfExact(element) != null).where((element) {
                if (element.isStatic) {
                  log.severe(
                      '@sync cannot be used on static fields. Failing element: ${clazz.name}.${element.name} in library ${library.source.fullName}.');
                  return false;
                }
                if (element.isFinal) {
                  log.severe(
                      '@sync cannot be used on final fields. Failing element: ${clazz.name}.${element.name} in library ${library.source.fullName}.');
                  return false;
                }
                if (element.isPrivate) {
                  log.severe(
                      '@sync cannot be used on private fields. Failing element: ${clazz.name}.${element.name} in library ${library.source.fullName}.');
                  return false;
                }

                return true;
              })
            ))
        .where((c) => c.$2.isNotEmpty)
        .where((c) {
      if (!stateChecker.isSuperOf(c.$1)) {
        log.severe(
            '@sync can only be used on fields in a State class. Failing element: ${c.$1.name} in library ${library.source.fullName}.');
        return false;
      }
      return true;
    });

    if (annotated.isEmpty) {
      return;
    }

    var resource = await buildStep.fetchResource(codecResource);
    var codecs = await resource.readCodecs(buildStep);

    var outputId = buildStep.inputId.changeExtension('.sync.dart');

    var moduleImport = 'package:${buildStep.inputId.package}/${buildStep.inputId.path.replaceFirst('lib/', '')}';
    var mixinImports = <String>{};

    var mixins = annotated.map((e) {
      var (mixin, imports) = generateMixinFromEntry(e, codecs);
      mixinImports.addAll(imports);
      return mixin;
    }).join('\n\n');

    var syncPart = DartFormatter(pageWidth: 120).format('''
      $generationHeader
      
      import 'package:jaspr/jaspr.dart';
      import '$moduleImport';
      ${mixinImports.map((p) => "import '$p';").join('\n  ')}
            
      $mixins
    ''');

    await buildStep.writeAsString(outputId, syncPart);
  }

  (String, Set<String>) generateMixinFromEntry((ClassElement, Iterable<FieldElement>) element, Codecs codecs) {
    final (clazz, fields) = element;
    final comp = clazz.supertype!.typeArguments.first.element!;

    final imports = <String>{};

    final members = fields.map((f) => """
      ${f.type.getDisplayString()} get ${f.name};
      set ${f.name}(${f.type.getDisplayString()} ${f.name});
    """).join('\n');

    final decoders = fields.map((f) {
      var decoder = codecs.getDecoderFor(f.type, "value['${f.name}']");
      imports.addAll(decoder.$2);
      return "${f.name} = ${decoder.$1};";
    }).join('\n');

    final encoders = fields.map((f) {
      var encoder = codecs.getEncoderFor(f.type, f.name);
      imports.addAll(encoder.$2);
      return "'${f.name}': ${encoder.$1},";
    }).join('\n');

    return (
      """
      mixin ${clazz.name.startsWith('_') ? clazz.name.substring(1) : clazz.name}SyncMixin on State<${comp.name}> implements SyncStateMixin<${comp.name}, Map<String, dynamic>> {
        $members
      
        @override
        void updateState(Map<String, dynamic> value) {
          $decoders
        }
      
        @override
        Map<String, dynamic> getState() {
          return {
            $encoders
          };
        }
      
        @override
        void initState() {
          super.initState();
          SyncStateMixin.initSyncState(this);
        }
      }
    """,
      imports
    );
  }
}
