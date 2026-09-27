#!/usr/bin/env python3
"""Generate a deterministic Xcode project without requiring XcodeGen or CocoaPods."""
from pathlib import Path
import hashlib, json, plistlib

root = Path(__file__).resolve().parents[1]
APP_NAME = 'Altiscope'
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(identifier, isa, **fields):
    key = uid(identifier); objects[key] = dict(isa=isa, **fields); return key
def ref(path, kind=None, tree='<group>'):
    return add('file:'+path, 'PBXFileReference', lastKnownFileType=kind or 'sourcecode.swift', path=path, sourceTree=tree)
sources=[]; resources=[]; links=[]; children=[]
for path in sorted([*root.glob('App/**/*.swift'),*root.glob('Sources/**/*.swift')]):
    p=str(path.relative_to(root)); f=ref(p); children.append(f)
    sources.append(add('build:'+p,'PBXBuildFile',fileRef=f))
for p,kind in [('App/Resources/Assets.xcassets','folder.assetcatalog'),('App/Resources/PrivacyInfo.xcprivacy','text.xml')]:
    f=ref(p,kind); children.append(f); resources.append(add('build:'+p,'PBXBuildFile',fileRef=f))
frameworks=['Accelerate','Contacts','CoreData','CoreGraphics','CoreImage','CoreLocation','CoreMotion','CoreTelephony','CoreText','GLKit','ImageIO','Metal','OpenGLES','QuartzCore','Security','SystemConfiguration','UIKit','MetricKit','MapKit','Network']
for name in frameworks:
    f=ref(f'System/Library/Frameworks/{name}.framework','wrapper.framework','SDKROOT')
    children.append(f); links.append(add('link:'+name,'PBXBuildFile',fileRef=f))
google=root/'Vendor/Google/GoogleMaps.xcframework'
if google.exists():
    f=ref(str(google.relative_to(root)),'wrapper.xcframework'); children.append(f); links.append(add('link:google','PBXBuildFile',fileRef=f))
    p='Vendor/Google/Distribution/Maps/Resources/GoogleMapsResources/GoogleMaps.bundle'
    f=ref(p,'wrapper.plug-in'); children.append(f); resources.append(add('build:'+p,'PBXBuildFile',fileRef=f))
amap_exists=(root/'Vendor/AMap/MAMapKit.framework').exists() and (root/'Vendor/AMap/AMapFoundationKit.framework').exists()
if amap_exists:
    # AMap's arm64 slice is an iPhone binary, not an Apple Silicon simulator binary.
    for name in ['MAMapKit','AMapFoundationKit']:
        f=ref('Vendor/AMap/'+name+'.framework','wrapper.framework'); children.append(f)
    f=ref('Vendor/AMap/MAMapKit.framework/AMap.bundle','wrapper.plug-in'); children.append(f); resources.append(add('build:amap-resources','PBXBuildFile',fileRef=f))
config=ref('Config/App.xcconfig','text.xcconfig'); children.append(config)
product=add('product','PBXFileReference',explicitFileType='wrapper.application',path=APP_NAME+'.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products','PBXGroup',children=[product],name='Products',sourceTree='<group>')
group=add('main','PBXGroup',children=children+[products],sourceTree='<group>')
src=add('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0)
res=add('resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)
fw=add('frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=links,runOnlyForDeploymentPostprocessing=0)
project_configs=[]; target_configs=[]
for name in ['Debug','Release']:
    project_configs.append(add('project:'+name,'XCBuildConfiguration',name=name,buildSettings=dict(CLANG_ENABLE_MODULES='YES',SDKROOT='iphoneos',SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O',DEBUG_INFORMATION_FORMAT='dwarf',ENABLE_USER_SCRIPT_SANDBOXING='YES')))
    settings=dict(PRODUCT_NAME='$(TARGET_NAME)',SWIFT_EMIT_LOC_STRINGS='YES',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SUPPORTS_MACCATALYST='NO',OTHER_LDFLAGS=['$(inherited)','-ObjC','-lc++','-lz','-lsqlite3'],SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if name=='Debug' else '')
    if amap_exists:
        settings['FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]']=['$(inherited)','$(PROJECT_DIR)/Vendor/AMap']
        settings['OTHER_LDFLAGS[sdk=iphoneos*]']=['$(inherited)','-framework','MAMapKit','-framework','AMapFoundationKit']
    target_configs.append(add('target:'+name,'XCBuildConfiguration',name=name,baseConfigurationReference=config,buildSettings=settings))
pcl=add('project-configs','XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
tcl=add('target-configs','XCConfigurationList',buildConfigurations=target_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=add('target','PBXNativeTarget',buildConfigurationList=tcl,buildPhases=[src,fw,res],buildRules=[],dependencies=[],name=APP_NAME,productName=APP_NAME,productReference=product,productType='com.apple.product-type.application')
project=add('project','PBXProject',attributes=dict(BuildIndependentTargetsInParallel='YES',LastUpgradeCheck='2630'),buildConfigurationList=pcl,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['en','zh-Hans','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
def organize_navigator(objects, main_group, root):
    """Arrange freshly generated file references into disk-backed groups.

    File and build identifiers stay unchanged. Supporting files are visible
    in the navigator only; they are not added to the app's build phases.
    """
    import hashlib
    from pathlib import PurePosixPath

    def identifier(value):
        return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

    products = [key for key in objects[main_group]['children']
                if objects[key].get('name') == 'Products']
    objects[main_group]['children'] = []
    groups = {'': main_group}

    def directory(path):
        if path in groups:
            return groups[path]
        relative = PurePosixPath(path)
        parent_path = str(relative.parent)
        parent = directory('' if parent_path == '.' else parent_path)
        key = identifier('navigator-group:' + path)
        fields = dict(isa='PBXGroup', children=[], path=relative.name, sourceTree='<group>')
        # The framework itself remains a linked binary; this group exposes
        # the resource bundle inside it without duplicating the framework name.
        if relative.suffix == '.framework':
            fields['name'] = relative.stem + ' Resources'
        objects[key] = fields
        objects[parent]['children'].append(key)
        groups[path] = key
        return key

    kinds = {'.swift': 'sourcecode.swift', '.plist': 'text.plist.xml',
             '.xcconfig': 'text.xcconfig', '.md': 'net.daringfireball.markdown',
             '.py': 'text.script.python', '.json': 'text.json',
             '.png': 'image.png', '.gpx': 'text.xml'}
    support = [root/'README.md', root/'Package.swift', root/'App/Resources/Info.plist']
    for folder in ['Config', 'Tests', 'Scripts', 'Documentation']:
        support.extend(sorted((root/folder).rglob('*')))
    for file in support:
        if not file.is_file() or any(part.startswith('.') for part in file.relative_to(root).parts):
            continue
        path = file.relative_to(root).as_posix()
        key = identifier('file:' + path)
        objects.setdefault(key, dict(isa='PBXFileReference', path=path,
            sourceTree='<group>', lastKnownFileType=kinds.get(file.suffix, 'text')))

    framework_group = identifier('navigator-group:sdk-frameworks')
    objects[framework_group] = dict(isa='PBXGroup', children=[], name='Frameworks',
        path='System/Library/Frameworks', sourceTree='SDKROOT')
    references = [(key, value) for key, value in objects.items() if value['isa'] == 'PBXFileReference']
    for key, file in references:
        tree = file.get('sourceTree', '<group>')
        path = PurePosixPath(file['path'])
        if tree == 'BUILT_PRODUCTS_DIR':
            continue
        if tree == 'SDKROOT':
            assert str(path.parent) == 'System/Library/Frameworks'
            parent = framework_group
        else:
            assert tree == '<group>', (file['path'], tree)
            parent_path = str(path.parent)
            parent = directory('' if parent_path == '.' else parent_path)
        file['path'] = path.name
        file['sourceTree'] = '<group>'
        objects[parent]['children'].append(key)

    for key in groups.values():
        objects[key]['children'].sort(key=lambda child: (
            objects[child]['isa'] != 'PBXGroup',
            objects[child].get('name', objects[child].get('path', '')).casefold()))
    objects[framework_group]['children'].sort(key=lambda child: objects[child]['path'].casefold())
    objects[main_group]['children'].extend([framework_group] + products)


organize_navigator(objects, group, root)

def serialize(value,depth=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(depth+1)+json.dumps(k)+' = '+serialize(v,depth+1)+';\n' for k,v in value.items())+'\t'*depth+'}'
    if isinstance(value,list): return '('+', '.join(serialize(v,depth+1) for v in value)+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)
directory=root/(APP_NAME+'.xcodeproj'); directory.mkdir(exist_ok=True)
data=dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(data)+'\n')
scheme=directory/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
(scheme/(APP_NAME+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}" ReferencedContainer="container:{APP_NAME}.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}" ReferencedContainer="container:{APP_NAME}.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{APP_NAME}.app" BlueprintName="{APP_NAME}" ReferencedContainer="container:{APP_NAME}.xcodeproj"/></BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
info=dict(CFBundleDisplayName=APP_NAME,CFBundleName='$(PRODUCT_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundlePackageType='APPL',CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)',LSRequiresIPhoneOS=True,UILaunchScreen={},UIRequiredDeviceCapabilities=['arm64'],UIBackgroundModes=['location'],UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],**{'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']},NSLocationWhenInUseUsageDescription='Altiscope 使用精确位置记录你的轨迹、速度和海拔，开始记录后会在锁屏期间继续定位。',NSMotionUsageDescription='Altiscope 使用运动传感器记录去除重力后的三轴加速度。',GoogleMapsAPIKey='$(GOOGLE_MAPS_API_KEY)',AMapAPIKey='$(AMAP_API_KEY)')
with (root/'App/Resources/Info.plist').open('wb') as f: plistlib.dump(info,f)
privacy=dict(NSPrivacyTracking=False,NSPrivacyTrackingDomains=[],NSPrivacyCollectedDataTypes=[],NSPrivacyAccessedAPITypes=[dict(NSPrivacyAccessedAPIType='NSPrivacyAccessedAPICategoryUserDefaults',NSPrivacyAccessedAPITypeReasons=['CA92.1'])])
with (root/'App/Resources/PrivacyInfo.xcprivacy').open('wb') as f: plistlib.dump(privacy,f)
print(f'Generated {APP_NAME}.xcodeproj; Google={google.exists()}, AMap={amap_exists}')
