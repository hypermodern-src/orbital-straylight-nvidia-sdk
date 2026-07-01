{ inputs, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    let
      indentWidth = 2;
      lineLength = 100;
    in
    { pkgs, ... }: {
      treefmt = {
        programs.biome.enable = true;
        settings.formatter.biome.allowComments = true;
        settings.formatter.biome.allowTrailingCommas = true;
        settings.formatter.biome.bracketSameLine = false;
        settings.formatter.biome.bracketSpacing = false;
        settings.formatter.biome.indentStyle = "space";
        settings.formatter.biome.indentWidth = 2;
        settings.formatter.biome.json.indentWidth = 2;
        settings.formatter.biome.json.indentStyle = "space";
        settings.formatter.biome.json.trailingComma = "es5";
        settings.formatter.biome.jsxQuoteStyle = "double";
        settings.formatter.biome.lineWidth = lineLength;
        settings.formatter.biome.trailingComma = "always";

        settings.formatter.biome.ignore = [
          "launchSettings.json"
          "package.json"
        ];
        settings.formatter.biome.excludes = [ ".vscode/settings.json" ];

        # `buildifier`: `.bzl` and `.bazel` files
        programs.buildifier.enable = true;
        settings.formatter.buildifier.excludes = [ ];

        # `clang-format`: C/C++, C#, Protocol Buffers, Java
        programs.clang-format.enable = true;
        programs.clang-format.includes = [
          "*.c"
          "*.h"
          "*.cpp"
          "*.cs"
          "*.proto"
          "*.java"
        ];

        # `deadnix`: dead code elimination for `nixlang`
        programs.deadnix.enable = true;
        settings.formatter.deadnix.excludes = [ ];

        # `dhall`
        programs.dhall.enable = true;
        programs.dhall.lint = true;
        settings.formatter.dhall.excludes = [ ];

        # `dos2unix`
        programs.dos2unix.enable = true;
        settings.formatter.dos2unix.excludes = [ ];

        # `fourmolu`: haskell formatting
        programs.fourmolu.enable = true;
        settings.formatter.fourmolu.excludes = [ ];

        # `hlint`: haskell linter
        programs.hlint.enable = true;
        settings.formatter.hlint.excludes = [ ];

        # `just`: justfiles
        programs.just.enable = true;
        settings.formatter.just.excludes = [ ];

        # `keep-sorted`: generally tidy
        programs.keep-sorted.enable = true;
        settings.formatter.keep-sorted.excludes = [ ];

        # `mdformat`: markdown with an emphasis on `README.md` style documents.
        # The mdBook docs (docs/) are excluded: mdformat's `wrap` reflows GFM
        # tables across lines, which breaks them (a GFM row must be one line),
        # so docs tables are hand-authored in multi-line form and left alone.
        programs.mdformat.enable = true;
        programs.mdformat.settings.number = true;
        programs.mdformat.settings.wrap = lineLength;
        settings.formatter.mdformat.excludes = [ "docs/**" ];

        # `nixfmt`: nixlang formatter...
        programs.nixfmt.enable = true;
        programs.nixfmt.strict = true;
        programs.nixfmt.width = lineLength;
        settings.formatter.nixfmt.excludes = [ ];

        # `ruff`: best python formatter except maybe that brand-new meta stuff...
        # TODO[b7r6]: set the indent width properly...
        programs.ruff-format.enable = true;
        programs.ruff-format.lineLength = lineLength;
        programs.ruff-check.enable = true;
        settings.formatter.ruff-format.excludes = [ ];
        settings.formatter.ruff-check.excludes = [ ];

        # `shfmt`: bash mostly, we could consider `beautysh`
        programs.shfmt.enable = true;
        programs.shfmt.indent_size = indentWidth;
        settings.formatter.shfmt.excludes = [ ];

        # `statix`: static anlaysis for `nixlang`
        programs.statix.enable = true;
        settings.formatter.statix.excludes = [ ];

        # `stylish-haskell`: haskell formatting that's a little extra...
        programs.stylish-haskell.enable = true;
        settings.formatter.stylish-haskell.excludes = [ ];

        # `taplo`: TOML
        programs.taplo.enable = true;
        settings.formatter.taplo.excludes = [ ];

        # XML, i.e. most `dotnet`/`msbuild` configuration mostly...
        settings.formatter.xmllint = {
          command = "${pkgs.libxml2}/bin/xmllint";
          package = pkgs.libxml2;
          options = [
            "--format"
            "--encode"
            "UTF-8"
          ];
          includes = [
            "*.xml"
            "*.csproj"
            "*.props"
            "*.targets"
            "*.svg"
            "*.xaml"
          ];
          excludes = [ "design/**/*.svg" ];
        };

        # `yamlfmt`: YAML
        programs.yamlfmt.enable = true;
        settings.formatter.yamlfmt.excludes = [ ];
      };
    };
}
