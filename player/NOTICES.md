# Third-Party Notices

WMusic is a local adaptation of [Bòcan](https://github.com/bocan/bocan-music)
by Chris Funderburg (Copyright 2026), licensed under the Apache License,
Version 2.0. The original copyright notice and full Apache 2.0 licence are
included in WMusic's bundled `LICENSE` file.

The following components retain their own authorship and licences. Their
notices and source links are listed here; applicable licence files for bundled
native libraries are also included in `ThirdPartyLicenses` in the app bundle.

---

## FFmpeg 9.0.2

<https://ffmpeg.org>

WMusic bundles FFmpeg libraries from Homebrew's FFmpeg build. The selected
configuration makes this FFmpeg build subject to the **GNU General Public Licence, version 3 or later (GPL 3+)**.
This designation applies to the FFmpeg build; separately bundled libraries
retain their own licences.

The applicable FFmpeg licence text is included as
`ThirdPartyLicenses/ffmpeg-COPYING.GPLv3` and is available at
<https://www.gnu.org/licenses/gpl-3.0.html>.

FFmpeg source code is available at <https://ffmpeg.org/download.html>.
The Homebrew formula used to build the bundled dylibs is
`homebrew-core/Formula/f/ffmpeg.rb`.

---

## TagLib 2.3.2

<https://taglib.org>

Licensed under the **GNU Lesser General Public Licence, version 2.1** or, at
your option, the **Mozilla Public Licence 1.1**.

### LGPL 2.1

The LGPL 2.1 full text is available at:
<https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>

### Mozilla Public Licence 1.1

The MPL 1.1 full text is available at:
<https://www.mozilla.org/en-US/MPL/1.1/>

TagLib source code is available at <https://github.com/taglib/taglib>.

---

## Chromaprint / fpcalc 1.6.1_1

<https://acoustid.org/chromaprint>

Licensed under the **GNU Lesser General Public Licence, version 2.1 or later**
(LGPL 2.1+).

The LGPL 2.1 full text is available at:
<https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>

Chromaprint source code is available at
<https://github.com/acoustid/chromaprint>.

---

## Other bundled native libraries

These are dynamic libraries included with FFmpeg or fpcalc in this local build.
Each component keeps its own licence; its licence text is included in
`ThirdPartyLicenses` in the app bundle.

### SVT-AV1

<https://gitlab.com/AOMediaCodec/SVT-AV1> — Clear BSD 3-Clause and BSD 2-Clause
terms (`svt-av1-LICENSE.md`, `svt-av1-LICENSE-BSD2.md`).

### dav1d

<https://code.videolan.org/videolan/dav1d> — BSD 2-Clause
(`dav1d-COPYING`).

### XZ Utils / liblzma

<https://tukaani.org/xz/> — liblzma uses the BSD Zero Clause licence
(`xz-COPYING`, `xz-COPYING.0BSD`).

### LAME

<https://lame.sourceforge.io/> — GNU Library General Public Licence,
version 2 or later (`lame-LICENSE`, `lame-COPYING`).

### mpg123

<https://www.mpg123.de/> — GNU Lesser General Public Licence,
version 2.1 (`mpg123-COPYING`).

### Opus

<https://www.opus-codec.org/> — BSD 3-Clause (`opus-COPYING`).

### libvpx

<https://www.webmproject.org/code/> — BSD 3-Clause (`libvpx-LICENSE`).

### x264 and x265

<https://www.videolan.org/developers/x264.html> and
<https://github.com/Multicorewareinc/x265> — GNU General Public Licence,
version 2 or later (`x264-COPYING`, `x265-COPYING`).

### OpenSSL

<https://openssl-library.org> — Apache License, Version 2.0
(`openssl@3-LICENSE.txt`).

---

## GRDB.swift 7.11.1

<https://github.com/groue/GRDB.swift>

MIT License

Copyright © 2015-2026 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## swift-snapshot-testing 1.19.6

<https://github.com/pointfreeco/swift-snapshot-testing>

MIT License

Copyright © 2019 Point-Free, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## swift-custom-dump 1.7.3

<https://github.com/pointfreeco/swift-custom-dump>

MIT License

Copyright © 2021 Point-Free, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## swift-issue-reporting 2.1.1

(formerly xctest-dynamic-overlay)

<https://github.com/pointfreeco/swift-issue-reporting>

MIT License

Copyright © 2021 Point-Free, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## SwiftSonic 0.9.0

<https://github.com/MathieuDubart/swiftsonic>

MIT License

Copyright (c) 2026 Mathieu Dubart

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## FeedKit 10.9.4

<https://github.com/nmdias/FeedKit>

Includes the XMLKit library, distributed as part of the FeedKit package under the same MIT license.

MIT License

Copyright (c) 2016 - 2025 Nuno Dias

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## swift-crypto 5.0.0

<https://github.com/apple/swift-crypto>

Cryptographic primitives for the Phone Sync feature. Licensed under the
**Apache License, Version 2.0**.

The Apache 2.0 full text is available at:
<https://www.apache.org/licenses/LICENSE-2.0>

---

## swift-certificates 1.21.0

<https://github.com/apple/swift-certificates>

X.509 certificate handling for the Phone Sync feature's mutual-TLS pairing.
Licensed under the **Apache License, Version 2.0**.

The Apache 2.0 full text is available at:
<https://www.apache.org/licenses/LICENSE-2.0>

---

## swift-asn1 1.7.3

<https://github.com/apple/swift-asn1>

ASN.1 encoding underneath swift-certificates. Licensed under the
**Apache License, Version 2.0**.

The Apache 2.0 full text is available at:
<https://www.apache.org/licenses/LICENSE-2.0>

---

## Podcast Index API

This product uses the Podcast Index API (<https://podcastindex.org>). Use of the Podcast Index API is subject to the Podcast Index API Terms of Service.

---

## Apple iTunes Search API

This product uses the Apple iTunes Search API. Use of the Apple iTunes Search API is subject to Apple's usage guidelines.

---

*This file was generated for WMusic 1.0.3. Swift package versions are
pinned in the workspace `Package.resolved`; bundled native libraries come
from the local Homebrew installation used to build the app.*
