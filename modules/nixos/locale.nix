# タイムゾーン・国際化設定
{ specialArgs, ... }: {
  time.timeZone = specialArgs.settings.timezone;

  i18n.defaultLocale = specialArgs.settings.locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = specialArgs.settings.locale;
    LC_IDENTIFICATION = specialArgs.settings.locale;
    LC_MEASUREMENT = specialArgs.settings.locale;
    LC_MONETARY = specialArgs.settings.locale;
    LC_NAME = specialArgs.settings.locale;
    LC_NUMERIC = specialArgs.settings.locale;
    LC_PAPER = specialArgs.settings.locale;
    LC_TELEPHONE = specialArgs.settings.locale;
    LC_TIME = specialArgs.settings.locale;
  };
}
