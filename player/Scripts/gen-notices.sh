#!/bin/bash
set -euo pipefail

# Regenerate NOTICES.md with current dependency versions from Homebrew and
# the workspace Package.resolved.
#
# Usage: ./Scripts/gen-notices.sh
#
# This script:
# 1. Extracts the app version from Resources/Info.plist
# 2. Queries installed versions from Homebrew (ffmpeg, chromaprint, taglib)
# 3. Extracts SPM versions from the workspace Package.resolved (the single
#    source of truth for what builds actually link; per-module resolved
#    files are uncommitted side effects of local test runs)
# 4. Rewrites NOTICES.md with current versions and the license texts below
#
# A missing pin is a hard error: silent fallbacks to hardcoded versions are
# how this file drifted from reality once already.
#
# Run this after updating dependencies or before releases.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_PATH="${REPO_ROOT}/Resources/Info.plist"
NOTICES_PATH="${REPO_ROOT}/NOTICES.md"
RESOLVED_PATH="${REPO_ROOT}/Bocan.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# Extract version from Info.plist CFBundleShortVersionString
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${PLIST_PATH}")
echo "📦 App version: ${APP_VERSION}"

# Get installed versions from Homebrew
FFMPEG_VERSION=$(brew list --versions ffmpeg 2>/dev/null | awk '{print $2}' || echo "unknown")
CHROMAPRINT_VERSION=$(brew list --versions chromaprint 2>/dev/null | awk '{print $2}' || echo "unknown")
TAGLIB_VERSION=$(brew list --versions taglib 2>/dev/null | awk '{print $2}' || echo "unknown")

# The Homebrew FFmpeg formula can be built with GPL codecs. A hard-coded LGPL
# notice misstates the licence of that binary, so derive this paragraph from
# the exact FFmpeg installation that the local app build bundles.
FFMPEG_PREFIX=$(brew --prefix ffmpeg)
FFMPEG_BUILD_CONFIG=$("${FFMPEG_PREFIX}/bin/ffmpeg" -buildconf 2>/dev/null)
if [[ "${FFMPEG_BUILD_CONFIG}" == *--enable-nonfree* ]]; then
    echo "error: bundled FFmpeg enables non-free components; review its terms before generating notices" >&2
    exit 1
fi
if [[ "${FFMPEG_BUILD_CONFIG}" == *--enable-gpl* ]]; then
    if [[ "${FFMPEG_BUILD_CONFIG}" == *--enable-version3* ]]; then
        FFMPEG_LICENSE_NAME="GNU General Public Licence, version 3 or later (GPL 3+)"
        FFMPEG_LICENSE_FILE="COPYING.GPLv3"
        FFMPEG_LICENSE_URL="https://www.gnu.org/licenses/gpl-3.0.html"
    else
        FFMPEG_LICENSE_NAME="GNU General Public Licence, version 2 or later (GPL 2+)"
        FFMPEG_LICENSE_FILE="COPYING.GPLv2"
        FFMPEG_LICENSE_URL="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    fi
elif [[ "${FFMPEG_BUILD_CONFIG}" == *--enable-version3* ]]; then
    FFMPEG_LICENSE_NAME="GNU Lesser General Public Licence, version 3 or later (LGPL 3+)"
    FFMPEG_LICENSE_FILE="COPYING.LGPLv3"
    FFMPEG_LICENSE_URL="https://www.gnu.org/licenses/lgpl-3.0.html"
else
    FFMPEG_LICENSE_NAME="GNU Lesser General Public Licence, version 2.1 or later (LGPL 2.1+)"
    FFMPEG_LICENSE_FILE="COPYING.LGPLv2.1"
    FFMPEG_LICENSE_URL="https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html"
fi
[[ -f "${FFMPEG_PREFIX}/${FFMPEG_LICENSE_FILE}" ]] || {
    echo "error: missing FFmpeg licence ${FFMPEG_PREFIX}/${FFMPEG_LICENSE_FILE}" >&2
    exit 1
}

echo "📌 Dependency versions:"
echo "  - FFmpeg: ${FFMPEG_VERSION}"
echo "  - Chromaprint: ${CHROMAPRINT_VERSION}"
echo "  - TagLib: ${TAGLIB_VERSION}"

# Extract an SPM pin version from the workspace Package.resolved by identity.
# Takes one or more identities and uses the first that resolves, so a package
# renamed upstream can be found under either name while the toolchains
# disagree about which one to write. Still hard-fails when none of them is
# present, so a rename or removal cannot silently print a stale number.
extract_spm_version() {
    python3 - "$RESOLVED_PATH" "$@" << 'PY'
import json
import sys

path, identities = sys.argv[1], sys.argv[2:]
pins = {pin["identity"]: pin["state"]["version"] for pin in json.load(open(path))["pins"]}
for identity in identities:
    if identity in pins:
        print(pins[identity])
        sys.exit(0)
sys.exit(f"error: no pin in {path} with any of these identities: {', '.join(identities)}")
PY
}

GRDB_VERSION=$(extract_spm_version "grdb.swift")
SNAPSHOT_VERSION=$(extract_spm_version "swift-snapshot-testing")
CUSTOM_DUMP_VERSION=$(extract_spm_version "swift-custom-dump")
# Point-Free renamed xctest-dynamic-overlay to swift-issue-reporting. Xcode 27
# follows the rename when it resolves; 26.6 still writes the old identity.
ISSUE_REPORTING_VERSION=$(extract_spm_version "swift-issue-reporting" "xctest-dynamic-overlay")
SWIFTSONIC_VERSION=$(extract_spm_version "swiftsonic")
FEEDKIT_VERSION=$(extract_spm_version "feedkit")
CRYPTO_VERSION=$(extract_spm_version "swift-crypto")
CERTIFICATES_VERSION=$(extract_spm_version "swift-certificates")
ASN1_VERSION=$(extract_spm_version "swift-asn1")

echo "  - GRDB: ${GRDB_VERSION}"
echo "  - swift-snapshot-testing: ${SNAPSHOT_VERSION}"
echo "  - swift-custom-dump: ${CUSTOM_DUMP_VERSION}"
echo "  - swift-issue-reporting: ${ISSUE_REPORTING_VERSION}"
echo "  - SwiftSonic: ${SWIFTSONIC_VERSION}"
echo "  - FeedKit: ${FEEDKIT_VERSION}"
echo "  - swift-crypto: ${CRYPTO_VERSION}"
echo "  - swift-certificates: ${CERTIFICATES_VERSION}"
echo "  - swift-asn1: ${ASN1_VERSION}"

# Build the file by replacing version placeholders in the existing template sections
cat > "${NOTICES_PATH}" << EOF
# Third-Party Notices

WMusic is a local adaptation of [Bòcan](https://github.com/bocan/bocan-music)
by Chris Funderburg (Copyright 2026), licensed under the Apache License,
Version 2.0. The original copyright notice and full Apache 2.0 licence are
included in WMusic's bundled \`LICENSE\` file.

The following components retain their own authorship and licences. Their
notices and source links are listed here; applicable licence files for bundled
native libraries are also included in \`ThirdPartyLicenses\` in the app bundle.

---

## FFmpeg ${FFMPEG_VERSION}

<https://ffmpeg.org>

WMusic bundles FFmpeg libraries from Homebrew's FFmpeg build. The selected
configuration makes this FFmpeg build subject to the **${FFMPEG_LICENSE_NAME}**.
This designation applies to the FFmpeg build; separately bundled libraries
retain their own licences.

The applicable FFmpeg licence text is included as
\`ThirdPartyLicenses/ffmpeg-${FFMPEG_LICENSE_FILE}\` and is available at
<${FFMPEG_LICENSE_URL}>.

FFmpeg source code is available at <https://ffmpeg.org/download.html>.
The Homebrew formula used to build the bundled dylibs is
\`homebrew-core/Formula/f/ffmpeg.rb\`.

---

## TagLib ${TAGLIB_VERSION}

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

## Chromaprint / fpcalc ${CHROMAPRINT_VERSION}

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
\`ThirdPartyLicenses\` in the app bundle.

### SVT-AV1

<https://gitlab.com/AOMediaCodec/SVT-AV1> — Clear BSD 3-Clause and BSD 2-Clause
terms (\`svt-av1-LICENSE.md\`, \`svt-av1-LICENSE-BSD2.md\`).

### dav1d

<https://code.videolan.org/videolan/dav1d> — BSD 2-Clause
(\`dav1d-COPYING\`).

### XZ Utils / liblzma

<https://tukaani.org/xz/> — liblzma uses the BSD Zero Clause licence
(\`xz-COPYING\`, \`xz-COPYING.0BSD\`).

### LAME

<https://lame.sourceforge.io/> — GNU Library General Public Licence,
version 2 or later (\`lame-LICENSE\`, \`lame-COPYING\`).

### mpg123

<https://www.mpg123.de/> — GNU Lesser General Public Licence,
version 2.1 (\`mpg123-COPYING\`).

### Opus

<https://www.opus-codec.org/> — BSD 3-Clause (\`opus-COPYING\`).

### libvpx

<https://www.webmproject.org/code/> — BSD 3-Clause (\`libvpx-LICENSE\`).

### x264 and x265

<https://www.videolan.org/developers/x264.html> and
<https://github.com/Multicorewareinc/x265> — GNU General Public Licence,
version 2 or later (\`x264-COPYING\`, \`x265-COPYING\`).

### OpenSSL

<https://openssl-library.org> — Apache License, Version 2.0
(\`openssl@3-LICENSE.txt\`).

---

## GRDB.swift ${GRDB_VERSION}

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

## swift-snapshot-testing ${SNAPSHOT_VERSION}

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

## swift-custom-dump ${CUSTOM_DUMP_VERSION}

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

## swift-issue-reporting ${ISSUE_REPORTING_VERSION}

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

## SwiftSonic ${SWIFTSONIC_VERSION}

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

## FeedKit ${FEEDKIT_VERSION}

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

## swift-crypto ${CRYPTO_VERSION}

<https://github.com/apple/swift-crypto>

Cryptographic primitives for the Phone Sync feature. Licensed under the
**Apache License, Version 2.0**.

The Apache 2.0 full text is available at:
<https://www.apache.org/licenses/LICENSE-2.0>

---

## swift-certificates ${CERTIFICATES_VERSION}

<https://github.com/apple/swift-certificates>

X.509 certificate handling for the Phone Sync feature's mutual-TLS pairing.
Licensed under the **Apache License, Version 2.0**.

The Apache 2.0 full text is available at:
<https://www.apache.org/licenses/LICENSE-2.0>

---

## swift-asn1 ${ASN1_VERSION}

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

*This file was generated for WMusic ${APP_VERSION}. Swift package versions are
pinned in the workspace \`Package.resolved\`; bundled native libraries come
from the local Homebrew installation used to build the app.*
EOF

echo "✅ Generated ${NOTICES_PATH}"
