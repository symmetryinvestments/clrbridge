{ pkgs ? import (builtins.fetchTarball "https://releases.nixos.org/nixos/20.09/nixos-20.09.3341.df8e3bd1109/nixexprs.tar.xz") {} }:
  pkgs.mkShell {
    nativeBuildInputs = [
    pkgs.rund
    pkgs.ldc
    # We use the C# compiler from mono (aka "csc")
    pkgs.mono
    # We use libcoreclr.so from this package
    pkgs.dotnetCorePackages.netcore_3_1 ];
  }
