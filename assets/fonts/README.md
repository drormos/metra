# Fonts

Both families are licensed under the SIL Open Font License 1.1
(`OFL-Saira.txt`, `OFL-SairaExtraCondensed.txt`), from
https://github.com/google/fonts.

- `SairaExtraCondensed-SemiBold.ttf`, `SairaExtraCondensed-Bold.ttf`: copied
  as published (`ofl/sairaextracondensed/`).
- `Saira-Medium.ttf` (500), `Saira-SemiBold.ttf` (600): static instances cut
  from the variable `ofl/saira/Saira[wdth,wght].ttf`, because variable-font
  weights are not applied reliably across Flutter platforms:

  ```sh
  pip install fonttools
  fonttools varLib.instancer 'Saira[wdth,wght].ttf' wght=500 wdth=100 --update-name-table -o Saira-Medium.ttf
  fonttools varLib.instancer 'Saira[wdth,wght].ttf' wght=600 wdth=100 --update-name-table -o Saira-SemiBold.ttf
  ```
