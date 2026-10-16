"""Generate the committed Xcode project deterministically. Python 3.9+, no dependencies."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def uid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def put(key, body):
    objects[uid(key)] = body
    return uid(key)

def arr(values):
    return '(' + ', '.join(values) + ', )' if values else '()'

def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

def ref(path, file_type):
    return put('ref:' + path, f'isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;')

core = sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'Core').glob('*.swift'))
app = sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'App').glob('*.swift'))
widget = ['Widget/NossoRitmoWidget.swift']
refs = {p: ref(p, 'sourcecode.swift') for p in core + app + widget}
config = ref('Config/Project.xcconfig', 'text.xcconfig')
assets = ref('App/Assets.xcassets', 'folder.assetcatalog')
app_product = put('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NossoRitmo.app; sourceTree = BUILT_PRODUCTS_DIR;')
widget_product = put('widget-product', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = NossoRitmoWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;')

def sources(name, paths):
    builds = [put(f'build:{name}:{p}', f'isa = PBXBuildFile; fileRef = {refs[p]};') for p in paths]
    return put(f'sources:{name}', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;')

app_sources = sources('app', core + app)
widget_sources = sources('widget', ['Core/WidgetSnapshot.swift'] + widget)
asset_build = put('assets-build', f'isa = PBXBuildFile; fileRef = {assets};')
resources = put('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([asset_build])}; runOnlyForDeploymentPostprocessing = 0;')
widget_resources = put('widget-resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
embed = put('embed-build', f'isa = PBXBuildFile; fileRef = {widget_product}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, );}};')
copy = put('embed-phase', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {arr([embed])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
proxy = put('proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("widget-target")}; remoteInfo = NossoRitmoWidget;')
dependency = put('dependency', f'isa = PBXTargetDependency; target = {uid("widget-target")}; targetProxy = {proxy};')

def configurations(name, base_settings):
    configurations = []
    for variant in ['Debug', 'Release']:
        settings = dict(base_settings)
        if name == 'project':
            settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if variant == 'Debug' else '-O', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if variant == 'Debug' else 'dwarf-with-dsym', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if variant == 'Debug' else ''})
        if variant == 'Release':
            settings['APS_ENVIRONMENT'] = 'production'
        body = ' '.join(f'{k} = {quoted(v)};' for k,v in settings.items())
        configurations.append(put(f'config:{name}:{variant}', f'isa = XCBuildConfiguration; baseConfigurationReference = {config}; buildSettings = {{{body}}}; name = {variant};'))
    return put('config-list:' + name, f'isa = XCConfigurationList; buildConfigurations = {arr(configurations)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_config = configurations('project', {'SDKROOT': 'iphoneos', 'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'targeted', 'TARGETED_DEVICE_FAMILY': '1', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'})
app_config = configurations('app', {'PRODUCT_BUNDLE_IDENTIFIER': '$(APP_BUNDLE_ID)', 'PRODUCT_NAME': 'NossoRitmo', 'INFOPLIST_FILE': 'Config/App-Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'Config/App.entitlements', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'GENERATE_INFOPLIST_FILE': 'NO', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks'})
widget_config = configurations('widget', {'PRODUCT_BUNDLE_IDENTIFIER': '$(WIDGET_BUNDLE_ID)', 'PRODUCT_NAME': 'NossoRitmoWidget', 'INFOPLIST_FILE': 'Config/Widget-Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'Config/Widget.entitlements', 'GENERATE_INFOPLIST_FILE': 'NO', 'SKIP_INSTALL': 'YES', 'APPLICATION_EXTENSION_API_ONLY': 'YES', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'})
put('widget-target', f'isa = PBXNativeTarget; buildConfigurationList = {widget_config}; buildPhases = {arr([widget_sources, widget_resources])}; buildRules = (); dependencies = (); name = NossoRitmoWidget; productName = NossoRitmoWidget; productReference = {widget_product}; productType = "com.apple.product-type.app-extension";')
put('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {arr([app_sources, resources, copy])}; buildRules = (); dependencies = {arr([dependency])}; name = NossoRitmo; productName = NossoRitmo; productReference = {app_product}; productType = "com.apple.product-type.application";')
products = put('products', f'isa = PBXGroup; children = {arr([app_product, widget_product])}; name = Products; sourceTree = "<group>";')
main = put('main', f'isa = PBXGroup; children = {arr(list(refs.values()) + [assets, config, products])}; sourceTree = "<group>";')
put('project', f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{{uid("app-target")} = {{SystemCapabilities = {{com.apple.iCloud = {{enabled = 1;}}; com.apple.ApplicationGroups.iOS = {{enabled = 1;}}; com.apple.Push = {{enabled = 1;}}; }}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "pt-BR"; hasScannedForEncodings = 0; knownRegions = ("pt-BR", en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([uid("app-target"), uid("widget-target")])};')
project_dir = ROOT / 'NossoRitmo.xcodeproj'
project_dir.mkdir(exist_ok=True)
text = '// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n'
text += ''.join(f'{key} = {{{value}}};\n' for key,value in sorted(objects.items()))
text += f'}};\nrootObject = {uid("project")};\n}}\n'
(project_dir / 'project.pbxproj').write_text(text, encoding='utf-8')
schemes = project_dir / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'NossoRitmo.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="NossoRitmo.app" BlueprintName="NossoRitmo" ReferencedContainer="container:NossoRitmo.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="NossoRitmo.app" BlueprintName="NossoRitmo" ReferencedContainer="container:NossoRitmo.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="NossoRitmo.app" BlueprintName="NossoRitmo" ReferencedContainer="container:NossoRitmo.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''', encoding='utf-8')
print('Generated NossoRitmo.xcodeproj with app + widget targets.')
