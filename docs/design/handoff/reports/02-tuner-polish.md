# 02 · Tuner polish: report

Build 1.8.0+106, installed on the phone (Metra dev). `flutter analyze` is clean and `flutter test` passes (1656 tests).

## What changed
1. **Reference row:** one line, "A4 =" then the 430–450 Hz stepper, centred. TalkBack still hears "Reference A4". At 200% text "A4 =" may wrap, but nothing overflows.
2. **Sizes:** the note is 200dp tall (its cap height), the meter is 88dp tall and full width (between the 24px margins), and the needle is 4dp (6dp in tune). Everything fits on one screen without scrolling at 115% on a 360dp phone and at 100% on a 412dp phone. Tests check this, and the real phone (363dp wide, 115% text) shows the same.
3. **Sharps:** the ♯ and the octave share one small column, tight to the letter's right. The ♯ starts at the cap height and the octave sits on the letter's baseline. The letter, ♯ and octave are centred as one group, measured on what's drawn. A flat would use the same column, but flats never show (note names use sharps).

Also:
- A 12dp gap under the note, so the cents line no longer touches it.
- The silence floor is lower (−54 dBFS). The phone's unprocessed mic is quiet: a speaker a metre away read just above the old floor.

## Screenshots (from the phone, status bar and sidebar dots cropped)
`docs/design/screens/tuner-sharp-v2-115.png` (A♯3 +8 cents), `tuner-in-tune-v2-115.png` (A3), `tuner-silent-v2-115.png`. The tones were played from the Mac's speakers.

## For the designer
- **Silence "–":** at 290px the dash is a wide grey slab at mid-height (see `tuner-silent-v2-115.png`). It reads more like a placeholder bar than a dash. Do you want it smaller, or a different empty state?

## Phone checks (from reports/01-tuner.md): what I saw
- **Top row at 115%:** four equal squares, "4/4" centred, the tuning fork clear. I didn't check the title's shrink with a long song name on the phone; the screen tests cover it.
- **Permission flow:** the first opening showed the privacy line with Android's dialog over it ("Allow Metra dev to record audio?"). Dror allowed it. **Refusal path (checked after Dror removed the permission in Settings):** opening the tuner showed the line and "Allow microphone", with no dialog. Tapping it showed Android's dialog. After one "Don't allow", the next tap opened Metra dev's page in Settings, because Android counted the removal in Settings as a refusal. Allowed there, the tuner started listening by itself on return and read A3 "In tune".
- **Tuning:** the phone read the test tones exactly: 234.16 Hz for an A♯3 8 cents sharp (shown "+8 cents · 234.2 Hz"), and 220.00 Hz for A3 ("In tune", the needle white and thick). It went back to "Play a string" about a second after the tone stopped. **Not tried with a real guitar string**, so the low E is still open.
- **Click:** it was playing when the tuner opened, stopped, and was still stopped after Back.
- **Microphone:** recording (Android's record monitor, UNPROCESSED source) only while the tuner is open. It stopped on Back, stopped on Home with the tuner open, and restarted on returning to the tuner.
- **Screen on:** a screen-bright wake lock was held for Metra while the tuner was open.

## Still worth a check by hand
- A real guitar, especially the low E2.
