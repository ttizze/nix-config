{
  security.pam.services.sudo_local.touchIdAuth = true;

  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = false;
    blockAllIncoming = false;
    allowSigned = true;
    allowSignedApp = true;
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };

    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = true;

    dock = {
      autohide = true;
      autohide-delay = 0.0;
      mru-spaces = false;
      show-recents = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXDefaultSearchScope = "SCcf";
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
    };

    CustomUserPreferences."com.cmuxterm.app" = {
      SUEnableAutomaticChecks = true;
      appearanceMode = "system";
      confirmQuit = "never";
      "rightSidebar.mode" = "files";
      warnBeforeQuitShortcut = false;
    };
  };
}
