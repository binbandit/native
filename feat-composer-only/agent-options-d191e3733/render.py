from pathlib import Path
import runpy
import subprocess
import sys

root = Path.cwd()
products = Path('/tmp/native-dd/cx-composer-agent-options/Build/Products/Debug')
original_run = subprocess.run

def run(command, *args, **kwargs):
    if command[:4] == ['nice', '-n', '10', 'xcrun']:
        command = command + ['-I', str(products), str(products / 'ACP.o'), str(products / 'AppAppearance.o')]
    return original_run(command, *args, **kwargs)

subprocess.run = run
support = [
    'native/Composer/ComposerRowPreviewFixtures.swift',
    'native/Composer/ComposerRowState.swift',
    'native/Composer/ComposerRowMenuOption.swift',
    'native/Composer/ComposerBottomRow.swift',
    'native/Composer/ComposerModeMenu.swift',
    'native/Composer/ComposerWhereMenu.swift',
    'native/Composer/Logic/SelectSetting.swift',
    'native/DesignSystem/Gallery/DSPreviewPair.swift',
    'native/DesignSystem/Tokens/TokensLayout.swift',
    'native/DesignSystem/Tokens/Platform.swift',
    'native/DesignSystem/Tokens/TokensComposerRow.swift',
    'native/DesignSystem/Tokens/TokensTypography.swift',
    'native/DesignSystem/Tokens/TokensColor.swift',
    'native/DesignSystem/Tokens/TokensLightTone.swift',
    'native/DesignSystem/Tokens/TokensDarkTone.swift',
    'native/DesignSystem/Tokens/TokensTransparency.swift',
    'native/DesignSystem/Tokens/AccentPalette.swift',
    'native/DesignSystem/Tokens/TokensMotion.swift',
    'native/DesignSystem/Components/SearchField.swift',
    'native/DesignSystem/Components/IconButton.swift',
    'native/DesignSystem/Components/ContextUsageRing.swift',
    'native/DesignSystem/Composer/ComposerActionButtons.swift',
    'native/DesignSystem/Status/DotGridLoader.swift',
    'native/DesignSystem/Status/DotGridLoader+Working.swift',
    'native/DesignSystem/Status/DotGridPulse.swift',
    'native/DesignSystem/Components/LayerMaskedView.swift',
]
sys.argv = ['render-previews.py', 'native/Composer/ComposerAgentModelMenu.swift',
            str(Path.home() / 'native-work/shots/cx-composer-agent-options'), '--width', '1560', '--height', '500']
for source in support:
    sys.argv += ['--support', source]
runpy.run_path(str(root / 'scripts/dev/render-previews.py'), run_name='__main__')
