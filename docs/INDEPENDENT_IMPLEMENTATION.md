# Independent implementation record

## Inputs and separation

The supplied archive identified Halide 3.2.1. Its directory listing, selected
Info.plist metadata, packaged English localization entries, compiled symbol names,
and Swift stored-field/enum reflection metadata were inspected to
enumerate features and screens. The installed reference app was also observed
through screenshots, accessibility trees and test interactions on an iPhone.
Those black-box observations informed the camera control positions and photo-lab
arrangement. No executable was disassembled or decompiled. No implementation code,
shader, LUT, font, artwork or other binary resource was incorporated into Lucent.
The original IPA and private device observations are outside the public sources.

Feature requirements came from those observations, the following public
descriptions and Apple's public APIs/installed SDK headers. Code and generated scene were written
independently for this project. The same implementer read the public descriptions
and wrote the code; this is **not a claim of an audited, independently staffed
clean-room process or a legal clearance opinion**.

## Public behavioral references

- [Halide Mark III](https://www.lux.camera/halide-mark-iii/): camera workflows,
  aspect crops, composition guides, priority exposure, photo lab and RAW import.
- [Halide 3.2](https://www.lux.camera/halide-aperture-update/): variable aperture
  and aperture priority where the hardware exposes them.
- [Process Zero manual](https://www.lux.camera/process-zero-manual/): single
  sensor capture, separate development, preserved digital negatives and paired
  exports. Lucent does not claim to reproduce that proprietary rendering.
- [Halide product page](https://halide.cam/): focus aids and manual capture.
- [Apple RAW photo capture](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-format).
- [Apple CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter).

References were consulted on October 12, 2026. Short control labels and settings descriptions follow the observed interface;
implementation requirements were independently derived from observed behavior. Public descriptions cannot establish exact internal behavior.

## Original components

The UI uses system typography and SF Symbols. The simulator scene is procedurally
drawn. The Neutral, Ember, Verdant, Silver and Charcoal recipes use ordinary Core
Image operations with independently selected coefficients. Highlight bloom is a
simple image-space effect; it is not a physically calibrated film model. Grain,
contrast and tone response are not asserted to match another product.

## What equivalence would require

1. A versioned behavioral specification from lawful black-box observations.
2. A device/OS/lens coverage matrix and paired test captures of controlled scenes.
3. Numerical tolerances for exposure, color, RAW metadata, export and orientation.
4. Independently authored implementations of missing features.
5. Documented conformance results, with differences published alongside the release.

A binary file and a marketing feature list cannot establish 1:1 image equivalence.
Source availability alone also cannot guarantee commercial product behavior.
