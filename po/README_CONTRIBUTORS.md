# Localizing Witty

The Linux UI uses gettext for translatable labels. Use `internal_os.translate`
with a string literal so the translation tools can extract it.

```v
// Translators: Button label that closes the dialog without applying changes.
label := internal_os.translate('Cancel')
```

The translation template lives at `po/com.alexander.witty.pot`. After editing
translated strings, update the template and locale catalogs from the repository
root.

```sh
v -path "$PWD|@vlib|@vmodules" run tools/build update-translations
```

The build compiles each locale catalog into a `.mo` file under
`share/locale/<LOCALE>/LC_MESSAGES/`.
