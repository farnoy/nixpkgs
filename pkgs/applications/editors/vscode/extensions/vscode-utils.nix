{
  stdenv,
  lib,
  buildEnv,
  writeShellScriptBin,
  fetchurl,
  vscode,
  unzip,
  jq,
}:
let
  buildVscodeExtension =
    a@{
      pname ? null, # Only optional for backward compatibility.
      src,
      # Same as "Unique Identifier" on the extension's web page.
      # For the moment, only serve as unique extension dir.
      vscodeExtPublisher,
      vscodeExtName,
      vscodeExtUniqueId,
      configurePhase ? ''
        runHook preConfigure
        runHook postConfigure
      '',
      buildPhase ? ''
        runHook preBuild
        runHook postBuild
      '',
      dontPatchELF ? true,
      dontStrip ? true,
      nativeBuildInputs ? [ ],
      passthru ? { },
      ...
    }:
    stdenv.mkDerivation (
      (removeAttrs a [
        "vscodeExtUniqueId"
        "pname"
      ])
      // (lib.optionalAttrs (pname != null) {
        pname = "vscode-extension-${pname}";
      })
      // {

        passthru = passthru // {
          inherit vscodeExtPublisher vscodeExtName vscodeExtUniqueId;
        };

        inherit
          configurePhase
          buildPhase
          dontPatchELF
          dontStrip
          ;

        # Some .vsix files contain other directories (e.g., `package`) that we don't use.
        # If other directories are present but `sourceRoot` is unset, the unpacker phase fails.
        sourceRoot = "extension";

        installPrefix = "share/vscode/extensions/${vscodeExtUniqueId}";

        nativeBuildInputs = [ unzip ] ++ nativeBuildInputs;

        installPhase = ''

          runHook preInstall

          mkdir -p "$out/$installPrefix"
          find . -mindepth 1 -maxdepth 1 | xargs -d'\n' mv -t "$out/$installPrefix/"

          runHook postInstall
        '';
      }
    );

  fetchVsixFromVscodeMarketplace =
    mktplcExtRef: fetchurl (import ./mktplcExtRefToFetchArgs.nix mktplcExtRef);

  buildVscodeMarketplaceExtension =
    a@{
      name ? "",
      src ? null,
      vsix ? null,
      mktplcRef,
      ...
    }:
    assert "" == name;
    assert null == src;
    buildVscodeExtension (
      (removeAttrs a [
        "mktplcRef"
        "vsix"
      ])
      // {
        pname = "${mktplcRef.publisher}-${mktplcRef.name}";
        version = mktplcRef.version;
        src = if (vsix != null) then vsix else fetchVsixFromVscodeMarketplace mktplcRef;
        vscodeExtPublisher = mktplcRef.publisher;
        vscodeExtName = mktplcRef.name;
        vscodeExtUniqueId = "${mktplcRef.publisher}.${mktplcRef.name}";
      }
    );

  mktplcRefAttrList = [
    "name"
    "publisher"
    "version"
    "sha256"
    "hash"
    "arch"
  ];

  mktplcExtRefToExtDrv =
    ext:
    buildVscodeMarketplaceExtension (
      removeAttrs ext mktplcRefAttrList
      // {
        mktplcRef = builtins.intersectAttrs (lib.genAttrs mktplcRefAttrList (_: null)) ext;
      }
    );

  extensionFromVscodeMarketplace = mktplcExtRefToExtDrv;
  extensionsFromVscodeMarketplace =
    mktplcExtRefList: builtins.map extensionFromVscodeMarketplace mktplcExtRefList;

  vscodeWithConfiguration = import ./vscodeWithConfiguration.nix {
    inherit lib extensionsFromVscodeMarketplace writeShellScriptBin;
    vscodeDefault = vscode;
  };

  vscodeExts2nix = import ./vscodeExts2nix.nix {
    inherit lib writeShellScriptBin;
    vscodeDefault = vscode;
  };

  vscodeEnv = import ./vscodeEnv.nix {
    inherit
      lib
      buildEnv
      writeShellScriptBin
      extensionsFromVscodeMarketplace
      jq
      ;
    vscodeDefault = vscode;
  };

  toExtensionJsonEntry = ext: rec {
    identifier = {
      id = ext.vscodeExtUniqueId;
      uuid = "";
    };

    version = ext.version;

    relativeLocation = ext.vscodeExtUniqueId;

    location = {
      "$mid" = 1;
      fsPath = ext.outPath + "/share/vscode/extensions/${ext.vscodeExtUniqueId}";
      path = location.fsPath;
      scheme = "file";
    };

    metadata = {
      id = "";
      publisherId = "";
      publisherDisplayName = ext.vscodeExtPublisher;
      targetPlatform = "undefined";
      isApplicationScoped = false;
      updated = false;
      isPreReleaseVersion = false;
      installedTimestamp = 0;
      preRelease = false;
    };
  };

  toExtensionJson = extensions: builtins.toJSON (map toExtensionJsonEntry extensions);
in
{
  inherit
    fetchVsixFromVscodeMarketplace
    buildVscodeExtension
    buildVscodeMarketplaceExtension
    extensionFromVscodeMarketplace
    extensionsFromVscodeMarketplace
    vscodeWithConfiguration
    vscodeExts2nix
    vscodeEnv
    toExtensionJsonEntry
    toExtensionJson
    ;
}
