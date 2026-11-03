from pathlib import Path
import subprocess

root = Path.cwd()
work = Path('/tmp/cx-composer-agent-options')
products = Path('/tmp/native-dd/cx-composer-agent-options/Build/Products/Debug')
app = products / 'Native.app'
source = subprocess.check_output(['git', 'show', 'bbbcd1b7a:native/Composer/ComposerRowModelAdapter.swift'], text=True)
(work / 'BeforeAdapter.swift').write_text('@testable import Native\n' + source)
flags = ['-I', str(Path.home() / 'Library/Caches/native-build/libghostty/include'), '-parse-as-library',
         '-swift-version', '6', '-default-isolation', 'MainActor', '-I', str(products),
         '-F', str(products), '-F', str(products / 'PackageFrameworks')]
for path in products.parents[2].glob('Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap'):
    flags += ['-Xcc', '-fmodule-map-file=' + str(path)]
command = ['nice', '-n', '10', 'xcrun', 'swiftc', *flags,
           str(root / 'scripts/tests/composer-row-settings.swift'), str(work / 'BeforeAdapter.swift'),
           str(root / 'Packages/ACP/Tests/ACPTests/GatewayWire.swift'),
           str(app / 'Contents/MacOS/Native.debug.dylib'),
           '-Xlinker', '-rpath', '-Xlinker', str(app / 'Contents/Frameworks'),
           '-Xlinker', '-rpath', '-Xlinker', str(app / 'Contents/MacOS'),
           '-o', str(work / 'check-before')]
subprocess.run(command, check=True)
raise SystemExit(subprocess.run([str(work / 'check-before'), '-sounds.enabled', 'NO', '-native.mute', 'YES']).returncode)
