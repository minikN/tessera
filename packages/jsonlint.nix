{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm,
  nodejs,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "jsonlint";
  version = "17.0.1";

  src = fetchFromGitHub {
    owner = "prantlf";
    repo = "jsonlint";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+G4+Lp2fbRfNjYk3svYCt3p8dwLzRCxWWAb7xTT4dYM=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 5;
    hash = "sha256-0v9gjiPI9XGZpdkz6ECIPO5RYEdGMIFyrCzhdazQLBY=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    cat src/prefix.js.txt src/unicode.js src/custom-parser.js src/pointer.js \
      src/native-parser.js src/configurable-parser.js src/suffix.js.txt > lib/jsonlint.js
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    rm -rf node_modules
    pnpm install --offline --prod --ignore-scripts --frozen-lockfile
    mkdir -p $out/lib/node_modules/jsonlint
    cp -r lib node_modules package.json $out/lib/node_modules/jsonlint
    makeWrapper ${lib.getExe nodejs} $out/bin/jsonlint \
      --add-flags $out/lib/node_modules/jsonlint/lib/cli.js
    runHook postInstall
  '';

  meta = {
    description = "JSON, CJSON and JSON5 parser, validator and pretty-printer";
    homepage = "https://github.com/prantlf/jsonlint";
    license = lib.licenses.mit;
    mainProgram = "jsonlint";
  };
})
