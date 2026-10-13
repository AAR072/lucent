# Device acceptance checklist

Observed device: iPhone 17 Pro, iOS 27.0.1. Do not mark hardware behavior passed
based on simulator tests. Private comparison images and signing material stay
outside the public sources.

| Test | Result |
| --- | --- |
| Signed build installs and launches natively | Passed on the connected iPhone; private bundle ID and profile overrides |
| Live camera stream / portrait control arrangement | Passed: about 30 fps, nonblack buffers; user confirmed visible image and correct controls |
| Camera permission denial/recovery and background/resume | Full acceptance outstanding |
| Physical lens/front selection, mirroring, unsupported RAW | Full acceptance outstanding; discovery alias logic tested |
| Manual ISO/shutter reflected in EXIF/DNG, long exposures | Outstanding |
| Priority exposure under changing light | Outstanding |
| White balance and focus endpoints | Outstanding |
| Supplied Bayer RAW and Apple ProRAW development | Decoder tests passed; calibrated defaults preserved; separate source types identified |
| Maximum resolution on every active lens/format | Outstanding |
| HEIC/JPEG interoperability and RAW Photos pairing | Outstanding |
| Denied Photos access preserves local data | Code path implemented; device permission test outstanding |
| Orientation, mirroring and focus mapping | Portrait arrangement user-confirmed; rotated captures and all lenses still need tests |
| Timer / hardware shutter / sustained thermals and memory | Outstanding |
| External-camera RAW import matrix | Supplied DNGs tested; CR2/NEF/RAF coverage outstanding |
| Controlled target conformance | Outstanding; no 1:1 claim |

During diagnosis, Xcode Device Hub's live screen viewer caused camera buffers to
be black while the capture session remained running. Quitting the viewer restored
live frames immediately. Keep screen mirroring off for camera acceptance checks;
validate on the phone and through normal logs rather than a live screen viewer.

Use a color chart, high-contrast edge target, level and controlled lighting.
Record model, OS, lens, dimensions, mode, shutter, ISO, white balance and recipe.
