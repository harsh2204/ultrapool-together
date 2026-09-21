# Ball artwork

Original multiplayer ball artwork generated through [Fal](https://fal.ai/) using `bytedance/seedream/v5/pro/text-to-image` (Seedream 5 Pro).

The eight PNG sources in `mod/assets/balls/` are 1536 × 768 pixels. Each contains two matching emblems on a solid color background. The texture loader takes the left square face and packs it into a 1024 × 768 cube atlas with 256-pixel faces, repeating the emblem on all six faces and generating mipmaps. This matches the native textures and the sphere shader's fixed mip-level calculation, keeping small table and shop balls sharp. Lighting comes from the native ball shader.

| Ball | Source file | Fal request | Original output |
| --- | --- | --- | --- |
| Relay | [relay.png](../mod/assets/balls/relay.png) | `01a0c271-451b-72f0-a018-1d6e44f1e8b3` | [PNG](https://v3b.fal.media/files/b/0aab4684/IIqMGz7Kjm9jh5RdhKaTp_0c628538684247c4829f701a14f50084.png) |
| Called Shot | [called_shot.png](../mod/assets/balls/called_shot.png) | `01a0c273-c29a-7f72-8a57-f70bd13e56fd` | [PNG](https://v3b.fal.media/files/b/0aab4691/VJ353Tf6MdRh-cmGfA6pW_f4a85bff073a4d99bf96e973d318087a.png) |
| Patience | [patience.png](../mod/assets/balls/patience.png) | `01a0c274-7373-7072-bba9-2580d1d86b30` | [PNG](https://v3b.fal.media/files/b/0aab4698/MzpKcsyryUXYeR2MiL_Eb_7ace312111ff46d8945ae95704a7d93b.png) |
| Bounty | [bounty.png](../mod/assets/balls/bounty.png) | `01a0c275-23e1-7792-aaed-90f422e593bb` | [PNG](https://v3b.fal.media/files/b/0aab469b/yrBRDH-tmhGbJzE1U6RsN_3828e09f22e04295981c2a29b886471a.png) |
| Bankroll | [bankroll.png](../mod/assets/balls/bankroll.png) | `01a0c275-d453-7d83-8ea8-586484194655` | [PNG](https://v3b.fal.media/files/b/0aab469e/jtiEHpwMdbA__NS9Yh53z_7699acbf8aa14e6ca7b6bc562d724fd7.png) |
| Lifeline | [lifeline.png](../mod/assets/balls/lifeline.png) | `01a0c276-8ba0-7eb1-b549-d6185cca7c1c` | [PNG](https://v3b.fal.media/files/b/0aab46a4/lTFYWQibMEAWkL9Gf3ReE_081a6639b6ad44d6a48c80c29a1c1cd3.png) |
| Encore | [encore.png](../mod/assets/balls/encore.png) | `01a0c277-3c1d-7ff1-8bcd-548b77c0e772` | [PNG](https://v3b.fal.media/files/b/0aab46a8/_sKmLZt5UnOyKYioBXXCV_5bbe189e3b424d96a2f3e28ac9d5b7dd.png) |
| Domino | [domino.png](../mod/assets/balls/domino.png) | `01a0c277-ec86-7ba1-bae2-b8dbbedde9d8` | [PNG](https://v3b.fal.media/files/b/0aab46ae/4ov3xzX0ijZG-0YWlrpNR_29f4bace901a4d0288a31b1867d36cd3.png) |
