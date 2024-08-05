{
  stdenv,
  lib,
  fetchFromGitHub,
  python3,
  libusb1,
  abseil-cpp_202308,
  flatbuffers,
  xxd,
  gcc12Stdenv,
}:

let
  flatbuffers_1_12 = flatbuffers.overrideAttrs (oldAttrs: rec {
    version = "1.12.1";
    NIX_CFLAGS_COMPILE = "-Wno-error=class-memaccess -Wno-error=maybe-uninitialized -Wno-error=stringop-overflow -Wno-error=uninitialized";
    cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [ "-DFLATBUFFERS_BUILD_SHAREDLIB=ON" ];
    NIX_CXXSTDLIB_COMPILE = "-std=c++17";
    configureFlags = (oldAttrs.configureFlags or [ ]) ++ [ "--enable-shared" ];
    src = fetchFromGitHub {
      owner = "google";
      repo = "flatbuffers";
      rev = "v${version}";
      sha256 = "sha256-5sHddlqWx/5d5/FOMK7qRlR5xbUR47rfejuXI1jymWM=";
    };
  });
  stdenv = gcc12Stdenv;

in
stdenv.mkDerivation rec {
  pname = "libedgetpu";
  version = "e35aed18fea2e2d25d98352e5a5bd357c170bd4d";

  src = fetchFromGitHub {
    owner = "google-coral";
    repo = pname;
    rev = version;
    sha256 = "sha256-SabiFG/EgspiCFpg8XQs6RjFhrPPUfhILPmYQQA1E2w=";
  };

  # patches = [ ./libedgetpu-stddef.patch ];

  makeFlags = [
    "-f"
    "makefile_build/Makefile"
    "libedgetpu"
  ];

  buildInputs = [
    libusb1
    abseil-cpp_202308
    flatbuffers_1_12
  ];

  nativeBuildInputs = [ xxd ];

  NIX_CXXSTDLIB_COMPILE = "-std=c++17";

  TFROOT = "${fetchFromGitHub {
    owner = "tensorflow";
    repo = "tensorflow";
    rev = "v2.16.1"; # latest rev providing tensorflow/lite/c/common.c
    sha256 = "sha256-MFqsVdSqbNDNZSQtCQ4/4DRpJPG35I0La4MLtRp37Rk=";
  }}";

  enableParallelBuilding = false;

  installPhase = ''
    mkdir -p $out/lib
    cp out/direct/k8/libedgetpu.so.1.0 $out/lib
    ln -s $out/lib/libedgetpu.so.1.0 $out/lib/libedgetpu.so.1
    mkdir -p $out/lib/udev/rules.d
    cp debian/edgetpu-accelerator.rules $out/lib/udev/rules.d/99-edgetpu-accelerator.rules
  '';
}
