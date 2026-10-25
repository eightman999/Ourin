# Minimal additional-SHIORI dictionaries

Ourin-authored regression fixtures, distributed under the repository's Apache-2.0 license.
They are not redistributed real ghosts and do not establish full original-engine compatibility.

Each dictionary answers OnBoot / OnAITalk / OnClose, assigns 37 in OnRemember, and reads it
in OnRecall. Engine-specific random-talk names are intentional: ese-shiori uses OnRandomTalk,
NiseShiori OnNSRandomTalk, Hisui OnHisuiFreeTalk, and Yuhna OnYuhnaRandomTalk.

Yuhna's binary `dic.ydf` has a `YDF/1.07 Ourin fixture` header and a big-endian 32-bit event count.
Its five records are, in order:

| Event | Script |
| --- | --- |
| OnYuhnaRandomTalk | talk:yuhna |
| OnBoot | boot:yuhna |
| OnRemember | {count=37}remember |
| OnRecall | {count} |
| OnClose | close:yuhna |

Each record contains a big-endian 16-bit event-name length, ASCII event name, four zero bytes
(alias count), one byte `1` (script count), a big-endian 16-bit script length, one zero byte,
and the ASCII script. Random talk must be the first record for this upstream parser.
