# sml-ogg

[![CI](https://github.com/sjqtentacles/sml-ogg/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-ogg/actions/workflows/ci.yml)

Ogg container **page parsing** for Standard ML. Scans a byte vector for `OggS`
capture patterns and splits it into pages, parses each page's fixed header
(version, flags, granule position, serial number, sequence number, CRC, and the
segment/lacing table), reassembles logical packets across page boundaries, and
validates page CRC-32 checksums.

## API

```sml
type page   = { header : Word8Vector.vector, body : Word8Vector.vector }
type header = { version : int, headerType : Word8.word, granulePos : LargeInt.int
              , serialNo : Word32.word, seqNo : Word32.word, crc : Word32.word
              , lacing : int list }

Ogg.capturePattern         (* the 4-byte "OggS" marker *)
Ogg.segment bytes          (* -> page list (skips junk between captures) *)
Ogg.pages bytes            (* alias for segment *)

Ogg.parseHeader page       (* -> header (raises Subscript on a truncated header) *)
Ogg.isContinuation header  (* flag 0x01 *)
Ogg.isBeginOfStream header (* flag 0x02 *)
Ogg.isEndOfStream header   (* flag 0x04 *)

Ogg.pagesForSerial bytes serial   (* pages of one logical stream *)
Ogg.packets pageList              (* reassemble logical packets (255-continuation) *)

Ogg.crc bytes              (* Ogg CRC-32 (poly 0x04C11DB7, no reflection) *)
Ogg.checkCrc page          (* recompute with CRC field zeroed and compare *)
```

`segment` walks the stream: it finds the next `OggS` page, reads the
segment-count byte and that many lacing values, sums them to get the body
length, slices out the `header`/`body`, and continues from the end of the page.
`packets` then glues page bodies into logical packets: a lacing value of 255
continues the current packet into the next segment (and across page
boundaries), while any value < 255 terminates it.

```sml
val pages = Ogg.segment bytes
val h     = Ogg.parseHeader (hd pages)
#serialNo h                               (* logical stream id *)
Ogg.packets pages                         (* logical packets, reassembled *)
Ogg.checkCrc (hd pages)                   (* true if the stored CRC matches *)
```

## Scope and limitations

- **Container framing only.** This separates Ogg pages and reassembles logical
  packets; it does not decode any codec carried inside them (Vorbis, Opus,
  FLAC-in-Ogg, etc.).
- The CRC uses the Ogg variant (MSB-first, polynomial `0x04C11DB7`, no
  input/output reflection, no final XOR); `checkCrc` zeroes the 4 CRC bytes
  before recomputing, per the spec.
- `parseHeader` assumes a well-formed fixed header; a header byte vector shorter
  than `27 + segmentCount` raises `Subscript`.

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-ogg
smlpkg sync
```

Reference from your `.mlb`:

```
lib/github.com/sjqtentacles/sml-ogg/ogg.mlb
```

## Building and testing

```sh
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make clean
```

## Project layout

```
sml.pkg
Makefile
lib/github.com/sjqtentacles/sml-ogg/
  ogg.sig
  ogg.sml      OggS page scanning, header parsing, packet reassembly, CRC-32
  ogg.mlb
test/
  test.sml     capture pattern, multi-page parse, headers, packets, CRC
```

## License

MIT. See [LICENSE](LICENSE).
