# Coverage against Halide 3.2.1

The comparison target is the supplied 3.2.1 build, not an unspecified future
release. Camera and photo-lab geometry were observed on an iPhone 17 Pro.
An implemented path is not proof of identical behavior or image output.

## Main gaps

- **Rendering:** no tone fusion or matched Process Zero development. HDR gain-map export and
  HDR photo-lab rendering are being validated; live view remains native video.
- **Looks and film:** five independent recipes instead of the reference looks;
  grain, bloom, detail and vignette are basic effects, not a matched film engine.
- **Library:** local captures/imports only, not browsing or editing existing
  Apple Photos assets. No album selection, selection/batch actions or GPS/map UI.
- **Interface:** core camera positions and the photo-lab drawer now follow observed
  arrangements. Grid/level menus, flash modes, white-balance presets and settings card navigation
  now follow direct observations. Film thumbnails, ruler behavior, transitions and expanded
  metadata are still different. Dynamic manual-setting toolbar items are missing.
- **System entry points:** lock-screen capture, widgets, App Intents/Shortcuts and
  Camera Control parameter sliders are absent; shutter events are implemented.
- **Settings:** icon selection, per-look defaults, exact themes and some advanced
  controls remain different. Membership and support use Lucent's own behavior.
- **Device coverage:** the current iPhone UI is locked to portrait. Landscape,
  iPad, full VoiceOver/localization, long exposures, RAW/Photos pairing, camera
  calibration and sustained thermal/memory behavior need acceptance testing.

## Detailed coverage

| Feature | Lucent 0.1.1 status | Evidence or remaining difference |
| --- | --- | --- |
| Native live viewfinder | Implemented | Live nonblack buffers at about 30 fps on the connected iPhone 17 Pro; user confirmed visible image |
| Portrait camera control positions | Implemented | Observed reference geometry; user confirmed controls look right |
| Physical lens / front selection | Implemented | Alias deduplication tested; one preferred front camera; full lens/mirroring QA outstanding |
| Digital crops | Implemented | Wide/tele 2× crops plus physical lenses; software crop preserves the Bayer capture path |
| Manual ISO, shutter, EV and focus | Implemented | Exposure math and UI tests; EXIF and changing-light acceptance outstanding |
| Shutter / ISO priority | Implemented | Native when supported; bounded feedback otherwise; not calibrated against reference |
| Aperture / aperture priority | Conditional | iOS 27 and eligible hardware required; not tested on variable-aperture hardware |
| White balance | Implemented | Device gains and RAW development controls; no reference color calibration |
| Bayer RAW / ProRAW / processed capture | Implemented | Explicit separate paths; supported dimensions requested; per-lens capture matrix outstanding |
| RAW development | Independent implementation | Supplied Bayer and ProRAW decode tested; calibrated decoder defaults restored; optional minimal processing |
| Film looks and simulation | Partial | Five original looks and basic effects; no rendering equivalence |
| HDR / tone fusion | Partial | JPEG/HEIC gain-map encoding and HDR lab rendering; validation in progress; no tone fusion |
| Histogram, zebras, peaking, loupe | Implemented | Small 8-bit video analysis; not a RAW histogram; scene thresholds not calibrated |
| Level and composition | Implemented | Off/On/Auto level; nested Golden Ratio in four corners, rabatment, grid, thirds and off; hardware rendering comparison outstanding |
| Aspect crops | Implemented | Original, Square, 35mm, Pano, Wide and adaptive Insta; crop-bound tests in both orientations |
| Local photo lab / image and RAW import | Implemented | Original retention, source-based edits and supplied RAW fixtures tested |
| Swipe gallery / zoom / 1:1 inspection | Implemented | Interactive pages; paging pauses while editing or magnified; originals/recipes stay attached to their record |
| Favorites / photograph removal | Implemented | Favorites persist; removal moves original, render and recipe together to local .Trash |
| Existing Apple Photos browsing | Missing | Add-only export integration currently; local library and Files imports only |
| Exposure / crop / straighten / resize / balance | Implemented | Imaging tests; controls and output not numerically matched to reference |
| Expanded metadata | Partial | Date, camera, ISO, shutter and aperture; optional Off/Coarse/Fine GPS tagging; no reference metadata grid or map |
| JPEG / HEIC and paired RAW Photos export | Implemented | Quality selection, format preservation through edits, optional RAW-only Photos export; hardware Photos pairing acceptance outstanding |
| Flash / timer / hardware shutter | Implemented | Capability checks; Off/On/Auto flash, including supported sensor RAW; full device QA outstanding |
| Lock-screen / widgets / Shortcuts | Missing | No extension or intent targets |
| Camera Control sliders | Missing | Shutter events only |
| iPad / landscape / accessibility / localization | Incomplete | iPhone portrait active; English; wider device and accessibility audits outstanding |
| Capture settings | Partial | Processing priority, compression, max resolution, fast capture priority, lossy ProRAW, RAW-only export and location controls; capture matrix QA outstanding |
| Settings presentation | Partial | Matching sheet/card/navigation organization for root, Capture and Looks; custom icons, fonts and Customize content still differ |
| Exact interaction and photographic equivalence | Not achieved | Requires controlled side-by-side tests with explicit tolerances |

Sources: [Mark III workflows](https://www.lux.camera/halide-mark-iii/),
[3.2 aperture and looks](https://www.lux.camera/halide-aperture-update/),
[Process Zero](https://www.lux.camera/process-zero-manual/), plus private runtime
observations of the supplied build. No reference assets or processing code are
included in the public source.
