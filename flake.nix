{
  description = "A flake for building LLVM from scratch in Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    llvm-project = {
      url = "github:llvm/llvm-project"; # Change the commit you want by overriding the url when using the flake  
      flake = false;
    };
  };

  outputs = { self, nixpkgs, llvm-project }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems f;

    mkLlvmFor = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      gcc = pkgs.stdenv.cc.cc;
      libc = pkgs.stdenv.cc.libc;
      gccInstallDir = "${gcc}/lib/gcc/${pkgs.stdenv.hostPlatform.config}/${gcc.version}";
      
      clangCfg = pkgs.writeText "clang.cfg" ''
        --gcc-install-dir=${gccInstallDir}
        -B${libc}/lib
        -L${libc}/lib
        -L${gcc.lib}/lib
        -idirafter ${libc.dev}/include
      '';

      clangCfgDir = pkgs.runCommand "clang-cfg" { } ''
        mkdir -p $out
        cp ${clangCfg} $out/clang.cfg
        cp ${clangCfg} $out/clang++.cfg
      '';

    in lib.makeOverridable ({
      projects ? [ "clang" "mlir" "flang" ],
      runtimes ? [ "compiler-rt" "flang-rt" "openmp" ],
      extraCmakeFlags ? [ "-DLIBOMP_FORTRAN_MODULES=ON" ],
    }: pkgs.llvmPackages.stdenv.mkDerivation {
      pname = "llvm-nix";
      version = "1.0.0";

      src = llvm-project;
      sourceRoot = "source/llvm";

      nativeBuildInputs = with pkgs; [
        cmake
        llvmPackages.bintools
        ninja
        python3
      ];
      buildInputs = with pkgs; [ gcc zlib ];

      hardeningDisable = [ "libcxxhardeningfast" ];

      cmakeFlags = [
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
        "-DLLVM_ENABLE_ASSERTIONS=ON"
        "-DLLVM_TARGETS_TO_BUILD=host"
        "-DLLVM_LIT_ARGS=-v"
        "-DLLVM_ENABLE_PROJECTS=${lib.concatStringsSep ";" projects}"
        "-DLLVM_ENABLE_RUNTIMES=${lib.concatStringsSep ";" runtimes}"
        "-DLLVM_USE_LINKER=lld"
        "-DLLVM_PARALLEL_LINK_JOBS=1"
        "-DCLANG_CONFIG_FILE_SYSTEM_DIR=${clangCfgDir}"
      ] ++ extraCmakeFlags;

      preBuild = ''
        mkdir -p bin
        cp ${clangCfg} bin/clang.cfg
        cp ${clangCfg} bin/clang++.cfg
      '';

      doCheck = false;
      requiredSystemFeatures = [ "big-parallel" ];
    });
  in {
    packages = forAllSystems (system: let
      mkLlvm = mkLlvmFor system;
    in {
      default = mkLlvm { };
      llvm-nix = mkLlvm { };
    });
  };
}