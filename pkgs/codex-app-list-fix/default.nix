{
  codex,
  codexAppListFixSrc,
  fetchurl,
  rustPlatform,
}:

let
  version = "0.147.0-alpha.6.5";
  librustyV8 = fetchurl {
    name = "librusty_v8-150.4.0-ptrcomp-sandbox";
    url = "https://github.com/openai/codex/releases/download/rusty-v8-v150.4.0/librusty_v8_ptrcomp_sandbox_release_aarch64-apple-darwin.a.gz";
    hash = "sha256-AK27SHmISMd1UEQcaGc6XoUpuOG3PqvN7iMss5tA9KE=";
  };
  librustyV8Binding = fetchurl {
    name = "src_binding_ptrcomp_sandbox_release_aarch64-apple-darwin.rs";
    url = "https://github.com/openai/codex/releases/download/rusty-v8-v150.4.0/src_binding_ptrcomp_sandbox_release_aarch64-apple-darwin.rs";
    hash = "sha256-ylrfDPicmnCtRgrnNkiy/om3SqETs8t/dXtqArdYOU8=";
  };
  codexBase = codex.override { librusty_v8 = librustyV8; };
in
codexBase.overrideAttrs (_old: {
  pname = "codex-app-list-fix";
  inherit version;

  src = codexAppListFixSrc;
  sourceRoot = "source/codex-rs";

  cargoDeps = rustPlatform.fetchCargoVendor {
    name = "codex-app-list-fix-${version}-vendor";
    src = codexAppListFixSrc;
    sourceRoot = "source/codex-rs";
    hash = "sha256-p0KoIcA8WW1uIFfMZ2ZCd6p1Ih/feXZRbBWicILAaMc=";
  };

  env = (_old.env or { }) // {
    RUSTY_V8_SRC_BINDING_PATH = librustyV8Binding;
  };

  # Codex 0.147 no longer depends on webrtc-sys, so omit the workaround from
  # nixpkgs' 0.144 package while retaining its Darwin release-profile fix.
  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "thin"' "" \
      --replace-fail 'codegen-units = 4' ""
  '';
})
