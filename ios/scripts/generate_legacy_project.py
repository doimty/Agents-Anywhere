#!/usr/bin/env python3
"""Generate the iOS 15 legacy app project.

The shipped project uses file-system synchronized groups tied to the modern
target, so a second target cannot share those folders. This generator writes a
small, explicit project that compiles the shared transport/API/domain files
together with `ios/Legacy/LegacySources` at IPHONEOS_DEPLOYMENT_TARGET=15.0.

Run it after adding or removing legacy sources:

    python3 ios/scripts/generate_legacy_project.py
    python3 ios/scripts/generate_legacy_project.py --check   # verify up to date
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
IOS_ROOT = REPO_ROOT / "ios"
APP_ROOT = IOS_ROOT / "Agents Anywhere" / "Agents Anywhere"
LEGACY_ROOT = IOS_ROOT / "Legacy"
PROJECT_DIR = LEGACY_ROOT / "AgentsAnywhereLegacy.xcodeproj"
PROJECT_FILE = PROJECT_DIR / "project.pbxproj"
SCHEME_FILE = PROJECT_DIR / "xcshareddata" / "xcschemes" / "AgentsAnywhereLegacy.xcscheme"
TARGET_NAME = "AgentsAnywhereLegacy"
BUNDLE_ID = "com.agentsanywhere.legacy"

SHARED_FILES = [
    "API/APIClient.swift",
    "API/V2/V2APIClient.swift",
    "API/V2/V2AccountAPI.swift",
    "API/V2/V2AttachmentAPI.swift",
    "API/V2/V2ConnectorAPI.swift",
    "API/V2/V2ConnectorAPI+Download.swift",
    "API/V2/V2ProjectAPI.swift",
    "API/V2/V2RealtimeAPI.swift",
    "API/V2/V2RuntimeAPI.swift",
    "Business/V2BusinessError.swift",
    "Models/WorkspaceDownloadedFile.swift",
    "API/V2/V2SessionAPI.swift",
    "Network/AsyncResultGate.swift",
    "Network/AuthTokenProvider.swift",
    "Network/DownloadRedirectPolicy.swift",
    "Network/HTTPError.swift",
    "Network/HTTPMethod.swift",
    "Network/HTTPReadRetryPolicy.swift",
    "Network/HTTPRequest.swift",
    "Network/HTTPTransport.swift",
    "Network/WebSocketTransport.swift",
    "Models/APIModels.swift",
    "Models/Chat/TimelineDiff.swift",
    "Models/Chat/TimelineEntryPresentation.swift",
    "Stores/KeychainStore.swift",
]
# Excluded from the legacy compile: they depend on iOS 16+/18+ types or on the
# modern presentation stack.
SHARED_EXCLUDED = {
    "Network/V2ConnectivityMonitor.swift",  # Observation
}


def shared_sources() -> list[Path]:
    files = [APP_ROOT / relative for relative in SHARED_FILES]
    files.extend(sorted((APP_ROOT / "Domain").rglob("*.swift"), key=lambda path: path.as_posix()))
    return [path for path in files if path.relative_to(APP_ROOT).as_posix() not in SHARED_EXCLUDED]


def legacy_sources() -> list[Path]:
    # Sort by POSIX path: `Path` ordering case-normalises on Windows but is
    # case-sensitive on POSIX, which reordered mixed-case file names and made
    # the generated project differ between a local run and CI.
    return sorted(
        (LEGACY_ROOT / "LegacySources").rglob("*.swift"),
        key=lambda path: path.as_posix(),
    )


def identifier(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def quote(value: str) -> str:
    # Always quote: PBX/OpenStep strings must not carry a bare "+" (Xcode
    # refuses to open the project when a file name like Foo+Bar.swift is bare).
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def generate() -> str:
    files: list[tuple[str, str]] = []  # (display name, path relative to project dir)
    for path in legacy_sources():
        files.append((path.name, path.relative_to(LEGACY_ROOT).as_posix()))
    for path in shared_sources():
        files.append((path.name, "../" + path.relative_to(IOS_ROOT).as_posix()))

    if not legacy_sources():
        raise SystemExit("No legacy sources found; expected ios/Legacy/LegacySources/*.swift")

    build_files = []
    file_refs = []
    children = []
    for name, relative in files:
        ref = identifier("ref:" + relative)
        build = identifier("build:" + relative)
        build_files.append(
            f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};"
        )
        file_refs.append(
            f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"name = {quote(name)}; path = {quote(relative)}; sourceTree = \"<group>\"; }};"
        )
        children.append(f"\t\t\t\t{ref} /* {name} */,")

    project = identifier("project")
    target = identifier("target")
    product = identifier("product")
    main_group = identifier("group:main")
    sources_group = identifier("group:sources")
    products_group = identifier("group:products")
    sources_phase = identifier("phase:sources")
    frameworks_phase = identifier("phase:frameworks")
    resources_phase = identifier("phase:resources")
    project_config_list = identifier("configlist:project")
    target_config_list = identifier("configlist:target")
    project_debug = identifier("config:project:debug")
    project_release = identifier("config:project:release")
    target_debug = identifier("config:target:debug")
    target_release = identifier("config:target:release")

    target_settings = f"""\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Agents Anywhere";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tMARKETING_VERSION = 0.9.0;
\t\t\t\tCURRENT_PROJECT_VERSION = 9;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = minimal;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;"""

    project_settings = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;"""

    text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{product} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {TARGET_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{sources_group} /* Sources */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{sources_group} /* Sources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(children)}
\t\t\t);
\t\t\tname = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product} /* {TARGET_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target} /* {TARGET_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget "{TARGET_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {TARGET_NAME};
\t\t\tproductName = {TARGET_NAME};
\t\t\tproductReference = {product} /* {TARGET_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2700;
\t\t\t\tLastUpgradeCheck = 2700;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject "{TARGET_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target} /* {TARGET_NAME} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f"\t\t\t\t{identifier('build:' + relative)} /* {name} in Sources */," for name, relative in files)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{project_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{project_settings}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{project_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{project_settings}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{target_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_settings}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{target_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{target_settings}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_config_list} /* Build configuration list for PBXProject "{TARGET_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{project_debug} /* Debug */,
\t\t\t\t{project_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_config_list} /* Build configuration list for PBXNativeTarget "{TARGET_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{target_debug} /* Debug */,
\t\t\t\t{target_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project} /* Project object */;
}}
"""
    return text


def scheme() -> str:
    target = identifier("target")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{TARGET_NAME}.app"
               BlueprintName = "{TARGET_NAME}"
               ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def write(path: Path, content: str, check: bool) -> bool:
    if check:
        return path.exists() and path.read_text(encoding="utf-8") == content
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail when the project is stale")
    args = parser.parse_args(argv)

    project_text = generate()
    scheme_text = scheme()
    if args.check:
        stale = [path for path, content in ((PROJECT_FILE, project_text), (SCHEME_FILE, scheme_text))
                 if not write(path, content, check=True)]
        for path in stale:
            print(f"stale: {path.relative_to(REPO_ROOT)}", file=sys.stderr)
        return 1 if stale else 0

    write(PROJECT_FILE, project_text, check=False)
    write(SCHEME_FILE, scheme_text, check=False)
    shared = len(shared_sources())
    legacy = len(legacy_sources())
    print(f"wrote {PROJECT_FILE.relative_to(REPO_ROOT)} ({shared} shared + {legacy} legacy sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
